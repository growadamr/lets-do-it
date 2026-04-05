# Phase 3, Step 9: Read Receipts & Unread Tracking — Implementation Log

**Date:** 2026-04-05
**Status:** ✅ Complete — BUILD SUCCEEDED

---

## What Was Done

### New Files Created

| File | Purpose |
|------|---------|
| `Views/Messaging/ReadReceiptsView.swift` | "Seen by" indicator view showing names of users who read a message, with truncation for long lists |

### Files Modified

| File | Change |
|------|--------|
| `Views/Messaging/ChatView.swift` | Added `lastReadSelfMessageId` computed property; wrapped `MessageBubbleView` in a `VStack` to conditionally render `ReadReceiptsView` below the most recent read self-message |

### Validated (No Changes Needed)

| Component | File | Finding |
|-----------|------|---------|
| `markMessagesRead` flow | `Services/MessagingManager.swift` | Correctly updates `readBy[uid]` on unread messages via batch write + updates `lastReadAt` on membership doc with `setData(merge: true)` |
| Unread badge logic | `Views/Messaging/ConversationsListView.swift` | `isUnread()` correctly compares `lastMessage.timestamp` vs `membership.lastReadAt`; handles nil cases properly |

---

## View Details

### `ReadReceiptsView`

```swift
struct ReadReceiptsView: View
```

| Property | Type | Notes |
|---|---|---|
| `readBy` | `[String: Date]` | UID → read timestamp map from `Message.readBy` |
| `participantNames` | `[String: String]` | UID → display name cache from `Conversation.participantNames` |
| `currentUid` | `String` | Used to filter out self from the reader list |

**Computed properties:**
- `readerNames` — Filters `readBy` to exclude `currentUid`, sorts by read time ascending, maps UIDs to display names
- `seenByText` — Formats as "Seen by Alice" / "Seen by Alice, Bob" / "Seen by Alice + 2 others" (truncates at 2)

**Layout:**
- `.caption2` font, `.secondary` foreground color
- Right-aligned with `.trailing` padding to avoid overlapping with scroll edge
- Returns `EmptyView` when no readers (besides self) — no visual footprint

---

## Modified File Details

### `ChatView.lastReadSelfMessageId`

New computed property that finds the most recent message sent by the current user that has been read by at least one other person:

```swift
private var lastReadSelfMessageId: String? {
    let currentUid = AuthManager.shared.userId ?? ""
    let selfMessages = messagingManager.messages.filter { $0.senderUid == currentUid }
    // Iterate reversed (newest first), return first with other readers
}
```

### `ChatView.messageListContent`

Wrapped each `MessageBubbleView` in a `VStack(alignment: .trailing)` and conditionally renders `ReadReceiptsView` when:
1. The message is from the current user (`isFromCurrentUser(message)`)
2. The message ID matches `lastReadSelfMessageId`
3. A `conversation` is available (for `participantNames`)

```swift
ForEach(messagingManager.messages) { message in
    VStack(alignment: .trailing, spacing: 0) {
        MessageBubbleView(...)
            .id(message.id)

        if isFromCurrentUser(message),
           message.id == lastReadSelfMessageId,
           let conversation {
            ReadReceiptsView(
                readBy: message.readBy,
                participantNames: conversation.participantNames,
                currentUid: AuthManager.shared.userId ?? ""
            )
        }
    }
}
```

---

## Validation Results

### `markMessagesRead` Flow (MessagingManager)

**Query:** `whereField("readBy.\(uid)", isEqualTo: NSNull())`
- Finds messages where the current user's UID key is absent or null in the `readBy` map
- Correctly identifies unread messages

**Batch update:** `readBy.{uid}: now` (Timestamp)
- All unread messages in the conversation are updated in a single batch commit

**Membership update:** `setData(["lastReadAt": now], merge: true)`
- Uses `merge: true` to avoid overwriting `muted` or `joinedAt` fields
- This is the key field used by `ConversationsListView.isUnread()` for badge computation

**End-to-end test scenarios (expected behavior):**
1. Open a conversation → `markMessagesRead` fires → `lastReadAt` updated → unread badge clears in list ✓
2. Switch away, receive new messages → `lastMessage.timestamp` > `lastReadAt` → badge reappears ✓
3. Open conversation again → `markMessagesRead` fires again → badge clears ✓

### Unread Badge Logic (ConversationsListView)

**`isUnread(conversation)` logic:**
- No `lastMessage` → `false` (no messages to be unread about) ✓
- No membership found → `true` (never read = unread) ✓
- `lastMessage.timestamp > lastReadAt` → `true` (new message since last visit) ✓
- Otherwise → `false` (up to date) ✓

**Membership listener:** `startListeningMemberships()` called in `.onAppear`, populates `messagingManager.memberships` dictionary → drives both `isUnread()` and `isMuted()` ✓

---

## Architecture Decisions

1. **Only show on most recent self-sent message** — Matching iMessage/WhatsApp behavior, showing "Seen by" on every bubble creates visual noise. The single indicator on the latest read message is sufficient and familiar to users.

2. **No "Delivered" state** — The spec calls for showing nothing if no one has read the message yet. A "Delivered" state (single dot or label) was considered but deferred — it adds complexity for minimal user value when the read receipt itself is the primary signal.

3. **Truncation at 2 readers** — "Alice + 2 others" format keeps the label short enough to fit within bubble width. The threshold of 2 balances informativeness with compactness.

4. **`AnyView` wrapping for conditional empty state** — `ReadReceiptsView.body` returns `AnyView(EmptyView())` when there are no readers. This is necessary because SwiftUI `View.body` must have a single consistent return type. The alternative (`if` in the parent) was also viable but keeping the empty logic inside the view makes the call site cleaner.

5. **`VStack(alignment: .trailing)` wrapper in ChatView** — Instead of modifying `MessageBubbleView` to include the read receipt (which would couple the bubble to read receipt logic), the indicator is rendered as a sibling view in the parent's `ForEach`. This keeps `MessageBubbleView` focused on rendering a single message and `ChatView` responsible for thread-level UX patterns.

6. **`markMessagesRead` uses `NSNull()` query** — The existing query `whereField("readBy.\(uid)", isEqualTo: NSNull())` correctly finds messages where the current user hasn't been marked as read. In Firestore, map keys that don't exist evaluate to null for this query type. No changes were needed to this flow.

---

## Build Verification
```
xcodebuild -scheme LetsDoIt -destination 'platform=iOS Simulator,name=iPhone 17' build
→ BUILD SUCCEEDED
```
