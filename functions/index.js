const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore, Timestamp, FieldValue } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");

initializeApp();
const db = getFirestore();

/**
 * Triggered when a new selection is created under any pair.
 *
 * Path: /pairs/{pairId}/selections/{selectionId}
 *
 * Logic:
 * 1. Read the new selection's userId and itemId.
 * 2. Look up the pair to find the other user.
 * 3. Query for the other user's active, unmatched selection of the same item
 *    where expiresAt > now.
 * 4. If found → it's a match!
 *    a. Mark both selections as matched (inside a transaction to prevent races).
 *    b. Create a pendingNotification with a random sendAt delay.
 */
exports.onSelectionCreated = onDocumentCreated(
    "pairs/{pairId}/selections/{selectionId}",
    async (event) => {
        const snapshot = event.data;
        if (!snapshot) return;

        const selectionData = snapshot.data();
        const { pairId } = event.params;

        // eslint-disable-next-line no-unused-vars
        const { userId, itemId, expiresAt, matched } = selectionData;

        // Don't process already-matched selections
        if (matched) return;

        // Get the pair to find the other user
        const pairDoc = await db.collection("pairs").doc(pairId).get();
        if (!pairDoc.exists) return;

        const pairData = pairDoc.data();
        const otherUserId = pairData.userA === userId
            ? pairData.userB
            : pairData.userA;

        // Use a transaction to prevent race conditions when both users
        // select the same item at nearly the same time.
        await db.runTransaction(async (transaction) => {
            // Re-read the other user's selection inside the transaction
            const otherSelectionsSnapshot = await transaction.get(
                db.collection("pairs").doc(pairId)
                    .collection("selections")
                    .where("userId", "==", otherUserId)
                    .where("itemId", "==", itemId)
                    .where("matched", "==", false)
                    .where("expiresAt", ">", Timestamp.now())
            );

            if (otherSelectionsSnapshot.empty) return;

            // Re-read the triggering selection to make sure it hasn't been matched
            const currentSelDoc = await transaction.get(snapshot.ref);
            if (!currentSelDoc.exists || currentSelDoc.data().matched) return;

            const otherSelDoc = otherSelectionsSnapshot.docs[0];

            // Mark both as matched
            transaction.update(snapshot.ref, { matched: true });
            transaction.update(otherSelDoc.ref, { matched: true });

            // Create pending notification with random delay: 1 to 15 minutes
            const delayMinutes = Math.floor(Math.random() * 15) + 1;
            const sendAt = new Date(Date.now() + delayMinutes * 60 * 1000);

            const notifRef = db.collection("pendingNotifications").doc();
            transaction.set(notifRef, {
                pairId,
                itemId,
                userAId: userId,
                userBId: otherUserId,
                sendAt: Timestamp.fromDate(sendAt),
                sent: false,
                createdAt: Timestamp.now(),
            });
        });

        console.log(
            `Match found! Item: ${itemId}, Users: ${userId} & ${otherUserId}`,
        );
    }
);

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
                data.userAId,
                data.userBId,
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
    // Look up the item label from a static map
    const itemLabels = {
        walk: "Go for a walk",
        workout: "Work out",
        movie: "Watch a movie",
        cook: "Cook together",
        game: "Play a game",
        drive: "Go for a drive",
        restaurant: "Go out to eat",
        cafe: "Hit a café",
        park: "Go to the park",
        beach: "Go to the beach",
        store: "Go shopping",
        drinks: "Drinks",
        coffee: "Coffee",
        snack: "Snack",
        chat: "Just talk",
        nap: "Nap time",
    };

    const label = itemLabels[itemId] || itemId;

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
    console.log(`Match: ${userAName} & ${userBName} both want: ${label}`);

    if (userAToken) {
        notifications.push(
            messaging.send({
                token: userAToken,
                notification: {
                    title: "It's a match! 🎉",
                    body: `You and ${userBName} both want: ${label}`,
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
                    body: `You and ${userAName} both want: ${label}`,
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
 * Runs every 15 minutes. Deletes expired, unmatched selections
 * to keep Firestore clean.
 */
exports.cleanupExpiredSelections = onSchedule("every 15 minutes", async () => {
    const now = Timestamp.now();

    // Get all active pairs
    const pairs = await db.collection("pairs")
        .where("active", "==", true)
        .get();

    let deletedCount = 0;

    for (const pairDoc of pairs.docs) {
        const expired = await pairDoc.ref
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
