# Phase 4, Step 11: Deep Linking & Notifications — Implementation Log

**Date:** 2026-04-05
**Status:** ✅ Complete — BUILD SUCCEEDED

---

## What Was Done

### New Files Created

| File | Purpose |
|------|---------|
| `Services/DeepLinkRouter.swift` | Generic deep link router with `DeepLinkRoute` enum (`Codable`, `Hashable`), singleton pattern, main-thread dispatch safety |
| `Services/TokenManager.swift` | FCM token lifecycle management — permission request, APNs registration, Firestore sync |

### Files Modified

| File | Change |
|------|--------|
| `AppDelegate.swift` | Added `UNUserNotificationCenterDelegate` methods for notification tap handling and foreground presentation; registered delegate in `didFinishLaunchingWithOptions` |
| `LetsDoItApp.swift` | Inject `DeepLinkRouter.shared` into view hierarchy via `.environment()` |
| `HomeView.swift` | Added `@Environment(DeepLinkRouter.self)`, `selectedTab` state, tab switching on deep link, and `NotificationCenter` listener for `.openConversation` |
| `MessagesTabView.swift` | Added `NavigationStack(path:)` with programmatic path navigation, `@Environment(DeepLinkRouter.self)`, `.onChange(of: router.route)` to push conversation on deep link |
| `ContactsListView.swift` | Added "Message" button (`message.fill` icon) to each `ContactRow` — calls `MessagingManager.createDM`, then posts `.openConversation` notification |
| `AuthManager.swift` | Replaced ad-hoc FCM token sync with `TokenManager.setupNotifications(for:)` after sign-in |
| `RootView.swift` | Added `refreshTokenOnLaunch()` call after authentication for already-logged-in users |

---

## New Service Details

### `DeepLinkRouter`

```swift
@Observable final class DeepLinkRouter
```

| Property | Type | Notes |
|---|---|---|
| `shared` | `static DeepLinkRouter` | Singleton instance |
| `route` | `DeepLinkRoute?` | Published route for observers |

| Method | Description |
|---|---|
| `handle(_:)` | Publishes a route. Main-thread only (dispatch precondition). |
| `clear()` | Resets `route` to `nil` after consumption. |
| `handleFCMPayload(_:)` | Parses `conversationId` from FCM `userInfo` dict. Thread-safe (dispatches to main queue). |

### `DeepLinkRoute`

```swift
enum DeepLinkRoute: Codable, Hashable
```

| Case | Description |
|---|---|
| `.conversation(String)` | Navigate to a specific conversation by ID |

Custom `Codable` implementation uses `type`/`id` keys for serialization from notification payloads. Extensible for Sprint 3 (`.event(String)`).

### `TokenManager`

```swift
@MainActor struct TokenManager
```

| Method | Description |
|---|---|
| `requestPermission() async -> Bool` | Requests `.alert`, `.badge`, `.sound` authorization via `UNUserNotificationCenter` |
| `registerForRemoteNotifications()` | Calls `UIApplication.shared.registerForRemoteNotifications()` for APNs |
| `syncTokenToFirestore(uid:) async` | Fetches FCM token via `Messaging.messaging().token()`, writes to `users/{uid}/fcmToken` |
| `setupNotifications(for:) async` | Orchestrator: checks auth status, requests permission if not determined, registers APNs, syncs token |
| `refreshTokenIfAvailable() async` | Refreshes token on app launch for already-authenticated users |

---

## Modified File Details

### `AppDelegate.swift`

| Method | Description |
|---|---|
| `userNotificationCenter(_:didReceive:withCompletionHandler:)` | Parses `conversationId` from notification payload → `DeepLinkRouter.shared.handleFCMPayload(userInfo)` |
| `userNotificationCenter(_:willPresent:withCompletionHandler:)` | Shows banner + sound for foreground notifications |

### `HomeView.swift`

| Property | Type | Notes |
|---|---|---|
| `router` | `@Environment(DeepLinkRouter.self)` | Consumed from app root environment |
| `selectedTab` | `@State Int` | Controls `TabView` selection (0=Activity, 1=Messages, 2=Contacts) |

| Behavior | Trigger |
|---|---|
| `.onChange(of: router.route)` | Any deep link → switches `selectedTab` to Messages (1) |
| `.onReceive(.openConversation)` | Notification from `ContactsListView` → sets tab + calls `router.handle(.conversation(id))` |

### `MessagesTabView.swift`

| Property | Type | Notes |
|---|---|---|
| `navPath` | `@State NavigationPath` | Heterogeneous path supporting `Conversation` (list taps) and `String` (deep links) |

