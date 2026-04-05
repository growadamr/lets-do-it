# Phase 1, Step 4: MessagingManager Service — Implementation Log

**Date:** 2026-04-05
**Status:** ✅ Complete — BUILD SUCCEEDED

---

## What Was Done

### New Files Created

| File | Purpose |
|------|---------|
| `Services/MessagingManager.swift` | Full messaging service — conversation CRUD, message CRUD, image upload, real-time listeners, cursor-based pagination |

### Files Modified

None.

---

## Service Details

### `MessagingManager`

```swift
@MainActor class MessagingManager: ObservableObject
```

| Property | Type | Notes |
|---|---|---|
| `shared` | `static MessagingManager` | Singleton instance |
| `conversations` | `@Published [Conversation]` | Auto-updated by real-time listener |
| `messages` | `@Published [Message]` | Auto-updated by real-time listener |

### Conversation Operations

| Method | Description |
|---|---|
| `createDM(with:)` | Creates 1-on-1 DM. Queries existing `dm` conversations first to avoid duplicates. Returns existing if found. |
| `createGroup(name:participantUids:)` | Creates group conversation with name and participants. Creator is auto-added. |
| `deleteConversation(_:)` | Deletes conversation doc, all messages in subcollection, and all membership docs (batched). |
| `updateConversationName(_:conversationId:)` | Updates group conversation name. |
| `startListeningConversations()` | Real-time listener on `conversations` where current user is in `participants`. Sorted by `lastMessage.timestamp` desc. |
| `stopListeningConversations()` | Removes listener, clears published array. |

### Message Operations

| Method | Description |
|---|---|
| `sendMessage(text:conversationId:imageUrl:)` | Creates message doc in `conversations/{id}/messages`. Initializes `readBy` with sender UID. |
| `fetchMessages(conversationId:cursor:)` | Cursor-based pagination — 50 messages per page, ordered by `createdAt` descending. Returns `(messages, nextCursor)`. |
| `deleteMessage(_:from:)` | Deletes message doc. If has `imageUrl`, also deletes from Firebase Storage. |
| `markMessagesRead(conversationId:)` | Batch updates `readBy[myUid]` on all unread messages. Also updates membership `lastReadAt`. |
| `startListeningMessages(conversationId:)` | Real-time listener on messages subcollection, ordered by `createdAt` ascending. |
| `stopListeningMessages()` | Removes listener, clears published array. |

### Image Upload

| Method | Description |
|---|---|
| `uploadImage(_:conversationId:messageId:)` | Resizes UIImage to max 1024px longest edge, compresses to JPEG 0.7 quality, uploads to `chat_images/{conversationId}/{messageId}/{uuid}.jpg`. Returns download URL. |

### Internal Helpers

| Method | Description |
|---|---|
| `createMemberships(conversationId:participantUids:)` | Batch-creates `conversationMembership` docs for all participants. |
| `verifyMembership(conversationId:uid:)` | Throws `notAMember` if user has no membership doc. |
| `fetchDisplayName(uid:)` | Looks up display name from `users/{uid}` document. |
| `decodeConversation(doc:data:)` | Converts Firestore data → `Conversation` model (handles `Timestamp` → `Date`). |
| `decodeMessage(doc:data:)` | Converts Firestore data → `Message` model (handles `Timestamp` → `Date`, `NSNull` → optional). |
| `resizeImage(_:maxDimension:)` | Scales `UIImage` using `UIGraphicsImageRenderer`. Returns original if already within bounds. |
| `deleteImageFromStorage(imageUrl:conversationId:messageId:)` | Deletes image from Firebase Storage using reconstructed path. Runs in detached `Task`. |

---

## Architecture Decisions

1. **Service layer handles Date ↔ Timestamp conversion** — Models use pure `Date` types (as established in Step 3). The service converts `Timestamp` → `Date` on read and `FieldValue.serverTimestamp()` / `Timestamp(date:)` on write. This keeps models framework-agnostic.

2. **`@MainActor` + `@Published` for reactive UI** — Follows the same pattern as `AuthManager` and `ContactManager`. Views observe `conversations` and `messages` arrays directly via SwiftUI `@ObservedObject` / `@StateObject`.

3. **Firestore `whereField` with `NSNull()` for null checks** — Firestore's Swift SDK doesn't accept Swift `nil` in `whereField` queries. `NSNull()` is used to query for fields that don't exist (e.g., finding unread messages where `readBy[uid]` is absent).

4. **Cursor-based pagination via `start(afterDocument:)`** — Uses actual Firestore document snapshots as cursors (not manual offset integers). The `fetchMessages` method fetches the cursor document from Firestore before paginating — this is required by the Firestore API.

5. **Batch operations for membership creation** — `createMemberships` uses `WriteBatch` to atomically create all membership docs in a single round-trip.

6. **Image deletion in detached Task** — Storage deletion is fire-and-forget (runs in `Task.detached`) so message deletion isn't blocked by network latency.

7. **Error types defined in same file** — `MessagingError` enum follows the `ContactError` pattern from `ContactManager.swift` — defined at file bottom with `LocalizedError` conformance.

---

## Build Verification
```
xcodebuild -scheme LetsDoIt -destination 'platform=iOS Simulator,name=iPhone 17' build
→ BUILD SUCCEEDED
```
