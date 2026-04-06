# Phase 1, Step 2: EventManager Service

**Date:** 2026-04-06
**Build Status:** ✅ BUILD SUCCEEDED

---

## What Was Done

### New Files

| File | Purpose |
|------|---------|
| `Services/EventManager.swift` | Central service for events CRUD, RSVP management, and real-time listener |

### Modified Files

| File | Change |
|------|--------|
| `firebase/rules/firestore.rules` | Updated event `allow update` rule to permit invitees to update `rsvps` field only |

---

## EventManager Service

### Pattern

Follows the established singleton pattern from `MessagingManager`:
- `@MainActor class EventManager: ObservableObject`
- `static let shared = EventManager()`
- `@Published` arrays for reactive UI updates
- `ListenerRegistration` for Firestore real-time listener
- `Date` ↔ `Timestamp` conversion in read/write methods
- Error enum at file bottom with `LocalizedError` conformance

### Properties

| Property | Type | Description |
|----------|------|-------------|
| `events` | `[Event]` | Upcoming events (dateTime >= now), sorted ascending |
| `pastEvents` | `[Event]` | Past events (dateTime < now), sorted descending |
| `db` | `Firestore` | Private Firestore instance |
| `listener` | `ListenerRegistration?` | Private real-time listener handle |

### Methods

#### CRUD

| Method | Signature | Description |
|--------|-----------|-------------|
| `createEvent` | `(title:description:location:dateTime:invitees:createConversation:) async throws -> Event` | Creates event doc. Auto-adds creator to invitees. Auto-accepts creator RSVP. Optionally creates linked group conversation via `MessagingManager.createGroup()`. |
| `updateEvent` | `(_ event: Event) async throws` | Updates all mutable fields. Verifies caller is creator. |
| `cancelEvent` | `(id: String) async throws` | Sets `status` to `.cancelled`. Verifies caller is creator. |
| `deleteEvent` | `(id: String) async throws` | Deletes event doc entirely. Verifies caller is creator. |

#### RSVP

| Method | Signature | Description |
|--------|-----------|-------------|
| `rsvp` | `(eventId: String, status: RSVPStatus) async throws` | Updates `rsvps[myUid]` via single-field write. Verifies user is an invitee. |

#### Real-Time Listener

| Method | Signature | Description |
|--------|-----------|-------------|
| `startListening` | `func startListening()` | Listens to `events` where current UID is in `invitees`. Splits into upcoming/past, sorts appropriately. |
| `stopListening` | `func stopListening()` | Removes listener, clears both arrays. |

#### Helpers

| Method | Signature | Description |
|--------|-----------|-------------|
| `inviteeName` | `(for uid: String, in event: Event) -> String` | Resolves display name from `ContactManager.shared.contacts`. Falls back to "Unknown". Synchronous — no Firestore round-trip. |

### Error Types

| Case | Description |
|------|-------------|
| `notAuthenticated` | User not signed in |
| `eventNotFound` | Event document doesn't exist |
| `notCreator` | User is not the event creator |
| `notInvitee` | User is not in the event's invitees list |
| `invalidEventData` | Event data failed decoding |

---

## Firestore Rule Change

### Before
```
allow update: if isAuthenticated() &&
                 request.auth.uid == resource.data.createdBy;
```

### After
```
allow update: if isAuthenticated() &&
                 (request.auth.uid == resource.data.createdBy ||
                  (request.auth.uid in resource.data.invitees &&
                   request.resource.data.diff(resource.data).affectedKeys().hasOnly(['rsvps'])));
```

**Rationale:** Creator retains full update access. Invitees can update ONLY the `rsvps` field, enabling instant RSVP feedback without Cloud Function latency. The `diff().affectedKeys().hasOnly()` constraint prevents invitees from modifying any other field.

---

## Key Design Decisions

1. **Creator auto-accepted** — `createEvent` seeds `rsvps` with `{ creatorUid: "accepted" }`. The creator doesn't need to RSVP to their own event.

2. **Creator in invitees list** — `createEvent` ensures the creator's UID is in the `invitees` array (required by the `arrayContains` listener query and the `read` security rule).

3. **Synchronous `inviteeName`** — Unlike `MessagingManager.fetchDisplayName()` which does a Firestore read, `inviteeName(for:in:)` resolves from `ContactManager.shared.contacts` (already in-memory). If a UID isn't in contacts, returns "Unknown". This avoids N Firestore reads per attendee list render.

4. **`createdAt`/`updatedAt` nil on create** — Since timestamps use `FieldValue.serverTimestamp()`, the returned `Event` from `createEvent` has nil for these fields. They're populated when the real-time listener fires with the server-written values. This matches the established `MessagingManager.createDM()` pattern.

5. **Separate `cancelEvent` method** — Cancelling is semantically distinct from general updates. Keeping it separate makes intent clear and provides a natural hook for future Cloud Function triggers (e.g., notify invitees of cancellation).

6. **Past events sorted descending** — Recently-completed events appear first in the past list, matching user expectation ("what just happened?").

---

## Build Verification

```
xcodebuild -scheme LetsDoIt -destination 'platform=iOS Simulator,name=iPhone 17' build
→ BUILD SUCCEEDED
```
