/**
 * LetsDoIt — Firebase Cloud Functions
 *
 * Functions:
 *   1. onMessageCreated      — Denormalizes lastMessage on conversation doc + sends FCM push
 *   2. onConversationCreated — Creates conversationMemberships for each participant (idempotent)
 *   3. onEventCreated        — Sends FCM push to event invitees when event is created
 *   4. onEventUpdated        — Sends FCM push on event detail changes or RSVP changes
 *   5. cleanupPastEvents     — Daily scheduled cleanup of events past their date by 7+ days
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

// ============================================================
// 3. onEventCreated
// ============================================================
// Triggered when a new event is created.
// Sends FCM push notifications to all invitees (excluding the creator).
// ============================================================

exports.onEventCreated = functions.firestore
  .document("events/{eventId}")
  .onCreate(async (snapshot, context) => {
    const eventId = context.params.eventId;
    const eventData = snapshot.data();

    const title = eventData.title || "An event";
    const createdBy = eventData.createdBy;
    const invitees = eventData.invitees || [];
    const dateTime = eventData.dateTime; // Firestore Timestamp
    const location = eventData.location;

    // Exclude creator from notification recipients
    const recipientUids = invitees.filter((uid) => uid !== createdBy);
    if (recipientUids.length === 0) {
      functions.logger.info("No invitees to notify (or only creator)", { eventId });
      return null;
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
      functions.logger.info("No FCM tokens found for invitees", { eventId });
      return null;
    }

    // Build notification payload
    let body = `You've been invited to "${title}"`;
    if (dateTime) {
      const date = dateTime.toDate();
      body += ` on ${date.toLocaleDateString()}`;
    }
    if (location) {
      const truncatedLoc = location.length > 50 ? location.substring(0, 50) + "…" : location;
      body += ` at ${truncatedLoc}`;
    }

    const message = {
      notification: {
        title: "New event invitation",
        body: body,
      },
      data: {
        eventId: eventId,
      },
      tokens: tokens,
    };

    try {
      const response = await admin.messaging().sendEachForMulticast(message);

      functions.logger.info("FCM push sent for new event", {
        eventId,
        successCount: response.successCount,
        failureCount: response.failureCount,
      });

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
      functions.logger.error("FCM push failed for new event", { eventId, error: err });
    }

    return null;
  });

// ============================================================
// 4. onEventUpdated
// ============================================================
// Triggered when an event document is updated.
// - RSVP changes → push to creator with "{name} {accepted/declined/maybe'd} your event"
// - Detail changes (dateTime, location, status) → push to all invitees
// ============================================================

exports.onEventUpdated = functions.firestore
  .document("events/{eventId}")
  .onUpdate(async (change, context) => {
    const eventId = context.params.eventId;
    const before = change.before.data();
    const after = change.after.data();

    const title = after.title || "An event";
    const createdBy = after.createdBy;
    const invitees = after.invitees || [];
    const tokens = [];

    // --- Detect RSVP changes ---

    const beforeRsvps = before.rsvps || {};
    const afterRsvps = after.rsvps || {};

    // Find UIDs whose RSVP status changed (new or modified)
    const changedRsvpUids = [];
    for (const uid of Object.keys(afterRsvps)) {
      if (!beforeRsvps.hasOwnProperty(uid) || beforeRsvps[uid] !== afterRsvps[uid]) {
        changedRsvpUids.push(uid);
      }
    }

    if (changedRsvpUids.length > 0) {
      // Notify the creator about RSVP changes
      try {
        const creatorDoc = await db.collection("users").doc(createdBy).get();
        let creatorToken = null;
        if (creatorDoc.exists && creatorDoc.data().fcmToken) {
          creatorToken = creatorDoc.data().fcmToken;
        }

        if (creatorToken) {
          // Look up names for changed RSVPs and build messages
          for (const uid of changedRsvpUids) {
            const status = afterRsvps[uid];
            let name = "Someone";
            try {
              const userDoc = await db.collection("users").doc(uid).get();
              if (userDoc.exists) {
                name = userDoc.data().displayName || "Someone";
              }
            } catch (err) {
              functions.logger.warn("Failed to fetch user name for RSVP notification", { uid, error: err });
            }

            let verb = "updated their RSVP for";
            if (status === "accepted") verb = "accepted your event";
            else if (status === "declined") verb = "declined your event";
            else if (status === "maybe") verb = "said maybe to your event";

            const rsvpMessage = {
              notification: {
                title: `${name} ${verb}`,
                body: `"${title}"`,
              },
              data: {
                eventId: eventId,
              },
              tokens: [creatorToken],
            };

            await admin.messaging().sendEachForMulticast(rsvpMessage);
            functions.logger.info("RSVP notification sent", { eventId, uid, status });
          }
        }
      } catch (err) {
        functions.logger.error("Failed to send RSVP notification to creator", { eventId, error: err });
      }
    }

    // --- Detect event detail changes (dateTime, location, status) ---

    const dateTimeChanged = before.dateTime && after.dateTime && !before.dateTime.isEqual(after.dateTime);
    const locationChanged = (before.location || "") !== (after.location || "");
    const statusChanged = (before.status || "active") !== (after.status || "active");

    if (dateTimeChanged || locationChanged || statusChanged) {
      // Build tokens for all invitees
      for (const uid of invitees) {
        try {
          const userDoc = await db.collection("users").doc(uid).get();
          if (userDoc.exists && userDoc.data().fcmToken) {
            tokens.push(userDoc.data().fcmToken);
          }
        } catch (err) {
          functions.logger.warn("Failed to fetch FCM token for event update notification", { uid, error: err });
        }
      }

      if (tokens.length > 0) {
        let body = `Event "${title}" has been updated.`;
        if (statusChanged && after.status === "cancelled") {
          body = `Event "${title}" has been cancelled.`;
        } else if (dateTimeChanged && locationChanged) {
          body = `Event "${title}" date and location changed.`;
        } else if (dateTimeChanged) {
          body = `Event "${title}" date has changed.`;
        } else if (locationChanged) {
          body = `Event "${title}" location has changed.`;
        }

        const message = {
          notification: {
            title: "Event updated",
            body: body,
          },
          data: {
            eventId: eventId,
          },
          tokens: tokens,
        };

        try {
          const response = await admin.messaging().sendEachForMulticast(message);

          functions.logger.info("FCM push sent for event update", {
            eventId,
            successCount: response.successCount,
            failureCount: response.failureCount,
          });
        } catch (err) {
          functions.logger.error("FCM push failed for event update", { eventId, error: err });
        }
      }
    }

    return null;
  });

// ============================================================
// 5. cleanupPastEvents
// ============================================================
// Scheduled daily (3:00 AM UTC).
// Deletes events whose dateTime is more than 7 days in the past and status is "active".
// ============================================================

exports.cleanupPastEvents = functions.pubsub
  .schedule("0 3 * * *")
  .timeZone("UTC")
  .onRun(async (context) => {
    const now = new Date();
    const sevenDaysAgo = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000);

    try {
      const snapshot = await db
        .collection("events")
        .where("dateTime", "<", admin.firestore.Timestamp.fromDate(sevenDaysAgo))
        .where("status", "==", "active")
        .get();

      if (snapshot.empty) {
        functions.logger.info("No past events to clean up");
        return null;
      }

      functions.logger.info("Found past events to clean up", { count: snapshot.size });

      const batch = db.batch();
      snapshot.docs.forEach((doc) => {
        batch.delete(doc.ref);
      });

      await batch.commit();
      functions.logger.info("Cleaned up past events", { deletedCount: snapshot.size });
    } catch (err) {
      functions.logger.error("Failed to clean up past events", { error: err });
      throw err; // Retry on failure
    }

    return null;
  });
