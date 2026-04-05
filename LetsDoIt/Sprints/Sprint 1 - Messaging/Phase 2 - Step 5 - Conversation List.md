# Phase 2, Step 5: Conversation List — Implementation Log

**Date:** 2026-04-05
**Status:** ✅ Complete — BUILD SUCCEEDED

---

## What Was Done

### New Files Created

| File | Purpose |
|------|---------|
| `Views/Messaging/ConversationsListView.swift` | Conversation list with unread badges, swipe actions (delete/mute), and empty state |
| `Views/Messaging/ChatView.swift` | Placeholder for Step 6 — accepts `conversationId` and `Conversation`, shows navigation title |

### Files Modified

| File | Change |
|------|--------|
| `Services/MessagingManager.swift` | Added `memberships` published property, `startListeningMemberships()`, `stopListeningMemberships()`, and `toggleMute(conversationId:)` method |
| `Views/MessagesTabView.swift` | Replaced placeholder VStack with `ConversationsListView()` |

---

## View Details

### `ConversationsListView`

```swift
@MainActor struct ConversationsListView: View
```

| State Property | Type | Purpose |
|---|---|---|
| `messagingManager` | `@StateObject MessagingManager` | Singleton observable for conversations + memberships |
| `showingDeleteAlert` | `@State Bool` | Controls delete confirmation alert |
| `conversationToDelete` | `@State String?` | Tracks which conversation is pending deletion |
| `deleteError` | `@State String?` | Error message from failed delete |
| `muteError` | `@State String?` | Error message from failed mute toggle |

| Computed Property | Type | Purpose |
|---|---|---|
| `showingErrorAlert` | `Bool` | True when either error is non-nil |
| `errorMessage` | `String?` | Returns whichever error is present |

| Lifecycle | Behavior |
|---|---|
| `.onAppear` | Starts both `startListeningConversations()` and `startListeningMemberships()` |
| `.onDisappear` | Stops both listeners, clears published arrays |

**Key features:**
- `List` with `ForEach` over `messagingManager.conversations`
- Each row uses `NavigationLink(value:)` + `.navigationDestination(for:)` for type-safe navigation
- Unread badge: `lastMessage.timestamp > membership.lastReadAt`
- Swipe actions (trailing): Mute (toggles icon/tint) + Delete (destructive, with confirmation alert)
- Empty state: centered icon + "No conversations yet" title + subtitle

### `ConversationRow`

```swift
struct ConversationRow: View
```

| Parameter | Type | Purpose |
|---|---|---|
| `conversation` | `Conversation` | The conversation to render |
| `isUnread` | `Bool` | Whether to show bold title + unread dot |
| `isMuted` | `Bool` | Whether to show speaker-slash icon |

**Layout:**
- HStack with avatar circle (accent color), title row, and last message snippet
- Avatar: `person.fill` for DM, `person.3.fill` for group
- Title: bold if unread, standard weight otherwise
- Timestamp: `Date(style: .time)` in trailing position
- Unread dot: 8pt accent-colored circle before last message text
- Last message: includes `senderName: ` prefix for non-self messages, image fallback text

### `ChatView` (Placeholder)

```swift
struct ChatView: View
```

| Parameter | Type | Purpose |
|---|---|---|
| `conversationId` | `String` | ID of the conversation |
| `conversation` | `Conversation?` | Optional conversation for title resolution |

Shows a placeholder icon and the conversation ID. Title resolves from `Conversation` type (group name, DM participant name, or "Event Chat"). Fully implemented in Step 6.

---

## Service Details

### `MessagingManager` Additions

| Property/Method | Type | Description |
|---|---|---|
| `memberships` | `@Published [String: ConversationMembership]` | Dictionary mapping `conversationId` → membership for O(1) lookup |
| `membershipListener` | `ListenerRegistration?` | Private Firestore listener on `users/{uid}/conversationMemberships` |
| `startListeningMemberships()` | `func` | Real-time listener on memberships collection |
| `stopListeningMemberships()` | `func` | Removes listener, clears dictionary |
| `toggleMute(conversationId:)` | `async throws func` | Flips `muted` field on membership doc; throws if membership not found |

---

## Architecture Decisions

1. **Memberships as `[String: ConversationMembership]` dictionary instead of array** — Unread badge computation needs O(1) lookup by conversation ID during list rendering. A dictionary avoids linear scans per row. The `MessagingManager.conversations` array is already ordered by `lastMessage.timestamp`, so the list iterates conversations and looks up membership data by key.

2. **Separate membership listener instead of joining with conversation listener** — Firestore doesn't support server-side joins. The membership listener runs independently on `users/{uid}/conversationMemberships`, which is the canonical location for per-user conversation state (mute, lastReadAt, joinedAt). This matches the data model established in Phase 1, Step 3.

3. **`NavigationLink(value:)` + `.navigationDestination(for:)` pattern** — Uses SwiftUI's modern programmatic navigation with `Conversation` as the navigation value (which already conforms to `Hashable` from the model). This is cleaner than binding-based `NavigationLink(destination:isActive:)` and supports deep linking patterns in the future.

4. **Swipe actions use `allowsFullSwipe: false`** — Prevents accidental destructive deletes. Both Mute and Delete require an explicit tap, with Delete requiring a confirmation alert.

5. **Error alerts use computed `showingErrorAlert` boolean** — SwiftUI's `.alert(isPresented:)` requires a `Binding<Bool>`. Using `.constant(showingErrorAlert)` with a computed property is a pragmatic approach that avoids complex alert state management. Both delete and mute errors funnel through the same alert.

6. **Empty state matches existing `MessagesTabView` placeholder style** — Same icon size (60pt), same font hierarchy (`title2.bold()` for title, `body` for subtitle), same secondary color for icon and subtitle text. The old placeholder is fully replaced by `ConversationsListView`'s internal empty state.

---

## Build Verification
```
xcodebuild -scheme LetsDoIt -destination 'platform=iOS Simulator,name=iPhone 17' build
→ BUILD SUCCEEDED
```
