# Phase 4: Integration & Polish — Implementation Breakdown

**Parent:** Sprint 1 — Messaging
**Estimated duration:** 1 week
**Complexity:** MEDIUM
**Prerequisites:** Phase 1 (Foundation), Phase 2 (Core Messaging UI), Phase 3 (Rich Messages + Cloud Functions) complete

---

## Deliverables Checklist

- [x] **Step 11: Deep Linking & Notifications**
  - [x] `DeepLinkRouter` utility — generic, enum-based router supporting `.conversation(id)`, extensible for Sprint 3 `.event(id)`
  - [x] `AppDelegate` notification tap handler — parse deep-link payload, publish route, navigate to `ChatView`
  - [x] FCM token sync: request notification permission, register for remote notifications, write `fcmToken` to `users/{uid}`
  - [x] `TokenManager` service — writes/refreshes FCM token to user doc on login and token refresh
  - [x] "Message" button on `ContactsListView` — opens/creates DM with selected contact
- [x] **Step 12: Edge Cases & UX**
  - [x] Offline state banners in `ConversationsListView` and `ChatView`
  - [x] Loading spinners during message send, image upload, conversation creation
  - [x] Error alerts for failed sends, failed uploads, membership violations
  - [x] Graceful handling of deleted conversations disappearing mid-view
  - [x] Graceful handling of deleted messages disappearing mid-thread
  - [x] Send button disabled state while upload in progress
  - [x] "Retry send" indicator for failed messages (visual distinction)
- [ ] **Step 13: Integration Testing**
  - [ ] Two-account simulator test (anonymous auth)
  - [ ] Firestore document creation/verification checklist
  - [ ] Cloud Functions emulator test (messaging triggers)
  - [ ] Real-time message sync verification across both accounts
  - [ ] End-to-end checks: unread badges, pagination, image uploads, link previews

---

## Dependencies (Existing Code)

| Dependency | File | Used By |
|---|---|---|
| `MessagingManager` | `Services/MessagingManager.swift` | Steps 11, 12 |
| `AuthManager` | `Services/AuthManager.swift` | Step 11 (current user ID, login hook) |
| `Conversation` model | `Models/Conversation.swift` | Step 11 (deep link routing) |
| `ContactManager.Contact` | `Services/ContactManager.swift` | Step 11 (message button on contacts) |
| `MessagesTabView` | `Views/MessagesTabView.swift` | Step 11 (deep link destination navigation) |
| `ConversationsListView` | `Views/Messaging/ConversationsListView.swift` | Step 12 (offline/loading states) |
| `ChatView` | `Views/Messaging/ChatView.swift` | Step 12 (offline/loading/error states) |
| `AppDelegate` | `AppDelegate.swift` | Step 11 (notification handler) |
| `MessagingManager.conversations` | `Services/MessagingManager.swift` | Step 12 (deleted conversation handling) |
| `MessagingManager.messages` | `Services/MessagingManager.swift` | Step 12 (deleted message handling) |

---

## Step 11: Deep Linking & Notifications

### 11.1 — DeepLinkRouter utility
**Dependencies:** SwiftUI `ObservableObject`, `NavigationPath`
**Files to create:**
- `Services/DeepLinkRouter.swift`

**Sub-tasks:**
- [ ] Create `DeepLinkRoute` enum with associated values:
  ```swift
  enum DeepLinkRoute: Codable, Hashable {
      case conversation(String)   // conversationId
      // Sprint 3: case event(String)
  }
  ```
- [ ] Create `DeepLinkRouter` as an `ObservableObject` with `@Published var route: DeepLinkRoute?`
- [ ] Make it a singleton: `static let shared = DeepLinkRouter()`
- [ ] Add `func handle(_ route: DeepLinkRoute)` — publishes the route and optionally logs
- [ ] Add `func clear()` — resets `route` to `nil` after navigation is consumed
- [ ] Ensure the enum is `Codable` so it can be serialized from FCM `data` payload in notifications

### 11.2 — AppDelegate notification handler
**Dependencies:** `DeepLinkRouter`, `UNUserNotificationCenter`
**Files to modify:**
- `AppDelegate.swift`

