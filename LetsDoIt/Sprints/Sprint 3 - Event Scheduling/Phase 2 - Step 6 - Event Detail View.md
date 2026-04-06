# Phase 2 — Step 6: Event Detail View

**Date:** 2026-04-06
**Build Status:** ✅ BUILD SUCCEEDED

---

## What Was Done

### New Files

| File | Purpose |
|------|---------|
| `Views/Events/EventDetailView.swift` | Full event detail with RSVP buttons, attendee list, Open Chat, and Edit |

### Modified Files

| File | Change |
|------|--------|
| `Views/Events/EventsListView.swift` | Added `onSelectEvent` closure parameter; rows now call it on tap |
| `Views/Events/EventsTabView.swift` | Wired `.navigationDestination` for `selectedEventId`; updated `.onChange(of: router.route)` to set it; passed `onSelectEvent` callback to `EventsListView`; added `findEvent(by:)` helper |

---

## EventDetailView

### UI Layout

1. **Header Section** — Title (from `.navigationTitle`), cancelled badge (if applicable), formatted date/time, location (if present), description (if present), divider, "Created by {name}" label.

2. **RSVP Section** — Three buttons (Accept / Maybe / Decline) in a rounded-rectangle card. The current user's RSVP is highlighted with accent color. Buttons are disabled while RSVPing or if the event is cancelled. Tapping a button calls `EventManager.rsvp(eventId:status:)`.

3. **Attendee List** — `ScrollView` with grouped `Section` headers for each RSVP status:
   - **Accepted** (green, checkmark icon)
   - **Maybe** (orange, question mark icon)
   - **Declined** (red, xmark icon)
   - **No Response** (gray, person icon)
   
   Each row shows a contact avatar circle, display name (resolved via `EventManager.inviteeName(for:in:)`), and a "(You)" suffix for the current user.

4. **Open Chat Button** — Full-width accent button, only visible when `event.conversationId` is non-nil and non-empty. Posts `NotificationCenter.openConversation` with `["id": conversationId]`.

5. **Edit Button** — Toolbar trailing button, only visible when `eventManager.isCreator(event)` is true. Presents `EditEventView` in a `.sheet(item:)`. On sheet dismiss, checks if the event was deleted and dismisses the detail view if so.

### Properties & Methods

| Property/Method | Type | Purpose |
|-----------------|------|---------|
| `event: Event` | `let` | The event to display |
| `myRSVP` | `RSVPStatus?` | Current user's RSVP status |
| `isCreator` | `Bool` | Whether current user created the event |
| `attendeesByStatus` | Computed tuple | Groups all invitees into accepted/maybe/declined/noResponse arrays |
| `submitRSVP(_:)` | `func` | Async RSVP submission with loading/error state |
| `attendeeGroup(title:icon:tint:attendees:)` | `@ViewBuilder` | Reusable attendee group section |
| `openChatButton(_:)` | `@ViewBuilder` | Open Chat button (posts notification) |

### Architecture Decisions

1. **Push-based navigation from list** — `EventsListView` accepts an `onSelectEvent` closure that `EventsTabView` uses to set `selectedEventId`. This keeps the list view decoupled from navigation state while enabling `.navigationDestination` in the tab shell.

2. **Deep link → navigation** — `.onChange(of: router.route)` sets `selectedEventId` which triggers `.navigationDestination`. Same code path as tapping a list row, ensuring consistent behavior.

3. **Event lookup across both arrays** — `findEvent(by:)` checks both `eventManager.events` (upcoming) and `eventManager.pastEvents` (past) because deep links and taps could target either.

4. **RSVP idempotency** — `submitRSVP` checks `myRSVP == status` before making the network call, avoiding unnecessary writes when the user taps their existing selection.

5. **Open Chat via notification** — Reuses the existing `Notification.Name.openConversation` pattern from `MatchDetailView`. The Messages tab (already implemented in Sprint 1) observes this and navigates to the conversation. No new deep link plumbing needed.

6. **AttendeeInfo struct** — Private nested struct bundles UID, display name, RSVP status, and "isYou" flag to avoid repeated lookups in `ForEach`.

---

## Build Verification

```
xcodebuild -scheme LetsDoIt -destination 'platform=iOS Simulator,name=iPhone 17' build
→ BUILD SUCCEEDED
```

Initial failure: `Date.FormatStyle.DateStyle` has no member `.full`. Fixed by using `.abbreviated` (consistent with `EventsListView`). Secondary: unused variable warning on `uid` in `submitRSVP`, fixed by using `currentUid != nil` boolean check.
