# Bug Fix Plan

## Bug 1: Multiple Sheet Presentation Cascade

**Severity:** ~~🔴 High~~ ✅ Fixed

**Status:** Fixed — 2026-04-07. Build verified clean of sheet cascade warnings.

### What Was Done

Consolidated multiple concurrent `.sheet(isPresented:)` / `.sheet(item:)` modifiers into single `.sheet(item:)` driven by an enum per view hierarchy.

**`ActivityTabView.swift`**
- Removed `@State var showingSchedules` and `@State var showingSettings`
- Added `enum ActivitySheet: Identifiable` with cases `.schedules(contactUid)`, `.settings(contactUid)`, `.nameContact(Contact)`
- Added `@State var activeSheet: ActivitySheet?`
- Added `.onChange(of: contactManager.pendingContactForNaming)` to bridge the external `ContactManager` signal into the enum case, then clear the source to prevent re-triggering
- Replaced 3 separate `.sheet()` modifiers with 1 `.sheet(item: $activeSheet)`

**`MatchesLandingView.swift`**
- Removed duplicate `.sheet(item: $contactManager.pendingContactForNaming)` block (parent `ActivityTabView` now handles it)

**`ContactsListView.swift`**
- Removed `@State var showAddContact` and `@State var showCreateCode`
- Added `enum ContactsSheet: Identifiable` with cases `.addContact`, `.createCode`, `.nameContact(Contact)`
- Added `@State var activeSheet: ContactsSheet?`
- Added `.onChange(of: contactManager.pendingContactForNaming)` with same bridging pattern
- Replaced 3 separate `.sheet()` modifiers with 1 `.sheet(item: $activeSheet)`

### Verification
- Build succeeded with no errors
- Test run produced zero instances of:
  - `"Currently, only presenting a single sheet is supported"`
  - `"Attempt to present ... while a presentation is in progress"`
  - `"Attempt to present ... whose view is not in the window hierarchy"`

---

## Bug 1: Multiple Sheet Presentation Cascade (Original Report)

**Severity:** 🔴 High