**Sub-tasks:**
- [ ] Implement `UNUserNotificationCenterDelegate` protocol methods on `AppDelegate`:
  - `userNotificationCenter(_:didReceive:withCompletionHandler:)` — called when user taps notification
  - `userNotificationCenter(_:willPresent:withCompletionHandler:)` — called when app is foreground and notification arrives (optional — show banner or silent)
- [ ] In `didReceive`, parse `userInfo` for `aps` → `data` → `conversationId`
- [ ] If `conversationId` found, call `DeepLinkRouter.shared.handle(.conversation(conversationId))`
- [ ] Call `completionHandler()` at the end
- [ ] Register `UNUserNotificationCenter.current().delegate = self` in `application(_:didFinishLaunchingWithOptions:)`
- [ ] Handle malformed payloads gracefully (log warning, call completion handler, no crash)

### 11.3 — Deep link consumption in RootView / MessagesTabView
**Dependencies:** `DeepLinkRouter`, `NavigationStack` in `MessagesTabView` or `RootView`
**Files to modify:**
- `LetsDoItApp.swift` or `RootView.swift` (wherever `AppDelegate` is wired)
- `Views/MessagesTabView.swift`
- `Views/Messaging/ConversationsListView.swift`

**Sub-tasks:**
- [ ] In `RootView` or `LetsDoItApp`, create `@StateObject var router = DeepLinkRouter.shared` and inject into the view hierarchy via `.environmentObject()`
- [ ] In `MessagesTabView`, consume `@EnvironmentObject var router: DeepLinkRouter`
- [ ] When `router.route` becomes `.conversation(id)`, programmatically navigate to `ChatView(conversationId:)`:
  - Use `NavigationStack(path:)` with a binding to a path array
  - Append `conversationId` to path when route is received
  - Call `router.clear()` after navigation to prevent re-trigger on re-render
- [ ] If user is on a different tab, auto-switch to Messages tab before navigating (set active tab index)
- [ ] Ensure `ConversationsListView` can handle being navigated into with a specific `conversationId` pre-selected

### 11.4 — FCM Token Sync (TokenManager)
**Dependencies:** `FirebaseMessaging`, `FirebaseFirestore`, `AuthManager`
**Files to create:**
- `Services/TokenManager.swift`

**Sub-tasks:**
- [ ] Create `TokenManager` as a `struct` with static methods:
  ```swift
  static func requestPermission() async -> Bool
  static func registerForRemoteNotifications()
  static func syncTokenToFirestore(uid: String) async throws
  ```
- [ ] `requestPermission()`: call `UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])` and return result
- [ ] `registerForRemoteNotifications()`: call `UIApplication.shared.registerForRemoteNotifications()`
- [ ] `syncTokenToFirestore`: get FCM token via `Messaging.messaging().token()`, write to `users/{uid}/fcmToken` via Firestore
- [ ] Handle token refresh: `Messaging.messaging().delegate` → `messaging(_:didReceiveRegistrationToken:)` → re-sync token to Firestore
- [ ] **Integration point**: Call `TokenManager.requestPermission()` and `TokenManager.registerForRemoteNotifications()` after successful login (in `AuthManager` or app init)
- [ ] Handle unauthenticated state gracefully — queue token sync until user is logged in
- [ ] If token write fails, log error but don't crash (user can still use the app, just won't get pushes)

### 11.5 — Notification permission flow in app lifecycle
**Dependencies:** `TokenManager`, `AuthManager`
**Files to modify:**
- `LetsDoItApp.swift` or `AppDelegate.swift`
- `Services/AuthManager.swift` (or wherever login flow is handled)

