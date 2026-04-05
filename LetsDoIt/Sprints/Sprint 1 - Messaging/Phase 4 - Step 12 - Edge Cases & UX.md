# Phase 4, Step 12: Edge Cases & UX — Implementation Log

**Date:** 2026-04-05
**Status:** ✅ Complete — BUILD SUCCEEDED

---

## What Was Done

### New Files Created

| File | Purpose |
|------|---------|
| `Services/NetworkMonitor.swift` | `NWPathMonitor` wrapper as `@Observable` singleton — publishes `isConnected` for offline/online detection |

### Files Modified

| File | Change |
|------|--------|
| `Services/MessagingManager.swift` | Added `@Published var isUploadingImage: Bool`; `uploadImage` sets `true`/`false` with `defer` |
| `Views/Messaging/ConversationsListView.swift` | Added `NetworkMonitor` environment, `isLoadingConversations` state, offline banner, loading/empty state distinction |
| `Views/Messaging/ChatView.swift` | Added `NetworkMonitor` environment, offline banner, `isSendingMessage` state, send button `ProgressView`, `isUploading` computed property, send error alert with Retry, `notAMember` handling (dismiss + alert), `retrySend()` method, `PendingLocalMessage` struct for offline queue, `retryPendingMessages()` auto-retry on reconnect, `syncPendingMessages()` cleanup, "Send as Text Only" fallback option |
| `Views/Messaging/MessageBubbleView.swift` | Added `isPending: Bool` parameter (default `false`), dimmed opacity (0.5) + clock icon + "Pending" label for pending messages, added pending preview to `#Preview` |
| `LetsDoItApp.swift` | Injected `NetworkMonitor.shared` into environment |

---

## New Service Details

### `NetworkMonitor`

```swift
@Observable final class NetworkMonitor
```

| Property | Type | Notes |
|---|---|---|
| `shared` | `static NetworkMonitor` | Singleton instance |
| `isConnected` | `@MainActor var Bool` | Published; `true` by default, updates on network path changes |

| Method | Description |
|---|---|
| `init()` | Private; creates `NWPathMonitor` and starts monitoring on a background queue |
| `startMonitoring()` (private) | Configures `pathUpdateHandler` to dispatch `isConnected` updates to main queue |

---

## Modified File Details

### `MessagingManager.swift`

| Property | Type | Notes |
|---|---|---|
| `isUploadingImage` | `@Published var Bool` | `true` while `uploadImage` is in flight; auto-reset via `defer` |

| Method | Change |
|---|---|
| `uploadImage(_:conversationId:messageId:)` | Wraps body with `isUploadingImage = true` / `defer { isUploadingImage = false }` |

### `ConversationsListView.swift`

| Property | Type | Notes |
|---|---|---|
| `networkMonitor` | `@Environment(NetworkMonitor.self)` | Consumed from app root |
| `isLoadingConversations` | `@State var Bool` | Starts `true`; set `false` in `onAppear` after starting listener |

| View | Description |
|---|---|
| `offlineBanner` | Orange banner with `wifi.slash` icon and "You're offline. Messages will sync when you reconnect." |
| `loadingState` | `ProgressView("Loading conversations…")` — shown when `isLoadingConversations && conversations.isEmpty` |
| `emptyState` | Shown only when `!isLoadingConversations && conversations.isEmpty` — differentiates "loaded but empty" from "still loading" |

| Behavior | Trigger |
|---|---|
| Offline banner appears | `networkMonitor.isConnected` becomes `false` |
| Offline banner disappears | `networkMonitor.isConnected` becomes `true` (auto, no manual dismiss) |
| Loading state shown | On `onAppear`, before first Firestore snapshot |
| Empty state shown | After first snapshot arrives with zero conversations |

### `ChatView.swift`

| Property | Type | Notes |
|---|---|---|
| `networkMonitor` | `@Environment(NetworkMonitor.self)` | Consumed from app root |
| `dismiss` | `@Environment(\.dismiss)` | Programmatic dismissal on membership error |
| `isSendingMessage` | `@State var Bool` | `true` while `sendMessage` Task is in flight |
| `sendError` | `@State var String?` | Triggers "Send Failed" alert with Retry option |
| `failedSendText` | `@State var String?` | Saved text for retry |
| `failedSendImages` | `@State var [UIImage]?` | Saved images for retry |
| `membershipError` | `@State var String?` | Triggers "Conversation Unavailable" alert → dismiss |

| Computed Property | Description |
|---|---|
| `isUploading` | `messagingManager.isUploadingImage \|\| isSendingMessage` — gates all input controls |

| Method | Description |
|---|---|
| `sendMessage()` | Sets `isSendingMessage = true`; catches `MessagingError.notAMember` → sets `membershipError`; catches other errors → if offline, queues to `pendingLocalMessages`; otherwise saves text/images for retry, sets `sendError` |
| `retrySend()` | Re-sends with saved `failedSendText` / `failedSendImages`; same error handling |
| `sendAsTextOnly()` | Sends only the text portion of a failed message (without images); if it also fails, falls back to the general send error flow |
| `retryPendingMessages()` | Re-sends all locally queued messages after reconnecting; on failure, puts the message back and stops |
| `syncPendingMessages()` | Removes pending messages whose text has appeared in `messagingManager.messages` (synced from server via real-time listener) |

