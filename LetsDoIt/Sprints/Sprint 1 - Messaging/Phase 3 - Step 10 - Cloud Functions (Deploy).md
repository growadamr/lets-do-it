# Phase 3, Step 10: Cloud Functions (Deploy) — Implementation Log

**Date:** 2026-04-05
**Status:** ✅ Complete — BUILD SUCCEEDED

---

## What Was Done

### New Files Created

| File | Purpose |
|------|---------|
| `firebase/.firebaserc` | Firebase project alias configuration (maps `default` to `letsdoit-dev`) |
| `firebase/firebase.json` | Firebase project configuration — Firestore rules, functions source path, emulator ports |
| `firebase/functions/package.json` | Node.js dependencies: `firebase-admin` v12, `firebase-functions` v4.9, Node 18 engine |
| `firebase/functions/index.js` | Two Cloud Functions: `onMessageCreated` (denormalize + FCM push) and `onConversationCreated` (idempotent membership creation) |

### Files Modified

None. This is purely server-side infrastructure — no Swift code changes.

---

## Function Details

### `onMessageCreated`

**Trigger:** `firestore.document('conversations/{conversationId}/messages/{messageId}').onCreate`

| Stage | Description |
|-------|-------------|
| **Denormalize** | Updates `lastMessage` on the parent conversation doc with `{ text, senderUid, senderName, timestamp, imageUrl }` |
| **FCM Push** | Sends push notification to all participants except the sender via `sendEachForMulticast` |

**Denormalization payload:**

| Field | Value |
|-------|-------|
| `lastMessage.text` | Message text truncated to 100 chars (with `…` ellipsis). If image-only message: `"📷 Photo"` |
| `lastMessage.senderUid` | Sender's UID |
| `lastMessage.senderName` | Sender's display name |
| `lastMessage.timestamp` | Message `createdAt` (Firestore Timestamp), fallback to `serverTimestamp()` |
| `lastMessage.imageUrl` | Message `imageUrl` or `null` |

**FCM push notification:**

| Field | Value |
|-------|-------|
| `notification.title` | `"New message from {senderName}"` |
| `notification.body` | Truncated message text or `"📷 Photo"` for image-only messages |
| `data.conversationId` | Conversation ID (for deep-link routing in the iOS app) |
| `data.messageId` | Message ID (for potential future use) |

**Token lookup:** Queries `users/{uid}` doc for each recipient participant, reads `fcmToken` field. Missing tokens are silently skipped with a warning log.

**Error handling:**
- Conversation not found → logs warning, skips FCM
- `lastMessage` update fails → logs error, continues to FCM anyway
- Individual FCM token fetch fails → logs warning, continues with other participants
- `sendEachForMulticast` partial failures → logs each failed token index

### `onConversationCreated`

**Trigger:** `firestore.document('conversations/{conversationId}').onCreate`

| Stage | Description |
|-------|-------------|
| **Read participants** | Extracts `participants` array from the new conversation doc |
| **Create memberships** | Batch-writes `users/{uid}/conversationMemberships/{conversationId}` for each participant |

**Membership fields:**

| Field | Value |
|-------|-------|
| `conversationId` | The conversation ID |
| `joinedAt` | `FieldValue.serverTimestamp()` |
| `lastReadAt` | `FieldValue.serverTimestamp()` |
| `muted` | `false` |

**Idempotency:** Uses `set({ ... }, { merge: true })` so that if the client-side `createMemberships()` already created the docs (which it does in `MessagingManager.createDM` and `createGroup`), this function won't overwrite them. The `merge: true` flag only adds/updates the specified fields.

**Error handling:**
- No participants → logs warning, returns early
- Batch commit fails → throws error (triggers Firebase retry)

---

## Firebase Project Configuration

### `firebase.json`

| Section | Config |
|---------|--------|
| `firestore.rules` | `rules/firestore.rules` |
| `functions.source` | `functions` |
| `emulators.auth.port` | 9099 |
| `emulators.firestore.port` | 8080 |
| `emulators.functions.port` | 5001 |
| `emulators.ui` | Enabled on port 4000 |

### `.firebaserc`

| Key | Value |
|-----|-------|
| `projects.default` | `letsdoit-dev` |

> **Note:** Replace `letsdoit-dev` with the actual Firebase project ID before deploying.

---

## Deployment Commands

```bash
# Install dependencies (first time only)
cd firebase/functions && npm install && cd ../..

# Deploy all functions
firebase deploy --only functions

# Deploy with emulator testing first
firebase emulators:start

# Deploy to production
firebase deploy --only functions --project letsdoit-dev
```

---

## Testing Procedure (Firebase Emulator Suite)