**Sub-tasks:**
- [ ] After user signs in successfully, trigger `TokenManager.requestPermission()` — if granted, call `registerForRemoteNotifications()` and `syncTokenToFirestore()`
- [ ] If permission was previously denied, skip (don't re-prompt — user must enable in Settings)
- [ ] On app launch (already logged in), call `syncTokenToFirestore()` to refresh token if it changed
- [ ] Show a brief inline explanation before requesting permission (optional: "Get notified when someone messages you")
- [ ] No blocking UI — if user denies, messaging still works, they just won't get push notifications

### 11.6 — "Message" button on ContactsListView
**Dependencies:** `MessagingManager.createDM`, `ContactManager.Contact`
**Files to modify:**
- `Views/ContactsListView.swift`

**Sub-tasks:**
- [ ] Add a "Message" button (bubble icon or "💬" text) to each contact row in `ContactsListView`
- [ ] Tap action: call `MessagingManager.createDM(with: contact.uid)` — if DM already exists, it returns the existing conversation
- [ ] On success: navigate to `ChatView(conversationId:)` for the returned conversation
- [ ] On error (e.g., network failure): show alert with error message
- [ ] Show loading indicator while `createDM` is in progress (button becomes disabled, shows spinner)
- [ ] If contact has no `uid` (edge case), disable the button
- [ ] Style: small secondary button, trailing edge of the contact row, matching the existing row design

---

## Step 12: Edge Cases & UX

### 12.1 — Offline state banners
**Dependencies:** `NetworkMonitor` (if exists) or `NWPathMonitor` from `Network` framework
**Files to create:**
- `Utilities/NetworkMonitor.swift` (if no connectivity monitor exists)

**Files to modify:**
- `Views/Messaging/ConversationsListView.swift`
- `Views/Messaging/ChatView.swift`

**Sub-tasks:**
- [ ] Create `NetworkMonitor` as an `ObservableObject` with `@Published var isConnected: Bool`, using `NWPathMonitor`
- [ ] Start monitor on app init, expose as singleton: `static let shared = NetworkMonitor()`
- [ ] In `ConversationsListView`, when `isConnected` is false, show a red/orange banner at the top: "⚠️ You're offline. Messages will sync when you reconnect."
- [ ] In `ChatView`, show similar banner when offline
- [ ] Banner should be dismissible (small "X" button) or auto-dismiss on reconnect
- [ ] Messages sent while offline should show a "pending" indicator (grayed out, clock icon) — this requires tracking locally which messages failed to send

### 12.2 — Loading states for send/create operations
**Dependencies:** `MessagingManager`, existing SwiftUI `ProgressView`
**Files to modify:**
- `Views/Messaging/ChatView.swift`
- `Views/Messaging/NewConversationView.swift`
- `Views/Messaging/ConversationsListView.swift`

**Sub-tasks:**
- [ ] **ChatView send**: disable send button while `sendMessage` is in progress; show a small `ProgressView` in place of the send icon
- [ ] **Image upload**: show upload progress (use `Progress` from `uploadImage` or a simple spinner overlay on the image preview thumbnails)
- [ ] **NewConversationView**: show loading spinner on "Create" button while `createDM`/`createGroup` is in progress; disable button
- [ ] **ConversationsListView**: if `conversations` is empty and `startListeningConversations()` was just called, show a skeleton/shimmer placeholder or "Loading conversations…" text (differentiate from true empty state)
- [ ] Distinguish between "initial load" (show loading) and "loaded but empty" (show empty state)

### 12.3 — Error alerts for failed operations
**Dependencies:** `MessagingError` enum, SwiftUI `.alert`
**Files to modify:**
- `Views/Messaging/ChatView.swift`
- `Views/Messaging/NewConversationView.swift`
- `Views/Messaging/ConversationsListView.swift`

**Sub-tasks:**
- [ ] **ChatView send failure**: catch errors from `sendMessage`, show `.alert` with "Failed to send message" + error description; optionally offer a "Retry" button that re-sends
- [ ] **Image upload failure**: show alert with "Failed to upload image" + "Send as text only" option (sends message without the image)
- [ ] **Membership error**: if `verifyMembership` throws `notAMember` mid-conversation (user was removed), show alert and navigate back to conversation list
- [ ] **Conversation creation failure**: show alert in `NewConversationView` with the specific error
- [ ] All error messages should be user-friendly (use `MessagingError.errorDescription`) — not raw Firestore error strings

### 12.4 — Graceful handling of deleted content
**Dependencies:** Firestore real-time listeners (auto-remove deleted docs)
**Files to modify:**
- `Views/Messaging/ConversationsListView.swift`
- `Views/Messaging/ChatView.swift`

**Sub-tasks:**
- [ ] **Conversation deleted while viewing list**: Firestore listener auto-removes from `MessagingManager.conversations` — if user was mid-navigation to it, `ChatView` will throw on `verifyMembership` — catch this and show "Conversation no longer exists" alert, then dismiss
- [ ] **Message deleted while viewing thread**: Firestore listener auto-removes from `messages` array — no crash expected since `messages` is `@Published` and SwiftUI re-renders
- [ ] **Edge case: message bubble referenced by ID in "Seen by" indicator** — if message is deleted, ensure `ReadReceiptsView` doesn't crash on nil lookup
- [ ] **Edge case: participant name missing** — if a participant's user doc was deleted, `participantNames` cache should still have their name; if not, show "Unknown user"

### 12.5 — Send button disabled state during upload
**Dependencies:** `ChatView` send logic
**Files to modify:**
- `Views/Messaging/ChatView.swift`

**Sub-tasks:**
- [ ] Track upload state with `@State private var isUploading: Bool = false`
- [ ] While `isUploading` is true, disable the send button and text input
- [ ] Show a `ProgressView` with label "Uploading…" above the input bar
- [ ] On upload completion (success or failure), reset `isUploading` to false

---

## Step 13: Integration Testing

### 13.1 — Two-account simulator test plan
**Dependencies:** Firebase Emulator Suite, two simulator instances
**Files to modify:**
- None (manual testing procedure)

**Test setup:**
- [ ] Run two iOS simulators simultaneously (e.g., iPhone 17 + iPhone 17 Pro)
- [ ] Sign in with anonymous auth on both (different UIDs)
- [ ] Set each user's display name (via `SetNameView`) so names appear in conversations

**Test cases:**

| # | Test | Expected Result |
|---|------|----------------|
| 1 | User A creates DM with User B | Conversation appears on both users' lists |
| 2 | User A sends text message to User B | Message appears on both screens in real-time |
| 3 | User B replies | Reply appears on User A's screen in real-time |
| 4 | User A sends image | Image uploads, appears on both screens, stored in Firestore Storage |
| 5 | User A sends message with URL | Link preview card renders on both screens |
| 6 | User A opens conversation (badge clears), User B sends new message | Unread badge appears on User A's conversation list |
| 7 | User A taps conversation (opens chat) | Badge clears, messages marked as read |
| 8 | User A creates group with User B + User C (if 3rd account available) | Group appears on all participants' lists |
| 9 | User A swipes to mute a conversation | Mute icon updates, no notification (manual — verify FCM push suppressed) |
| 10 | User A deletes a conversation | Conversation removed from User A's list; User B's list unaffected |
| 11 | User A scrolls to top of long conversation | Older messages load via pagination (50 per page) |
| 12 | User A goes offline (Airplane Mode), sends message | Message shows "pending" state; syncs when reconnected |
| 13 | Deep link: User A taps notification (simulated) | App opens to the correct conversation |
| 14 | User A taps "Message" on User B in Contacts | DM opens (or creates new one if first time) |

### 13.2 — Firestore document verification
**Dependencies:** Firebase Console or Emulator UI
**Files to modify:**
- None (manual testing procedure)

**Verification checklist:**

| Collection | Field | Verify |
|---|---|---|
| `conversations/{id}` | `type` | `"dm"`, `"group"`, or `"event"` |
| `conversations/{id}` | `participants` | Array contains correct UIDs |
| `conversations/{id}` | `participantNames` | Map has UID → name entries for all participants |
| `conversations/{id}` | `lastMessage.text` | Matches most recent message (denormalized) |
| `conversations/{id}` | `lastMessage.timestamp` | Matches most recent message `createdAt` |
| `conversations/{id}/messages/{id}` | `senderUid` | Matches sender |
| `conversations/{id}/messages/{id}` | `readBy` | Map populated with UID → Timestamp after read |
| `users/{uid}/conversationMemberships/{id}` | `lastReadAt` | Updated when user opens conversation |
| `users/{uid}/conversationMemberships/{id}` | `muted` | Toggles correctly |
| `users/{uid}` | `fcmToken` | Present after login (Step 11.4) |

### 13.3 — Cloud Functions emulator test
**Dependencies:** Firebase Emulator Suite (`firebase emulators:start`)
**Files to modify:**
- None (manual testing procedure)

**Test procedure:**
- [ ] Start emulator: `firebase emulators:start` from project root
- [ ] Create a test conversation via emulator UI → verify `onConversationCreated` creates membership docs for all participants
- [ ] Create a test message via emulator UI → verify `onMessageCreated` denormalizes `lastMessage` on the conversation doc
- [ ] Verify FCM push attempt in function logs (emulator logs the send attempt even without real tokens)
- [ ] Test idempotency: re-create the same conversation doc → verify no duplicate memberships, no errors

### 13.4 — Document test results
**Dependencies:** None
**Files to create:**
- `Sprints/Sprint 1 - Messaging/Phase 4 - Step 13 - Integration Testing.md`

**Sub-tasks:**
- [ ] Create an implementation log matching Phase 1/2/3 log format
- [ ] Record results for each test case (pass/fail + notes)
- [ ] Include screenshots from Firebase Emulator UI showing correct document structure (optional)
- [ ] Note any bugs found during testing and whether they were fixed

---

## File Summary

### New Files (3)
| File | Step | Purpose |
|------|------|---------|
| `Services/DeepLinkRouter.swift` | 11 | Generic deep link router with `DeepLinkRoute` enum, extensible for Sprint 3 |
| `Services/TokenManager.swift` | 11 | FCM token request, registration, and Firestore sync |
| `Utilities/NetworkMonitor.swift` | 12 | `NWPathMonitor` wrapper for offline/online state |

### Modified Files (6)
| File | Step | Change |
|------|------|--------|
| `AppDelegate.swift` | 11 | Add `UNUserNotificationCenterDelegate` implementation for notification tap handling |
| `LetsDoItApp.swift` or `RootView.swift` | 11 | Inject `DeepLinkRouter` as environment object |
| `Views/MessagesTabView.swift` | 11 | Consume `DeepLinkRouter` to navigate to specific conversation on notification tap |
| `Views/ContactsListView.swift` | 11 | Add "Message" button per contact row |
| `Views/Messaging/ChatView.swift` | 12 | Add offline banner, loading states, error alerts, upload progress |
| `Views/Messaging/ConversationsListView.swift` | 12 | Add offline banner, loading/empty state distinction |

---

## Implementation Order

Recommended: **11 → 12 → 13**

Step 11 (Deep Linking & Notifications) is the most critical remaining infrastructure — without it, push notifications won't reach the app and tapped notifications won't navigate. Step 12 (Edge Cases & UX) polishes the experience and handles failure modes. Step 13 (Integration Testing) validates everything end-to-end and should be done last, after all code changes are in place.

---

## Workflow Format — ALL Implementation Sessions Must Follow This

Every implementation task must follow this exact format:

1. **Plan** — Read the step's requirements and context files. Present a concrete implementation plan (specific files to create/modify, API design, key decisions) before writing any code.
2. **Present & confirm** — Wait for explicit user approval before implementing.
3. **Implement** — Create/modify files. Follow existing code conventions from the project.
4. **Verify** — Run `xcodebuild -scheme LetsDoIt -destination 'platform=iOS Simulator,name=iPhone 17' build` and confirm BUILD SUCCEEDED. Fix any errors.
5. **Document** — Create a "Phase 4 - Step X - [Name].md" implementation log in `Sprints/Sprint 1 - Messaging/` matching the format of the Phase 1 logs (`Phase 1 - Step 3 - Data Models.md` and `Phase 1 - Step 4 - MessagingManager.md`). Update this breakdown file to mark the step complete.
6. **Commit handoff** — End by asking the user to commit locally, and provide the list of changed files. Then give the user a ready-to-paste prompt for a fresh session to handle the next step. The prompt must include:
   - The project path (/Users/adamgrow/hermGameTest/LetsDoIt)
   - Which context files to re-read at the start of the next session
   - The specific next step to work on
   - A reminder of this workflow format (Plan -> Present & confirm -> Implement -> Verify -> Document -> Commit handoff)

IMPORTANT: The commit handoff prompt for the next step must be given as plain text only. Do NOT use markdown formatting (no code fences, no bold, no backticks, no lists) in the prompt block. It must be raw plain text that the user can copy and paste directly into a new chat.

### Implementation Log Format (reference)

Each implementation log must match the structure of the Phase 1 logs. See these files for the exact format:
- `Sprints/Sprint 1 - Messaging/Phase 1 - Step 3 - Data Models.md`
- `Sprints/Sprint 1 - Messaging/Phase 1 - Step 4 - MessagingManager.md`

Required sections in each log:
- Title, date, build status badge (✅ Complete — BUILD SUCCEEDED)
- "What Was Done" — tables of new/modified files
- Detailed section per file/service with property/method tables
- "Architecture Decisions" — numbered list of design rationale
- "Build Verification" — the exact xcodebuild command and result