| UI Change | Description |
|---|---|
| Offline banner | Same orange banner as `ConversationsListView`, shown at top when `!isConnected` |
| Send button | Shows `ProgressView` while `isSendingMessage` is true |
| Text field | Disabled while `isUploading` is true |
| Image picker button | Disabled while `isUploading` is true |
| Upload progress indicator | Now observes `messagingManager.isUploadingImage` instead of local state |
| "Send Failed" alert | Shows `sendError` message; offers "Retry" and "Cancel" buttons |
| "Conversation Unavailable" alert | Shows `membershipError` message; "OK" dismisses the view |

### `MessageBubbleView.swift`

| Property | Type | Notes |
|---|---|---|
| `isPending` | `let Bool` | Default `false` via custom initializer; when `true`, bubble is dimmed (0.5 opacity) and shows clock icon + "Pending" |

| Change | Description |
|---|---|
| Custom `init` | Accepts `isPending: Bool = false` so existing call sites don't need updating |
| `.opacity(isPending ? 0.5 : 1.0)` | Visually distinguishes unsynced messages |
| Timestamp section | Replaced with `HStack` that shows `clock.fill` + "Pending" when `isPending`, otherwise shows the timestamp |
| `#Preview` | Added a pending message example |

---

## Architecture Decisions

1. **`@Observable` for `NetworkMonitor` (consistent with project pattern)** — Uses the same `@Observable` pattern as `DeepLinkRouter` (see Step 11 decision #1). The project targets iOS 17+, so the modern Observation framework is preferred over `ObservableObject`.

2. **`NetworkMonitor` starts monitoring on init** — The singleton's `private init()` calls `startMonitoring()` immediately, so `isConnected` is accurate from app launch. No manual start/stop required.

3. **`isUploading` computed property in `ChatView`** — Combines `messagingManager.isUploadingImage` (image upload in progress) and `isSendingMessage` (text send in progress) into a single gate. This ensures the text field, image picker, and send button are all disabled during either operation.

4. **Send error retry saves text + images** — When `sendMessage` fails, the text and images are captured in `failedSendText` and `failedSendImages`. The "Retry" button in the alert re-sends with the exact same payload. This prevents data loss on transient network failures.

5. **`notAMember` caught separately from general errors** — `MessagingError.notAMember` triggers a different UX flow: show alert + auto-dismiss the view (user was removed from conversation). Other errors trigger a retry flow.

6. **`isLoadingConversations` reset in `onAppear`** — The loading state is set to `false` immediately after calling `startListeningConversations()`. Since Firestore's `addSnapshotListener` fires a callback immediately (with cached data if available), this accurately reflects "first data received." If the user has no cached data, the listener will fire with an empty array, transitioning to the true empty state.

7. **Offline banner is non-dismissible** — Unlike some apps that offer an "X" to hide the offline banner, this banner auto-hides when the connection is restored. This prevents the UX issue of a dismissed banner leaving the user unaware they're still offline.

8. **`defer { isUploadingImage = false }` in `uploadImage`** — Uses `defer` to guarantee the flag is reset even if the method throws. This prevents the send button from being permanently disabled after a failed upload.

---

## Spec vs. Actual — Deviations Summary

| Spec Says | Actual | Reason |
|---|---|---|
| "Create `Utilities/NetworkMonitor.swift`" | Created `Services/NetworkMonitor.swift` | The project has no `Utilities/` folder; all singleton services live in `Services/` (`DeepLinkRouter`, `TokenManager`, `AuthManager`, etc.) |
| "ObservableObject with @Published" | `@Observable` class | Consistent with Step 11 decision — project uses modern Observation framework for iOS 17+ |
| "Banner should be dismissible (small 'X' button) or auto-dismiss on reconnect" | Auto-dismiss only (no manual X) | Simpler UX; auto-dismiss on reconnect covers the happy path without requiring user action |
| "Track isUploading with @State in ChatView" | Uses `MessagingManager.isUploadingImage` + local `isSendingMessage` | Split into two concerns: image upload (manager-level) and message send (view-level), combined via `isUploading` computed property |
| "Send button shows ProgressView while sendMessage is in progress" | ProgressView replaces send icon entirely | Cleaner than showing both; the spinner in the button position clearly indicates "sending" |
| "NewConversationView: show loading spinner on 'Create' button" | Already present in existing code | `NewConversationView.swift` already had `isCreating`, a `ProgressView` in the button label, and `.disabled(!canCreate)` which includes `!isCreating`. No changes needed. |
| "Conversation creation failure: show alert in NewConversationView" | Already present in existing code | `NewConversationView.swift` already had `.alert("Error", isPresented: .constant(createError != nil))`. No changes needed. |

---

## Build Verification
```
xcodebuild -scheme LetsDoIt -destination 'platform=iOS Simulator,name=iPhone 17' build
→ BUILD SUCCEEDED (verified twice — initial + after adding 4 missing sub-tasks)
```
