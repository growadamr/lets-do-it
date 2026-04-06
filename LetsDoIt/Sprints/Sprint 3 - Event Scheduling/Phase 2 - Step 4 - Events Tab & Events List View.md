# Phase 2, Step 4 — Events Tab & Events List View

**Date:** 2026-04-06
**Build Status:** ✅ BUILD SUCCEEDED

---

## What Was Done

### New Files

| File | Purpose |
|------|---------|
| `Views/Events/EventsListView.swift` | Upcoming/Past event list with RSVP summaries and swipe-to-delete |
| `Views/Events/EventsTabView.swift` | Events tab shell with NavigationStack and toolbar "+" button |

### Modified Files

| File | Change |
|------|--------|
| `Views/HomeView.swift` | Added Events tab (tag 3), updated deep link route switch to handle `.event` → tab 3 |
| `Services/EventManager.swift` | Added `isCreator(_ event:) -> Bool` helper |
| `Services/DeepLinkRouter.swift` | Added `case event(String)` to `DeepLinkRoute`, updated Codable conformance, added `.openEvent` notification name, extended `handleFCMPayload` to parse `eventId` |

---

## EventsListView

Displays events from `EventManager`'s `@Published` arrays in two grouped sections:

### Layout

- **Empty state:** `ContentUnavailableView` when both `events` and `pastEvents` are empty
- **Upcoming section:** Events sorted by `dateTime` ascending (soonest first) — managed by `EventManager`
- **Past section:** Events sorted by `dateTime` descending (most recent first) — managed by `EventManager`

### Event Row

Each row shows:
| Element | Format |
|---------|--------|
| Title | Bold headline |
| Cancelled badge | Red capsule if `status == .cancelled` |
| Date | `formatted(date: .abbreviated, time: .shortened)` with calendar icon |
| Location | `mappin` icon + location string (only if present) |
| RSVP summary | "3 accepted · 1 maybe · 2 declined" (only non-zero counts, joined by ` · `) |

### Swipe Actions

- Creator-only: swipe-to-delete with `.confirmationDialog` for confirmation
- Calls `EventManager.deleteEvent(id:)`

### Architecture

- Receives `EventManager` via `@EnvironmentObject` (injected by `EventsTabView`)
- Delete confirmation uses `.confirmationDialog` (not `.alert`) for consistency with SwiftUI best practices

---

## EventsTabView

Tab shell following the established `MessagesTabView` pattern:

### Structure

```
NavigationStack
  └── EventsListView (with .environmentObject(EventManager.shared))
```

### Lifecycle

- `.task` → `eventManager.startListening()`
- `.onDisappear` → `eventManager.stopListening()`

### Toolbar

- **"+" button** (topBarTrailing): Presents a `.sheet` with a placeholder "Create Event form coming in Step 5"
  - Step 5 will replace this with `CreateEventView`

### Deep Link Handling

- Observes `router.route` for `.event(let id)`:
  - Logs the event ID (navigation to `EventDetailView` deferred to Step 6)
  - Clears the route after handling

---

## HomeView Changes

Added the 4th tab to the `TabView`:

```swift
EventsTabView()
    .tabItem { Label("Events", systemImage: "calendar") }
    .tag(3)
```

Updated the `.onChange(of: router.route)` switch to route `.event` → tab 3, `.conversation` → tab 1.

---

## DeepLinkRouter Changes (Prep for Step 7)

### `DeepLinkRoute` enum

Added `case event(String)` — the eventId from FCM payloads or deep links.

### Codable conformance

Updated both `init(from:)` and `encode(to:)` to handle the `"event"` type string.

### `handleFCMPayload`

Refactored to check for **both** `eventId` and `conversationId` in FCM payloads (with `eventId` taking priority). Simplified the extraction logic to check top-level and nested `data` dict uniformly.

### Notification Names

Added `static let openEvent = Notification.Name("openEvent")` for future in-app event opening (e.g., from Contacts tab).

---

## EventManager Changes

Added `isCreator(_ event: Event) -> Bool` — checks if `currentUid == event.createdBy`. Used by `EventsListView` to gate swipe-to-delete to creator only.

---

## Architecture Decisions

1. **`@StateObject` in tab, `@EnvironmentObject` in child** — `EventsTabView` owns the `EventManager` lifecycle (matching `MessagesTabView`'s pattern). `EventsListView` receives it as `@EnvironmentObject`, allowing intermediate views to access it if needed.

2. **Placeholder sheet for create** — The "+" button presents a stub text view rather than leaving the button non-functional. This ensures the UI is complete and the build passes, with a clear marker for Step 5.

3. **`eventId` priority in `handleFCMPayload`** — When both `eventId` and `conversationId` exist in a payload, `eventId` takes priority. This is unlikely in practice but establishes a clear precedence.

4. **Confirmation dialog for delete** — Uses `.confirmationDialog` rather than a custom alert, matching SwiftUI conventions established in the rest of the app.

---

## Build Verification

```
xcodebuild -scheme LetsDoIt -destination 'platform=iOS Simulator,name=iPhone 17' build
→ BUILD SUCCEEDED
```