| Modifier | Description |
|---|---|
| `.navigationDestination(for: Conversation.self)` | Standard list → thread navigation |
| `.navigationDestination(for: String.self)` | Deep link destination — looks up `Conversation` from `MessagingManager.conversations`, passes `nil` if not yet loaded |
| `.onChange(of: router.route)` | Appends `conversationId` to `navPath`, calls `router.clear()` |

### `ContactsListView.swift`

| Property | Type | Notes |
|---|---|---|
| `messagingContactId` | `@State String?` | Tracks which contact is being messaged (for loading state) |
| `messageError` | `@State String?` | Error message for failed `createDM` |

| Method | Description |
|---|---|
| `startMessage(contact:)` | Calls `MessagingManager.shared.createDM(with:)`, posts `.openConversation` notification on success |

### `ContactRow`

| Property | Type | Notes |
|---|---|---|
| `isMessaging` | `Bool` | Shows `ProgressView` when message button is tapped |
| `onMessage` | `() -> Void` | Callback to parent's `startMessage` |

### `AuthManager.swift`

| Change | Description |
|---|---|
| `signInAnonymously()` | Replaced inline FCM token sync with `Task { await TokenManager.setupNotifications(for: uid) }` |

---

## Architecture Decisions

1. **`@Observable` instead of `ObservableObject` (deviation from spec)** — The spec recommends `ObservableObject` with `@Published`, but this caused a compile error (`type 'DeepLinkRouter' does not conform to protocol 'ObservableObject'`) under Swift 6 strict concurrency when combined with `@MainActor`. The project targets iOS 17+ (SDK 26.2), which supports the modern Observation framework. `@Observable` provides the same reactive behavior without the conformance conflict. Consumers use `@Environment(DeepLinkRouter.self)` instead of `@EnvironmentObject` — functionally equivalent.

2. **`.environment()` injection instead of `@StateObject` + `.environmentObject()` (deviation from spec)** — The spec says to create `@StateObject var router = DeepLinkRouter.shared` and inject via `.environmentObject()`. However, `@StateObject` calls `init()` and takes ownership of the object's lifecycle, which fails for singletons with a private `init()`. The correct pattern is to pass the shared instance directly via `.environment(DeepLinkRouter.shared)`, which SwiftUI's Observation framework then provides to any descendant using `@Environment(DeepLinkRouter.self)`.

3. **`NotificationCenter` as bridge between ContactsListView and MessagesTabView** — `ContactsListView` lives inside a separate tab (`ContactsTabView`) from `MessagesTabView`. The cleanest cross-tab communication is a notification: `ContactsListView` posts `.openConversation`, `HomeView` catches it, switches tabs, and routes via the `DeepLinkRouter`. This avoids tight coupling between the tabs.

4. **`NavigationPath` with heterogeneous types** — The navigation stack supports both `Conversation` (from list row taps) and `String` conversation IDs (from deep links). Deep links use `String` because the conversation may not yet be loaded in `MessagingManager.conversations` when the notification arrives. `ChatView` already accepts `Conversation?` and handles `nil`.

5. **Main-thread enforcement in `DeepLinkRouter.handle(_:)`** — A `dispatchPrecondition(condition: .onQueue(.main))` ensures that route changes always happen on the main thread, preventing SwiftUI update crashes from background notification callbacks.

6. **`handleFCMPayload` dispatches to main queue asynchronously** — The FCM payload may arrive on a background queue. Parsing is done synchronously, but the route publication is dispatched to `DispatchQueue.main.async` to satisfy the main-thread precondition.

7. **TokenManager respects user's notification preference** — `setupNotifications` checks `UNUserNotificationCenter.current().notificationSettings()` before requesting permission. If the user previously denied, it skips the request (no re-prompt) but still syncs the token if one exists.

---

## Spec vs. Actual — Deviations Summary

| Spec Says | Actual | Reason |
|---|---|---|
| `DeepLinkRouter: ObservableObject` with `@Published` | `@Observable` class | `ObservableObject` + `@MainActor` caused Swift 6 conformance failure. `@Observable` is the modern equivalent. |
| `@StateObject var router = DeepLinkRouter.shared` + `.environmentObject()` | `.environment(DeepLinkRouter.shared)` | `@StateObject` takes ownership and must call `init()`, which is impossible for singletons with a private initializer. |
| "Ensure the enum is `Codable` so it can be serialized from FCM `data` payload" | Custom `Codable` with `type`/`id` keys (not raw `Codable`) | FCM payloads don't match Swift's default `enum` encoding. Custom `init(from:)` / `encode(to:)` maps to the `type` + `id` structure used in Cloud Functions' notification data. |

---

## Build Verification
```
xcodebuild -scheme LetsDoIt -destination 'platform=iOS Simulator,name=iPhone 17' build
→ BUILD SUCCEEDED
```
