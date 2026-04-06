const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore, Timestamp, FieldValue } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");

initializeApp();
const db = getFirestore();

// Item labels for notifications
const ITEM_LABELS = {
    walk: { emoji: "🚶", label: "Go for a walk" },
    workout: { emoji: "💪", label: "Work out" },
    movie: { emoji: "🎬", label: "Watch a movie" },
    cook: { emoji: "🍳", label: "Cook together" },
    game: { emoji: "🎮", label: "Play a game" },
    drive: { emoji: "🚗", label: "Go for a drive" },
    restaurant: { emoji: "🍽️", label: "Go out to eat" },
    cafe: { emoji: "☕", label: "Hit a café" },
    park: { emoji: "🌳", label: "Go to the park" },
    beach: { emoji: "🏖️", label: "Go to the beach" },
    store: { emoji: "🛒", label: "Go shopping" },
    drinks: { emoji: "🍻", label: "Drinks" },
    coffee: { emoji: "☕", label: "Coffee" },
    snack: { emoji: "🍿", label: "Snack" },
    chat: { emoji: "💬", label: "Just talk" },
    nap: { emoji: "😴", label: "Nap time" },
};

/**
 * Resolves display info for an activity item.
 * First checks the hardcoded ITEM_LABELS map (catalog items).
 * If itemId starts with "custom_", fetches from either user's customActivities collection.
 * Falls back to { emoji: "🎯", label: itemId } if not found.
 */
async function resolveItemInfo(itemId, userAId, userBId) {
    // Check catalog items first
    const catalogInfo = ITEM_LABELS[itemId];
    if (catalogInfo) return catalogInfo;

    // Try fetching custom activity from either user's collection
    if (itemId.startsWith("custom_")) {
        const [docA, docB] = await Promise.all([
            db.collection("users").doc(userAId).collection("customActivities").doc(itemId).get(),
            db.collection("users").doc(userBId).collection("customActivities").doc(itemId).get(),
        ]);

        const data = docA.exists ? docA.data() : docB.exists ? docB.data() : null;
        if (data && data.emoji && data.label) {
            return { emoji: data.emoji, label: data.label };
        }
    }

    // Fallback
    return { emoji: "🎯", label: itemId };
}

/**
 * Checks if a custom activity match is valid based on visibility rules.
 * Returns true if at least one user owns the activity and has the other in visibleTo.
 * Returns true for non-custom items (no visibility check needed).
 */
async function checkCustomActivityVisibility(userId, targetUserId, itemId) {
    if (!itemId.startsWith("custom_")) return true;

    const [docA, docB] = await Promise.all([
        db.collection("users").doc(userId).collection("customActivities").doc(itemId).get(),
        db.collection("users").doc(targetUserId).collection("customActivities").doc(itemId).get(),
    ]);

    // User A owns it and has User B in visibleTo
    if (docA.exists) {
        const visibleTo = docA.data().visibleTo || [];
        if (visibleTo.includes(targetUserId)) return true;
    }

    // User B owns it and has User A in visibleTo
    if (docB.exists) {
        const visibleTo = docB.data().visibleTo || [];
        if (visibleTo.includes(userId)) return true;
    }

    return false;
}

/**
 * Runs every 5 minutes.
 * Scans all active unmatched selections and finds matches between contacts.
 * This avoids instant notifications — matches are only detected on the 5-min check.
 */
exports.checkForMatches = onSchedule("every 5 minutes", async () => {
    const now = Timestamp.now();

    // Get all users
    const usersSnapshot = await db.collection("users").get();
    if (usersSnapshot.empty) return;

    let matchCount = 0;

    for (const userDoc of usersSnapshot.docs) {
        const userId = userDoc.id;

        // Get all active, unmatched selections for this user
        const selectionsSnapshot = await userDoc.ref
            .collection("selections")
            .where("matched", "==", false)
            .get();

        if (selectionsSnapshot.empty) continue;

        for (const selection of selectionsSnapshot.docs) {
            const data = selection.data();
            const { itemId, targetUserId, expiresAt } = data;

            if (!targetUserId || !expiresAt) continue;

            // Skip expired selections
            if (expiresAt.toMillis() <= now.toMillis()) continue;

            // Avoid duplicate notifications: check if a pending notification already exists
            const existingNotifs = await db.collection("pendingNotifications")
                .where("userId", "==", userId)
                .where("targetUserId", "==", targetUserId)
                .where("itemId", "==", itemId)
                .where("sent", "==", false)
                .get();

            if (!existingNotifs.empty) continue;

            // Check if the target user has a matching selection back
            const targetSelectionsSnapshot = await db.collection("users")
                .doc(targetUserId)
                .collection("selections")
                .where("matched", "==", false)
                .get();

            for (const targetSel of targetSelectionsSnapshot.docs) {
                const targetData = targetSel.data();
                if (
                    targetData.itemId === itemId &&
                    targetData.targetUserId === userId &&
                    targetData.expiresAt &&
                    targetData.expiresAt.toMillis() > now.toMillis()
                ) {
                    // For custom activities, verify visibility before confirming match
                    const isVisible = await checkCustomActivityVisibility(
                        userId,
                        targetUserId,
                        itemId,
                    );
                    if (!isVisible) {
                        console.log(
                            `Match SKIPPED (visibility check failed): Item: ${itemId}, Users: ${userId} & ${targetUserId}`,
                        );
                        continue;
                    }

                    // It's a match! Mark both and create notification
                    await db.runTransaction(async (transaction) => {
                        // Re-check both are still unmatched
                        const selDoc = await transaction.get(selection.ref);
                        if (!selDoc.exists || selDoc.data().matched) return;

                        const targetSelDoc = await transaction.get(targetSel.ref);
                        if (!targetSelDoc.exists || targetSelDoc.data().matched) return;

                        transaction.update(selection.ref, { matched: true });
                        transaction.update(targetSel.ref, { matched: true });

                        // Create pending notification with random delay: 1 to 10 minutes
                        const delayMinutes = Math.floor(Math.random() * 10) + 1;
                        const sendAt = new Date(Date.now() + delayMinutes * 60 * 1000);

                        const notifRef = db.collection("pendingNotifications").doc();
                        transaction.set(notifRef, {
                            userId,
                            targetUserId,
                            itemId,
                            sendAt: Timestamp.fromDate(sendAt),
                            sent: false,
                            createdAt: Timestamp.now(),
                        });
                    });

                    console.log(
                        `Match found! Item: ${itemId}, Users: ${userId} & ${targetUserId}`,
                    );
                    matchCount++;
                }
            }
        }
    }

    if (matchCount > 0) {
        console.log(`Found ${matchCount} new match(s)`);
    }
});

