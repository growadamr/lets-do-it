# Phase 3, Step 7: Deep Linking for Events

**Date:** 2026-04-06
**Build Status:** ✅ BUILD SUCCEEDED

---

## What Was Done

### Modified Files

| File | Change |
|------|--------|
| `Views/HomeView.swift` | Added `.onReceive` for `.openEvent` notification |

---

## Detailed Changes

### HomeView.swift

Added notification observer for `.openEvent` to enable cross-app event navigation:

```swift
.onReceive(NotificationCenter.default.publisher(for: .openEvent)) { notification in
    guard let eventId = notification.userInfo?["id"] as? String else { return }
    selectedTab = 3
    router.handle(.event(eventId))
}
```

**Behavior:**
1. Extracts `eventId` from `userInfo["id"]`
2. Switches the TabView to the Events tab (tag 3)
3. Publishes `.event(eventId)` route on `DeepLinkRouter`
4. `EventsTabView` observes the route change, sets `selectedEventId`, and navigates to `EventDetailView`

**What was already in place (from Steps 4 & 6):**
- `DeepLinkRoute.event(String)` enum case with Codable conformance
- `DeepLinkRouter.handleFCMPayload` parsing `eventId` from FCM data payloads
- `Notification.Name.openEvent` declaration
- `HomeView` Events tab (tag 3) and `.onChange(of: router.route)` switching to it for `.event` routes
- `EventsTabView` `.onChange(of: router.route)` handling `.event(let id)` → `selectedEventId`
- `AppDelegate` delegating notification tap handling to `DeepLinkRouter.shared.handleFCMPayload`

**What this step added:**
- The final connecting wire: `.onReceive(.openEvent)` in `HomeView` so that posting the notification from anywhere in the app (e.g., `EventDetailView`'s "Open Chat" button, or other cross-app triggers) correctly routes to the Events tab and event detail.

---

## Architecture Decisions

1. **Single-line addition** — Steps 4 and 6 had already laid all the groundwork for event deep linking. Step 7 only required the `.openEvent` notification observer in `HomeView` to complete the chain. No new types, services, or views were needed.

2. **Consistent with existing pattern** — The `.onReceive(.openEvent)` mirrors the existing `.onReceive(.openConversation)` pattern: switch to the correct tab, then delegate route publishing to `DeepLinkRouter`. This keeps cross-tab navigation consistent and predictable.

3. **Two-path event navigation** — Events can be reached via:
   - **FCM notification tap** → `AppDelegate` → `DeepLinkRouter.handleFCMPayload` → `router.handle(.event(id))` → `HomeView.onChange(of: router.route)` → tab 3 → `EventsTabView.onChange` → `selectedEventId` → `EventDetailView`
   - **NotificationCenter post** → `NotificationCenter.post(name: .openEvent, userInfo: ["id": eventId])` → `HomeView.onReceive(.openEvent)` → tab 3 + `router.handle(.event(id))` → same chain

---

## Build Verification

```
xcodebuild -scheme LetsDoIt -destination 'platform=iOS Simulator,name=iPhone 17' build
** BUILD SUCCEEDED **
```