### Root Cause
Multiple views stack `.sheet(isPresented:)` modifiers that can fire simultaneously. The primary offender: `$pendingContactForNaming` is declared in **both** `ActivityTabView` and `MatchesLandingView` at the same time (since `MatchesLandingView` is rendered inside `ActivityTabView`'s `landingView`). Both try to present on the same window.

Full sheet inventory across the app:

| View | Sheets |
|------|--------|
| `ActivityTabView.contactSelectedView` | `$showingSchedules`, `$showingSettings`, `$pendingContactForNaming` |
| `MatchesLandingView` | `$showingContacts` (fullscreenCover), `$selectedMatch`, `$pendingContactForNaming` |
| `ContactsListView` | `$showAddContact`, `$showCreateCode`, `$pendingContactForNaming` |
| `ConversationsListView` | `$showingNewConversation` |
| `EventsTabView` | `$showCreateEvent`, `$eventToEdit` |
| `ChatView` | `$showingImagePicker` |
| `ActivitySettingsView` | `$showingEditActivity` |

The cascade produces:
- `"Currently, only presenting a single sheet is supported"` (x10+)
- `"Attempt to present ... while a presentation is in progress"`
- `"Attempt to present ... whose view is not in the window hierarchy"`

### Fix Approach
Centralize sheet management per view hierarchy using an enum + single `.sheet(item:)`.

**Fix 1A: `ActivityTabView`** — Replace `$showingSchedules`, `$showingSettings`, and the duplicate `$pendingContactForNaming` with a single enum:

```swift
enum ActivitySheet: Identifiable {
    case schedules
    case settings(contactUid: String)
    case nameContact(ContactManager.Contact)
    var id: String {
        switch self {
        case .schedules: return "schedules"
        case .settings(let uid): return "settings-\(uid)"
        case .nameContact(let c): return "name-\(c.uid)"
        }
    }
}
```

Replace the three separate `.sheet()` modifiers with one:
```swift
.sheet(item: $activeSheet) { sheet in
    switch sheet {
    case .schedules: ScheduledActivitiesListView(...)
    case .settings(let uid): ActivitySettingsView(contactUid: uid)
    case .nameContact(let contact): SetContactNameSheet(contact: contact)
    }
}
```

**Fix 1B: `MatchesLandingView`** — Remove the `$pendingContactForNaming` sheet (handled by parent `ActivityTabView`). Keep only `$showingContacts` and `$selectedMatch` (these two are mutually exclusive in practice — one is a fullscreenCover, one is a sheet — but consider consolidating if warnings persist).

**Fix 1C: `ContactsListView`** — Consolidate `$showAddContact`, `$showCreateCode`, `$pendingContactForNaming` into a `ContactsSheet` enum with one `.sheet(item:)`.

### Files to Change
- `Views/ActivityTabView.swift`
- `Views/Activities/MatchesLandingView.swift`
- `Views/ContactsListView.swift`

---

## Bug 2: FCM Token Retry Spam Without APNs

**Severity:** ~~🔴 High~~ ✅ Fixed

**Status:** Fixed — 2026-04-07. Build verified clean. Console no longer emits error 505 spam.

### What Was Done

Gated the FCM token fetch behind an APNs token availability flag, eliminating wasted `Messaging.messaging().token()` calls that throw error 505 on every launch.

**`TokenManager.swift`**
- Added `static var apnsTokenReceived: Bool = false` flag
- Added `guard apnsTokenReceived else { return }` at the top of `syncTokenToFirestore(uid:)` — silently skips when APNs hasn't arrived
- Removed `await syncTokenToFirestore(uid: uid)` from `setupNotifications(for:)` — no more premature FCM token fetch

**`AppDelegate.swift`**
- In `didRegisterForRemoteNotificationsWithDeviceToken`: sets `TokenManager.apnsTokenReceived = true` then calls `refreshTokenIfAvailable()` to trigger the sync
- In `messaging(_:didReceiveRegistrationToken:)`: added a `Task` calling `refreshTokenIfAvailable()` as a safety net for when the FCM token arrives after APNs is already set

### Flow After Fix
| Scenario | Before | After |
|----------|--------|-------|
| First launch, APNs not yet arrived | `syncTokenToFirestore` called → error 505 → logged | Guard returns early → silent |
| APNs token arrives (physical device + paid account) | No sync triggered | Flag set → `refreshTokenIfAvailable()` → token synced |
| Physical device, no paid dev account (APNs never comes) | Repeated error 505 on every launch | Guard always returns early → zero noise |
| App launch (returning user) | `refreshTokenIfAvailable` → error 505 if APNs not ready | Same guard applies → silent skip |

---

## Bug 2: FCM Token Retry Spam Without APNs (Original Report)

**Severity:** 🔴 High

### Root Cause
`TokenManager.syncTokenToFirestore()` calls `Messaging.messaging().token()` which throws error 505 when no APNs token is set. This is called from `setupNotifications()` on every launch and `refreshTokenIfAvailable()`. On a physical device without a paid Apple Developer account, APNs never delivers a token, so every call fails with a printed error:

```
[TokenManager] Failed to sync FCM token: Error Domain=com.google.fcm Code=505
```

### Fix Approach
Gate the FCM token fetch behind an APNs token availability check.

Add an `apnsTokenReady` flag:

1. In `AppDelegate.didRegisterForRemoteNotificationsWithDeviceToken`, set a flag (e.g., `TokenManager.apnsTokenReceived = true`)
2. In `TokenManager.syncTokenToFirestore()`, skip the sync if `apnsTokenReady` is false — no error log, no wasted call
3. In `TokenManager.setupNotifications()`, only call `syncTokenToFirestore()` after the APNs token arrives (or skip entirely if denied)

### Files to Change
- `Services/TokenManager.swift`
- `AppDelegate.swift`

---

## Bug 3: Keyboard Auto Layout Constraint Conflicts in ChatView

**Severity:** 🟡 Medium

### Root Cause
`ChatView` uses a `ScrollView` + `VStack` layout where the `TextField` in `inputBar` creates an internal `UITextView`. Its input view constraints conflict with the keyboard's accessory view constraints (`'accessoryView.bottom'` vs `'inputView.top'`). iOS auto-resolves by breaking one constraint, but logs warnings repeatedly.

```
Unable to simultaneously satisfy constraints.
'accessoryView.bottom' ... 'inputView.top' ...
Will attempt to recover by breaking constraint
```

### Fix Approach
Add `.ignoresSafeArea(.keyboard, edges: .bottom)` to the `ScrollView` (the `messageScrollView` only, not the entire outer `VStack`). This prevents the keyboard from fighting with the scroll view's internal layout.

### Files to Change
- `Views/Messaging/ChatView.swift`

---

## Bug 4: Deep Link Navigation Multi-Frame Update

**Severity:** 🟡 Medium

### Root Cause
`HomeView` responds to `router.route` changes by setting `selectedTab`. `MessagesTabView` also observes `router.route` and appends to `navPath`. Both fire in the same render frame, causing SwiftUI's `NavigationStack` to log:

```
Update NavigationRequestObserver tried to update multiple times per frame.
```

`DeepLinkRouter.handle()` sets `self.route` synchronously with no debounce or frame deferral.

### Fix Approach
Wrap `self.route = route` in `DeepLinkRouter.handle(_:)` with `DispatchQueue.main.async { self.route = route }`. This defers the state change to the next runloop cycle, giving SwiftUI observers time to settle before the navigation state changes.

### Files to Change
- `Services/DeepLinkRouter.swift`

---

## Summary

| Bug | Severity | Files | Change |
|-----|----------|-------|--------|
| 1. Multiple sheet cascade | 🔴 | 3 | Enum-based sheet consolidation in `ActivityTabView`, `MatchesLandingView`, `ContactsListView` |
| 2. FCM token retry spam | 🔴 | 2 | APNs-gated token sync in `TokenManager`, flag in `AppDelegate` |
| 3. Keyboard constraint conflicts | 🟡 | 1 | `.ignoresSafeArea(.keyboard)` on `ChatView` scroll area |
| 4. Deep link multi-frame update | 🟡 | 1 | `DispatchQueue.main.async` in `DeepLinkRouter.handle()` |