/**
 * Scheduled function that runs every minute.
 * Checks for pending notifications where sendAt <= now and sent == false.
 * Sends push notifications to both users (if FCM tokens exist) and marks as sent.
 * Also logs to console for in-app notification fallback.
 */
exports.sendPendingNotifications = onSchedule("every 1 minutes", async () => {
    const now = Timestamp.now();

    const pending = await db.collection("pendingNotifications")
        .where("sent", "==", false)
        .where("sendAt", "<=", now)
        .get();

    if (pending.empty) return;

    console.log(`Processing ${pending.size} pending notification(s)`);

    for (const doc of pending.docs) {
        const data = doc.data();

        try {
            // Try to send push notifications (graceful if no FCM tokens)
            await sendMatchNotification(
                data.userId,
                data.targetUserId,
                data.itemId,
            );

            // Mark as sent
            await doc.ref.update({ sent: true });

            console.log(`Sent notification for item: ${data.itemId}`);
        } catch (error) {
            console.error(`Failed to send notification: ${error}`);
        }
    }
});

/**
 * Sends a push notification to both users about a matched item.
 * If a user has no FCM token, the notification is logged to console only.
 * @param {string} userAId - The ID of user A.
 * @param {string} userBId - The ID of user B.
 * @param {string} itemId - The ID of the matched item.
 */
async function sendMatchNotification(userAId, userBId, itemId) {
    const itemInfo = await resolveItemInfo(itemId, userAId, userBId);

    // Get both users' FCM tokens and display names
    const [userADoc, userBDoc] = await Promise.all([
        db.collection("users").doc(userAId).get(),
        db.collection("users").doc(userBId).get(),
    ]);

    const userAData = userADoc.data();
    const userBData = userBDoc.data();

    const userAToken = userAData?.fcmToken;
    const userBToken = userBData?.fcmToken;
    const userAName = userAData?.displayName || "Your person";
    const userBName = userBData?.displayName || "Your person";

    const messaging = getMessaging();
    const notifications = [];

    // Log to console for in-app fallback
    console.log(
        `Match: ${userAName} & ${userBName} both want: ${itemInfo.emoji} ${itemInfo.label}`,
    );

    if (userAToken) {
        notifications.push(
            messaging.send({
                token: userAToken,
                notification: {
                    title: "It's a match! 🎉",
                    body: `You and ${userBName} both want: ${itemInfo.emoji} ${itemInfo.label}`,
                },
                data: {
                    type: "match",
                    itemId: itemId,
                },
            }),
        );
    }

    if (userBToken) {
        notifications.push(
            messaging.send({
                token: userBToken,
                notification: {
                    title: "It's a match! 🎉",
                    body: `You and ${userAName} both want: ${itemInfo.emoji} ${itemInfo.label}`,
                },
                data: {
                    type: "match",
                    itemId: itemId,
                },
            }),
        );
    }

    if (notifications.length > 0) {
        await Promise.all(notifications);
    }
}

/**
 * Triggered when a user adds someone as a contact.
 * Automatically adds the reverse contact (bidirectional) with an empty display name.
 */
exports.onContactAdded = onDocumentCreated(
    "users/{userId}/contacts/{contactId}",
    async (event) => {
        const { userId, contactId } = event.params;

        // Check if the reverse contact already exists
        const reverseContactDoc = await db.collection("users")
            .doc(contactId)
            .collection("contacts")
            .doc(userId)
            .get();

        if (reverseContactDoc.exists) return;

        // Add the reverse contact with an empty display name
        // (each user sets their own display name for the contact)
        await db.collection("users")
            .doc(contactId)
            .collection("contacts")
            .doc(userId)
            .set({
                uid: userId,
                displayName: "",
                addedAt: FieldValue.serverTimestamp(),
            });

        console.log(
            `Bidirectional contact added: ${contactId} -> ${userId}`,
        );
    }
);

/**
 * Runs every 15 minutes. Deletes expired, unmatched selections
 * to keep Firestore clean.
 */
exports.cleanupExpiredSelections = onSchedule("every 15 minutes", async () => {
    const now = Timestamp.now();

    // Get all users
    const users = await db.collection("users").get();

    let deletedCount = 0;

    for (const userDoc of users.docs) {
        const expired = await userDoc.ref
            .collection("selections")
            .where("matched", "==", false)
            .where("expiresAt", "<=", now)
            .get();

        for (const sel of expired.docs) {
            await sel.ref.delete();
            deletedCount++;
        }
    }

    if (deletedCount > 0) {
        console.log(`Cleaned up ${deletedCount} expired selections`);
    }
});
