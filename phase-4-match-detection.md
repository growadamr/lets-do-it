# Phase 4: Match Detection (Firebase Cloud Function)

## Goal
A Cloud Function triggers whenever a new selection is written. It checks if the other user in the pair has an active (unexpired, unmatched) selection for the same item. If yes, it creates a pending notification with a random delay.

---

## Step 4.1 — Initialize Firebase Cloud Functions

Run these commands in your terminal:

```bash
# Make sure Firebase CLI is installed
npm install -g firebase-tools

# Login to Firebase (if not already)
firebase login

# Navigate to project root and initialize Functions
cd /Users/adamgrow/hermGameTest
firebase init functions
```

During `firebase init`:
1. Select your existing Firebase project (`herm-app`).
2. Choose **JavaScript** (simpler for this project; TypeScript is fine too).
3. Say **Yes** to ESLint.
4. Say **Yes** to install dependencies.

This creates a `functions/` directory.

---

## Step 4.2 — Write the Match Detection Function

**File: `functions/index.js`** — replace the entire contents with:

```javascript
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
 *    a. Mark both selections as matched.
 *    b. Create a pendingNotification with a random sendAt delay.
 */
exports.onSelectionCreated = onDocumentCreated(
    "pairs/{pairId}/selections/{selectionId}",
    async (event) => {
        const snapshot = event.data;
        if (!snapshot) return;

        const selectionData = snapshot.data();
        const { pairId } = event.params;

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

        // Query for the other user's active selection of the same item
        const now = Timestamp.now();

        const otherSelections = await db
            .collection("pairs").doc(pairId)
            .collection("selections")
            .where("userId", "==", otherUserId)
            .where("itemId", "==", itemId)
            .where("matched", "==", false)
            .where("expiresAt", ">", now)
            .get();

        if (otherSelections.empty) {
            // No match — do nothing
            return;
        }

        // MATCH FOUND!
        const otherSelectionDoc = otherSelections.docs[0];

        // Mark both selections as matched
        const batch = db.batch();
        batch.update(snapshot.ref, { matched: true });
        batch.update(otherSelectionDoc.ref, { matched: true });

        // Calculate random delay: 1 to 15 minutes from now
        const delayMinutes = Math.floor(Math.random() * 15) + 1;
        const sendAt = new Date(Date.now() + delayMinutes * 60 * 1000);

        // Create pending notification
        batch.set(db.collection("pendingNotifications").doc(), {
            pairId: pairId,
            itemId: itemId,
            userAId: userId,
            userBId: otherUserId,
            sendAt: Timestamp.fromDate(sendAt),
            sent: false,
            createdAt: FieldValue.serverTimestamp(),
        });

        await batch.commit();

        console.log(
            `Match found! Item: ${itemId}, Users: ${userId} & ${otherUserId}. ` +
            `Notification scheduled for ${sendAt.toISOString()} (${delayMinutes}min delay)`
        );
    }
);

/**
 * Scheduled function that runs every minute.
 * Checks for pending notifications where sendAt <= now and sent == false.
 * Sends push notifications to both users and marks as sent.
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
            await sendMatchNotification(
                data.userAId,
                data.userBId,
                data.itemId
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

    if (userAToken) {
        notifications.push(
            messaging.send({
                token: userAToken,
                notification: {
                    title: "It's a match! 🎉",
                    body: `You and ${userBName} both want: ${label}`,
                },
                apns: {
                    payload: {
                        aps: {
                            sound: "default",
                            badge: 1,
                        },
                    },
                },
                data: {
                    type: "match",
                    itemId: itemId,
                },
            })
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
                apns: {
                    payload: {
                        aps: {
                            sound: "default",
                            badge: 1,
                        },
                    },
                },
                data: {
                    type: "match",
                    itemId: itemId,
                },
            })
        );
    }

    await Promise.all(notifications);
}
```

---

## Step 4.3 — Install Required Dependencies

```bash
cd /Users/adamgrow/hermGameTest/functions
npm install firebase-admin firebase-functions
```

---

## Step 4.4 — Deploy the Functions

```bash
cd /Users/adamgrow/hermGameTest
firebase deploy --only functions
```

Verify in Firebase Console → **Functions** that both functions appear:
- `onSelectionCreated` (Firestore trigger)
- `sendPendingNotifications` (Scheduled, every 1 minute)

---

## Step 4.5 — Test Match Detection Manually

You can test without push notifications by checking Firestore directly:

1. Open two simulators (or one simulator + one physical device).
2. Pair the two users (Phase 2).
3. On **User A's device**, tap "Drinks?" → checkmark appears.
4. On **User B's device**, tap "Drinks?" → checkmark appears.
5. Check Firestore:
   - Both selection docs under `pairs/{pairId}/selections` should now have `matched: true`.
   - A new doc should appear in `pendingNotifications` with `sent: false` and a `sendAt` in the future (1–15 min from now).
6. Wait for the scheduled function to run (within 1 minute of `sendAt`).
7. The `pendingNotifications` doc should update to `sent: true`.

> **Note**: Push notifications won't actually arrive yet — that requires APNs setup in Phase 5. But you can verify the entire match + scheduling pipeline works via Firestore.

---

## Step 4.6 — Add a Firestore Index

The query in `onSelectionCreated` uses a compound filter: `userId`, `itemId`, `matched`, `expiresAt`. Firestore requires a composite index for this.

**Option A (automatic):** Deploy the function, trigger it, and check the Firebase Functions logs. Firestore will log an error with a direct link to create the needed index. Click it.

**Option B (manual):** In Firebase Console → Firestore → Indexes → Composite, create:

| Collection Path | Fields | Order |
|----------------|--------|-------|
| `pairs/{pairId}/selections` | `userId` Ascending, `itemId` Ascending, `matched` Ascending, `expiresAt` Ascending | — |

---

## How Match Detection Works (Summary)

```
1. User A taps "Drinks"
   → Firestore: selection doc created (userId=A, itemId="drinks", matched=false)
   → Cloud Function fires: checks if User B has active "drinks" selection
   → User B has NOT selected "drinks" → no match → function exits

2. (20 minutes later) User B taps "Drinks"
   → Firestore: selection doc created (userId=B, itemId="drinks", matched=false)
   → Cloud Function fires: checks if User A has active "drinks" selection
   → User A's selection is still active (within 60-min window) → MATCH!
   → Both selections marked matched=true
   → pendingNotification created with sendAt = now + random(1-15min)

3. (random delay later) Scheduled function runs
   → Finds the pending notification where sendAt <= now
   → Sends push to both users: "You and [name] both want: Drinks!"
   → Marks notification as sent
```

---

## Verification Checklist

- [ ] `firebase deploy --only functions` succeeds without errors
- [ ] Both functions appear in Firebase Console → Functions
- [ ] Selecting the same item on both devices creates a `pendingNotifications` doc
- [ ] The `sendAt` field is 1–15 minutes in the future (random)
- [ ] Both selection docs have `matched: true` after a match
- [ ] The scheduled function runs and marks `sent: true` after `sendAt` passes
- [ ] No match occurs if only one user selects an item
- [ ] No match occurs if User A's selection has expired before User B selects
- [ ] Selecting different items does not produce a match

---

## File Structure After Phase 4

```
Herm/
├── (iOS project files from Phases 1-3)
├── firebase.json
├── .firebaserc
└── functions/
    ├── index.js
    ├── package.json
    └── node_modules/
```
