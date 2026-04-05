/**
 * LetsDoIt — Firebase Cloud Functions
 *
 * Functions:
 *   1. onMessageCreated      — Denormalizes lastMessage on conversation doc + sends FCM push
 *   2. onConversationCreated — Creates conversationMemberships for each participant (idempotent)
 */

const functions = require("firebase-functions");
const admin = require("firebase-admin");
const { FieldValue } = require("firebase-admin/firestore");

admin.initializeApp();

const db = admin.firestore();

// ============================================================
// 1. onMessageCreated
// ============================================================
// Triggered when a new message is created in a conversation.
// Denormalizes lastMessage onto the conversation document and
// sends FCM push notifications to all participants except the sender.
// ============================================================

exports.onMessageCreated = functions.firestore
  .document("conversations/{conversationId}/messages/{messageId}")
  .onCreate(async (snapshot, context) => {
    const conversationId = context.params.conversationId;
    const messageId = context.params.messageId;

    const messageData = snapshot.data();
    const senderUid = messageData.senderUid;
    const senderName = messageData.senderName || "Someone";
    const text = messageData.text || "";
    const imageUrl = messageData.imageUrl;
    const createdAt = messageData.createdAt; // Firestore Timestamp

    // --- Step 1: Denormalize lastMessage on conversation doc ---

    const truncatedText = text.length > 100 ? text.substring(0, 100) + "…" : text;

    const lastMessagePayload = {
      text: imageUrl && !text ? "📷 Photo" : truncatedText,
      senderUid: senderUid,
      senderName: senderName,
      timestamp: createdAt || FieldValue.serverTimestamp(),
      imageUrl: imageUrl || null,
    };

    const conversationRef = db.collection("conversations").doc(conversationId);

    try {
      await conversationRef.update({ lastMessage: lastMessagePayload });
      functions.logger.info("Denormalized lastMessage", { conversationId, messageId });
    } catch (err) {
      functions.logger.error("Failed to update lastMessage", {
        conversationId,
        messageId,
        error: err,
      });
      // Continue to FCM even if denormalization fails
    }

    // --- Step 2: Send FCM push to participants except sender ---

    try {
      const convDoc = await conversationRef.get();
      if (!convDoc.exists) {
        functions.logger.warn("Conversation not found for FCM", { conversationId });
        return null;
      }

      const convData = convDoc.data();
      const participants = convData.participants || [];

      // Exclude sender
      const recipientUids = participants.filter((uid) => uid !== senderUid);
      if (recipientUids.length === 0) {
        return null; // No one else to notify
      }

      // Look up FCM tokens for all recipients
      const tokens = [];
      for (const uid of recipientUids) {
        try {
          const userDoc = await db.collection("users").doc(uid).get();
          if (userDoc.exists) {
            const userData = userDoc.data();
            if (userData.fcmToken) {
              tokens.push(userData.fcmToken);
            }
          }
        } catch (err) {
          functions.logger.warn("Failed to fetch FCM token for user", { uid, error: err });
        }
      }

      if (tokens.length === 0) {
        functions.logger.info("No FCM tokens found for recipients", { conversationId });
        return null;
      }

      // Build notification payload
      const notificationBody = imageUrl && !text ? "📷 Photo" : truncatedText;
      const message = {
        notification: {
          title: `New message from ${senderName}`,
          body: notificationBody,
        },
        data: {
          conversationId: conversationId,
          messageId: messageId,
        },
        tokens: tokens,
      };

      const response = await admin.messaging().sendEachForMulticast(message);

      functions.logger.info("FCM push sent", {
        conversationId,
        successCount: response.successCount,
        failureCount: response.failureCount,
      });

      // Log individual failures for debugging
      if (response.failureCount > 0) {
        response.responses.forEach((resp, idx) => {
          if (!resp.success) {
            functions.logger.warn("FCM failed for token", {
              tokenIndex: idx,
              error: resp.error,
            });
          }
        });
      }
    } catch (err) {
      functions.logger.error("FCM push failed", { conversationId, messageId, error: err });
    }

    return null;
  });

// ============================================================
// 2. onConversationCreated
// ============================================================
// Triggered when a new conversation is created.
// Creates conversationMemberships for each participant.
// Uses merge: true for idempotency (client may create memberships first).
// ============================================================

exports.onConversationCreated = functions.firestore
  .document("conversations/{conversationId}")
  .onCreate(async (snapshot, context) => {
    const conversationId = context.params.conversationId;
    const data = snapshot.data();

    const participants = data.participants || [];
    if (participants.length === 0) {
      functions.logger.warn("No participants on new conversation", { conversationId });
      return null;
    }

    const now = FieldValue.serverTimestamp();
    const batch = db.batch();

    for (const uid of participants) {
      const membershipRef = db
        .collection("users")
        .doc(uid)
        .collection("conversationMemberships")
        .doc(conversationId);

      // Use set with merge: true — idempotent, won't overwrite existing memberships
      batch.set(
        membershipRef,
        {
          conversationId: conversationId,
          joinedAt: now,
          lastReadAt: now,
          muted: false,
        },
        { merge: true }
      );
    }

    try {
      await batch.commit();
      functions.logger.info("Created conversationMemberships", {
        conversationId,
        participantCount: participants.length,
      });
    } catch (err) {
      functions.logger.error("Failed to create conversationMemberships", {
        conversationId,
        error: err,
      });
      throw err; // Retry on failure
    }

    return null;
  });
