# Phase 2, Step 5 — Create & Edit Event Views

**Date:** 2026-04-06
**Build status:** BUILD SUCCEEDED

---

## What Was Done

### New Files (2)

| File | Purpose |
|------|---------|
| `LetsDoIt/Views/Events/CreateEventView.swift` | Form for creating events with title, description, location, date/time, invitee picker, and group chat toggle |
| `LetsDoIt/Views/Events/EditEventView.swift` | Form for editing existing events (creator only), with Cancel Event button |

### Modified Files (1)

| File | Change |
|------|--------|
| `LetsDoIt/Views/Events/EventsTabView.swift` | Replaced placeholder sheet with `CreateEventView`, added `eventToEdit` state and `.sheet(item:)` for `EditEventView` |

---

## CreateEventView

A form presented as a sheet from the Events tab's "+" toolbar button.

### Fields

| Field | Type | Validation |
|-------|------|------------|
| Title | `TextField` | Required, 1–100 characters, trimmed |
| Description | `TextField` (multi-line) | Optional |
| Location | `TextField` | Optional |
| Date & Time | `DatePicker` | Must be in the future (`Date()...`) |
| Invitees | `MultiContactPickerView` (sheet) | At least 1 contact required |
| Group Chat | `Toggle` | Default: on; controls `createConversation` parameter |

### Key Methods

| Method | Description |
|--------|-------------|
| `save()` | Validates, calls `EventManager.createEvent()`, invokes `onCreate` callback, dismisses |

### Architecture

- Follows the same pattern as `CreateCustomActivityView.swift`: Form in NavigationStack, validation via `isValid` computed property, error display in red Section, async Task-based save.
- Reuses `MultiContactPickerView` for invitee selection (bound to `$selectedUids`).
- `onCreate: (Event) -> Void` callback — parent uses `{ _ in }` since the real-time listener auto-populates the list.

---

## EditEventView

A form presented as a sheet when editing an existing event. Only accessible to the event creator.

### Fields

Same as `CreateEventView`, but pre-filled from the passed `Event`.

| Field | Difference from Create |
|-------|----------------------|
| Date & Time | No minimum date constraint (editing may adjust to past times) |
| Invitees | Pre-populated with existing invitees (excluding creator, who is auto-added on save) |
| Group Chat | Toggle only shown if `event.conversationId != nil`; disabling doesn't delete the existing conversation |

### Key Methods

| Method | Description |
|--------|-------------|
| `save()` | Rebuilds full invitees list (others + creator), constructs new `Event` instance, calls `EventManager.updateEvent()` |
| `cancelEvent()` | Calls `EventManager.cancelEvent(id:)`, dismisses on success |

### Architecture

- Uses custom `init(event:onUpdate:)` to seed `@State` properties from the immutable `Event` struct.
- Rebuilds a new `Event` instance on save (since `Event` properties are `let`), preserving `rsvps`, `createdAt`, and `conversationId`.
- "Danger Zone" section with destructive "Cancel Event" button and confirmation alert.
- `onUpdate: (Event) -> Void` callback — parent uses `{ _ in }` since the listener auto-refreshes.

---

## EventsTabView Changes

| Change | Description |
|--------|-------------|
| Replaced placeholder | `Text("Create Event form coming in Step 5")` → `CreateEventView(onCreate:)` |
| Added `eventToEdit` | `@State private var eventToEdit: Event?` for triggering edit sheet |
| Added edit sheet | `.sheet(item: $eventToEdit) { EditEventView(event: $0) }` |

**Note:** The `eventToEdit` sheet is wired but not yet triggered from the UI. The Edit button will be added in Step 6 (Event Detail View), which will navigate to `EditEventView` from the detail screen.

---

## Architecture Decisions

1. **Future-only validation for creation, not editing** — `CreateEventView` enforces `dateTime > Date()` via the DatePicker's `in:` parameter. `EditEventView` removes this constraint because you may need to adjust an event's time to earlier on the same day, or correct a mistakenly-set date.

2. **Invitees exclude creator in the picker** — Both views store invitees in `selectedUids` excluding the creator. On save, the creator is re-added to ensure they always have read access (per security rules). This prevents the user from accidentally removing themselves.

3. **Event struct immutability respected** — `Event` uses `let` properties. `EditEventView` constructs a new `Event` instance rather than attempting mutation, preserving the pure Swift model pattern.

4. **`conversationId` not changed in edit** — The group chat toggle in `EditEventView` only appears if the event already has a `conversationId`. Turning it off doesn't delete the conversation (that would be a separate feature). Creating a new conversation for an event that didn't have one is deferred — the `createEvent` Cloud Function handles the one-time creation.

5. **Error handling via `errorMessage` state** — Both views display errors in a red Section at the bottom of the form, matching the pattern established in `CreateCustomActivityView`.

---

## Build Verification

```
xcodebuild -scheme LetsDoIt -destination 'platform=iOS Simulator,name=iPhone 17' build
→ BUILD SUCCEEDED
```

Initial build failed due to missing `import FirebaseAuth` in `EditEventView.swift` (used for `Auth.auth().currentUser?.uid` in the `init` and `currentUid` property). Fixed by adding the import and using the standard `Auth` shorthand.