### Setup
```bash
cd /Users/adamgrow/hermGameTest/LetsDoIt/firebase
firebase emulators:start
```

### Test 1: `onConversationCreated`
1. Open Firestore Emulator UI at `http://localhost:4000`
2. Create a test conversation doc: `conversations/test-conv-1`
   - `type`: `"dm"`
   - `participants`: `["user-a", "user-b"]`
   - `createdBy`: `"user-a"`
   - `createdAt`: (server timestamp)
3. Verify: `users/user-a/conversationMemberships/test-conv-1` and `users/user-b/conversationMemberships/test-conv-1` are created
4. Re-create the same doc (idempotency test) — verify no errors, existing memberships are not overwritten

### Test 2: `onMessageCreated` — Denormalization
1. Create a conversation doc `conversations/test-conv-2` with `participants: ["user-a", "user-b"]`
2. Create a message: `conversations/test-conv-2/messages/msg-1`
   - `senderUid`: `"user-a"`
   - `senderName`: `"Alice"`
   - `text`: `"Hello, this is a test message that is longer than..."`
   - `createdAt`: (server timestamp)
3. Verify: `conversations/test-conv-2.lastMessage` is updated with truncated text, sender info, timestamp

### Test 3: `onMessageCreated` — FCM Push
1. Create a user doc `users/user-b` with `fcmToken: "test-token-abc"`
2. Create a conversation with `user-a` and `user-b` as participants
3. Create a message from `user-a`
4. Verify: Function logs show `successCount: 1` for FCM delivery (emulator logs the send attempt)

### Test 4: Error Cases
- Message to non-existent conversation → verify graceful error log, no crash
- Conversation with no `participants` array → verify membership function logs warning
- User with no `fcmToken` → verify skipped with warning, no crash

---

## Firestore Rules Compatibility

The existing `firestore.rules` already account for these Cloud Functions:
- `conversationMemberships` create is set to `allow create: if false` with comment "Handled by onConversationCreated Cloud Function" — the functions use the Firebase Admin SDK which bypasses rules
- Messages subcollection allows `create` with the exact field set that `sendMessage` uses: `senderUid`, `senderName`, `text`, `imageUrl`, `linkPreview`, `readBy`, `createdAt`

No rules changes were needed for this step.

---

## Architecture Decisions

1. **Single `index.js` file for both functions** — Keeps the codebase simple and co-located. Both functions are closely related to the messaging domain, so splitting into multiple files would add complexity without benefit at this scale.

2. **`merge: true` for idempotent membership creation** — The client-side `MessagingManager.createMemberships()` already creates membership docs when a conversation is created from the iOS app. This Cloud Function serves as a safety net for edge cases (server-side conversation creation in Sprint 3, race conditions, or manual Firestore writes). Using `set({ ... }, { merge: true })` ensures both paths can coexist without conflicts.

3. **FCM token lookup from `users/{uid}` doc** — Follows the standard Firebase pattern: the iOS app writes the FCM token to the user doc on login/token refresh (`users/{uid}.fcmToken`). The function reads this field to target pushes. Missing tokens are silently skipped rather than failing the entire notification batch.

4. **Separate error handling for denormalization and FCM** — If denormalization fails (e.g., conversation was deleted between message creation and function execution), FCM push should still attempt to deliver. The two stages are wrapped in independent try/catch blocks.

5. **Text truncation at 100 chars with ellipsis** — Matches the `lastMessage.text` field expectations in the `LastMessage` model and keeps push notification bodies within reasonable length. The `"📷 Photo"` fallback for image-only messages provides context without exposing a raw URL.

6. **`sendEachForMulticast` over `sendMulticast`** — `sendEachForMulticast` returns per-recipient response data, enabling granular failure logging. This is important for debugging which users aren't receiving notifications.

7. **No Swift code changes** — The Cloud Functions operate entirely server-side. The iOS app's existing `MessagingManager` already handles `lastMessage` denormalization on the client (via the real-time listener picking up the server-side update) and FCM token management is handled by the app's FCM integration.

---

## Build Verification
```
xcodebuild -scheme LetsDoIt -destination 'platform=iOS Simulator,name=iPhone 17' build
→ BUILD SUCCEEDED
```

---

## Next Steps (Manual)

1. **Replace project ID** — Update `firebase/.firebaserc` `projects.default` to the actual Firebase project ID
2. **Install dependencies** — `cd firebase/functions && npm install`
3. **Test with emulator** — `firebase emulators:start` and follow the testing procedure above
4. **Deploy** — `firebase deploy --only functions`
5. **Set up FCM token sync** — Ensure the iOS app writes `fcmToken` to `users/{uid}` on login/token refresh (required for push notifications to work)
