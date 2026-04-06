# Sprint 3: Event Scheduling — Implementation Breakdown

**Estimated duration:** 2–3 weeks  
**Complexity:** MEDIUM-HIGH  
**Key risk:** Fourth tab integration, RSVP real-time sync, optional conversation linkage, 3 new Cloud Functions

---

## Overview

Sprint 3 adds multi-person event scheduling with invitations and RSVPs:
- **Create events** with title, date/time, location, description
- **Invite multiple contacts** — each RSVPs independently (accept/decline/maybe)
- **Real-time RSVP updates** via Firestore listeners
- **Optional group chat** — create a conversation linked to the event (uses Sprint 1 messaging)
- **Events tab** — fourth tab in the TabView
- **Push notifications** for event invitations, updates, and RSVP changes
- **Daily cleanup** of past events

### Firestore Schema

```
events/{eventId}
  title: String
  description: String?
  location: String?
  dateTime: Timestamp
  createdBy: String                    // UID of creator
  createdAt: Timestamp
  updatedAt: Timestamp
  invitees: [uid1, uid2, ...]          // array of invited user UIDs
  rsvps: { uid: "accepted" | "declined" | "maybe" }
  conversationId: String?              // links to Sprint 1 conversation (nullable)
  status: "active" | "cancelled"
```

### Security Rules (Already Deployed — Sprint 1, Phase 1, Step 2)

Event rules were pre-authored during Sprint 1's Firebase setup:
```
match /events/{eventId} {
  allow read: if isAuthenticated() && request.auth.uid in resource.data.invitees;
  allow create: if isAuthenticated() && request.resource.data.createdBy == request.auth.uid;
  allow update: if isAuthenticated() && request.auth.uid == resource.data.createdBy;
  allow delete: if isAuthenticated() && request.auth.uid == resource.data.createdBy;
}
```

**Note on rules:** The current `update` rule only allows the **creator** to update. This means invitees cannot RSVP via direct doc update — the RSVP mechanism must either:
- (a) Use a Cloud Function to update RSVPs on behalf of invitees, OR
- (b) Expand the update rule to allow invitees to update only the `rsvps` field

Option (b) is simpler and more responsive (no function latency). The rule change should be:
```
allow update: if isAuthenticated() &&
  (request.auth.uid == resource.data.createdBy ||
   (request.auth.uid in resource.data.invitees &&
    request.resource.data.diff(resource.data).affectedKeys().hasOnly(['rsvps'])));
```
This allows invitees to update ONLY the `rsvps` field while the creator retains full update access.

### Cloud Functions

Sprint 3 adds functions to the **messaging functions project** (`LetsDoIt/firebase/functions/index.js`, v1 API) since events use Firestore document triggers — same pattern as `onMessageCreated` and `onConversationCreated`:

- **`onEventCreated`** — Triggered on `events/{eventId}` `.onCreate`. Sends FCM push to all invitees.
- **`onEventUpdated`** — Triggered on `events/{eventId}` `.onUpdate`. Sends FCM push on date/location/cancellation changes to invitees, and push to creator on RSVP changes.
- **`cleanupPastEvents`** — Scheduled daily. Archives/deletes events older than 7 days past their `dateTime`.

**Note:** `cleanupPastEvents` uses `onSchedule` which is v2 API. It could go in either functions project, but placing it in the messaging project keeps all event-related functions together. If the messaging project doesn't support v2 imports, this function goes in the match functions project (`/hermGameTest/functions/index.js`).

### Existing Assets to Reuse

- `MultiContactPickerView.swift` — built in Sprint 1, reused in Sprint 2, reuse again for event invitee selection
- `DeepLinkRouter.swift` — already has a comment reserving `case event(String)` for Sprint 3
- `ChatPrefillStore.swift` — available if "Open Chat" from event should prefill a message
- `MessagingManager.createGroup()` — for creating the optional event conversation
- `HomeView.swift` — TabView root, needs a 4th tab

### Patterns Established in Sprints 1 & 2 (Must Follow)

1. **Pure Swift models** — `Event` model uses `Date` not `Timestamp`, no `FirebaseFirestore` import. Service handles conversion.

2. **Singleton service pattern** — `@MainActor class EventManager: ObservableObject` with `static let shared`, `@Published` arrays, `ListenerRegistration` for real-time.

3. **Error types in service file** — `EventManagerError` enum at file bottom with `LocalizedError` conformance.

4. **Deep link extension** — Add `case event(String)` to `DeepLinkRoute` enum. `HomeView` switches to Events tab. `EventsTabView` observes route and navigates.

5. **Cloud Functions in messaging project** — v1 API (`functions.firestore.document().onCreate/onUpdate`), `admin.messaging().sendEachForMulticast()` for FCM.

6. **Tab navigation** — Each tab has its own `NavigationStack`. Modals use `.sheet`. Cross-tab navigation uses `NotificationCenter` + `DeepLinkRouter`.

### Sprint 2 Dependencies Used

- `MultiContactPickerView` — invitee picker
- `ActivityDisplayable` protocol — not directly used, but establishes the pattern of protocol-driven display
- `ContactManager.shared` — resolve invitee display names

---

## Phase 1: Data Layer & Service (Steps 1–3)

### Step 1: Event Model & RSVPStatus Enum ✅ COMPLETE

**Goal:** Create the Event model and supporting types.

**New files:**
- `Models/Event.swift` — `Event` struct (Codable, Identifiable, Hashable) with fields: `id`, `title`, `description` (String?), `location` (String?), `dateTime` (Date), `createdBy` (String), `createdAt` (Date?), `updatedAt` (Date?), `invitees` ([String]), `rsvps` ([String: RSVPStatus]), `conversationId` (String?), `status` (EventStatus). **Pure Swift — no FirebaseFirestore import.**
- `RSVPStatus` enum: `.accepted`, `.declined`, `.maybe` — String-backed, Codable
- `EventStatus` enum: `.active`, `.cancelled` — String-backed, Codable

**Build verification:** BUILD SUCCEEDED (2026-04-06)

---

### Step 2: EventManager Service ✅ COMPLETE

**Goal:** Central service for events CRUD, RSVP management, and real-time listener.

**New files:**
- `Services/EventManager.swift` — `@MainActor class EventManager: ObservableObject` (singleton `.shared`)

**Follows established singleton pattern:**
- `static let shared = EventManager()`
- `@Published var events: [Event] = []` — real-time listener, sorted by `dateTime` ascending (upcoming first)
- `@Published var pastEvents: [Event] = []` — events with `dateTime` in the past
- `private let db = Firestore.firestore()`
- `private var listener: ListenerRegistration?`
- `Date` ↔ `Timestamp` conversion in read/write methods

**Responsibilities:**

1. **Events CRUD**
   - `createEvent(title:description:location:dateTime:invitees:createConversation:)` — creates event doc, optionally creates linked group conversation via `MessagingManager.createGroup()`, returns `Event`
   - `updateEvent(_:)` — updates event fields (creator only), sets `updatedAt`
   - `cancelEvent(id:)` — sets `status` to `.cancelled`
   - `deleteEvent(id:)` — deletes event doc

2. **RSVP**
   - `rsvp(eventId:status:)` — updates `rsvps[myUid]` on the event doc (single field update)

3. **Real-time listener**
   - `startListening()` — listens to `events` where current user is in `invitees`, splits into upcoming/past
   - `stopListening()` — removes listener, clears arrays

4. **Helpers**
   - `inviteeName(for uid:, in event:)` — resolves from `ContactManager.contacts`, falls back to "Unknown"

**Modified files:**
- `firebase/rules/firestore.rules` — Updated event `allow update` rule to permit invitees to update `rsvps` field only

**Build verification:** BUILD SUCCEEDED (2026-04-06)

---

### Step 3: Cloud Functions (Event Triggers) ✅ COMPLETE

**Goal:** Push notifications for event lifecycle.

**Modified files:**
- `LetsDoIt/firebase/functions/index.js` — added `onEventCreated`, `onEventUpdated`, and `cleanupPastEvents`

**`onEventCreated`:**
- Trigger: `events/{eventId}` `.onCreate`
- Reads `invitees` array, excludes creator
- Looks up FCM tokens for invitees from `users/{uid}.fcmToken`
- Sends push: "New event invitation" with title, date, location preview
- Data payload: `{ eventId }` for deep linking

**`onEventUpdated`:**
- Trigger: `events/{eventId}` `.onUpdate`
- RSVP changes → personalized push to creator: "{name} accepted/declined/said maybe to your event"
- Detail changes (dateTime, location, status) → push to all invitees with contextual message
- Data payload: `{ eventId }`

**`cleanupPastEvents`:**
- Schedule: daily at 3:00 AM UTC via `functions.pubsub.schedule()`
- Queries `events` where `dateTime` < 7 days ago and `status == "active"`
- Batch deletes all matching documents
- Throws on failure for automatic retry

**Syntax verification:** `node --check` passed (exit code 0)

---

## Phase 2: Core Event UI (Steps 4–6)

### Step 4: Events Tab & Events List View

**Goal:** Add the Events tab to the TabView and build the events list.

**New files:**
- `Views/Events/EventsListView.swift` — two sections: "Upcoming" and "Past", each showing events sorted by date. Upcoming sorted ascending (soonest first), past sorted descending (most recent first). Shows event title, date, location, RSVP count summary. Swipe-to-delete for events the user created. Empty state.
- `Views/Events/EventsTabView.swift` — tab shell with `NavigationStack`, embeds `EventsListView`, toolbar "+" button for creating events. Observes `DeepLinkRouter` for `.event` routes.

**Modified files:**
- `Views/HomeView.swift` — Add Events tab (tag 3) with `EventsTabView`. Update `onChange(of: router.route)` to switch to Events tab for `.event` routes.

---

### Step 5: Create & Edit Event Views

**Goal:** Forms for creating and editing events.

**New files:**
- `Views/Events/CreateEventView.swift` — form with title (required), description (optional), location (optional), date/time picker, invitee picker (using `MultiContactPickerView`), toggle for "Create group chat". On save, calls `EventManager.createEvent()`.
- `Views/Events/EditEventView.swift` — same form pre-filled, only accessible to creator. Save calls `EventManager.updateEvent()`. Cancel event button.

**Validation:**
- Title: required, 1–100 characters
- DateTime: required, must be in the future (for creation)
- Invitees: at least one contact selected

---

### Step 6: Event Detail View

**Goal:** Full event detail with RSVP buttons and attendee list.

**New files:**
- `Views/Events/EventDetailView.swift`

**UI layout:**
- Header: title, date/time (formatted), location (if present), description (if present)
- Status badge if cancelled
- RSVP buttons: Accept / Decline / Maybe — highlighted based on current user's RSVP. Calls `EventManager.rsvp(eventId:status:)`.
- Attendee list: grouped by RSVP status (Accepted, Maybe, Declined, No Response). Shows contact display name resolved via `ContactManager`.
- "Open Chat" button: visible only if `conversationId` is non-nil. Routes to the conversation via `DeepLinkRouter.handle(.conversation(id))`.
- "Edit" button: visible only if current user is the creator. Navigates to `EditEventView`.
- Creator label: "Created by {name}"

---

## Phase 3: Deep Linking & Integration (Steps 7–8)

### Step 7: Deep Linking for Events

**Goal:** Extend the deep link router to support event navigation, wire up notification tap handling.

**Modified files:**
- `Services/DeepLinkRouter.swift` — Add `case event(String)` to `DeepLinkRoute`. Update `Codable` conformance. Add `handleFCMPayload` parsing for `eventId` key. Add `Notification.Name.openEvent`.
- `Views/HomeView.swift` — Add `.onReceive` for `.openEvent` notification, switch to Events tab (tag 3).
- `Views/Events/EventsTabView.swift` — Observe `router.route` for `.event(let id)`, navigate to `EventDetailView`.
- `AppDelegate.swift` — `handleFCMPayload` already delegates to `DeepLinkRouter`, which will now parse `eventId` from the payload. No changes needed if the router handles it.

---

### Step 8: Integration Testing

**Goal:** End-to-end verification with two simulator accounts.

**Test cases:**

1. User A creates event with User B invited — event appears on both users' event lists
2. User B RSVPs "accepted" — RSVP updates in real-time on User A's detail view
3. User B changes RSVP to "declined" — updates in real-time
4. User A edits event (change date/location) — updates reflected on User B's view
5. User A cancels event — status shows "cancelled" on both users' views
6. User A creates event with "Create group chat" enabled — conversation created, "Open Chat" button visible, chat thread works
7. User A creates event without group chat — "Open Chat" button hidden
8. Deep link: tap event notification → app opens to correct event detail
9. User A taps "+" to create event, User B is not a contact → User B does not appear in invitee picker (contacts only)
10. User A deletes event — removed from both users' lists
11. Past events appear in "Past" section, upcoming in "Upcoming"
12. Cleanup function: events older than 7 days are deleted (test via emulator)

**Firestore verification:**
- `events/{id}` doc has correct fields, `invitees` array, `rsvps` map
- `rsvps` map updates when invitee RSVPs
- `conversationId` populated when group chat created
- `status` changes to `cancelled` on cancel
- Cloud Functions fire correctly (check emulator logs)

---

## Deliverables Checklist

- [ ] `Event` model with `RSVPStatus` and `EventStatus` enums
- [ ] `EventManager` service (CRUD, RSVP, real-time listener)
- [ ] Firestore security rule updated for invitee RSVP
- [ ] `onEventCreated` Cloud Function (FCM push to invitees)
- [ ] `onEventUpdated` Cloud Function (FCM push on changes/RSVPs)
- [ ] `cleanupPastEvents` Cloud Function (daily cleanup)
- [ ] Events tab (4th tab) in TabView
- [ ] Events list with upcoming/past sections
- [ ] Create event form with invitee picker and optional group chat
- [ ] Edit event form (creator only)
- [ ] Event detail with RSVP buttons, attendee list, "Open Chat"
- [ ] Deep link router extended for events
- [ ] Event notification tap → navigates to event detail
- [ ] Integration tested with two accounts

---

## Files Summary

### New Files (~8)

| File | Step | Purpose |
|------|------|---------|
| `Models/Event.swift` | 1 | Event struct, RSVPStatus enum, EventStatus enum |
| `Services/EventManager.swift` | 2 | Events CRUD, RSVP, real-time listener |
| `Views/Events/EventsTabView.swift` | 4 | Tab shell with NavigationStack |
| `Views/Events/EventsListView.swift` | 4 | Upcoming/past event list |
| `Views/Events/CreateEventView.swift` | 5 | Create form with invitee picker |
| `Views/Events/EditEventView.swift` | 5 | Edit form (creator only) |
| `Views/Events/EventDetailView.swift` | 6 | Detail view with RSVP + attendees + chat |
| `Sprints/Sprint 3 - Event Scheduling/BREAKDOWN.md` | — | This document |

### Modified Files (~5)

| File | Step | Change |
|------|------|--------|
| `firebase/rules/firestore.rules` | 2 | Update event `allow update` for invitee RSVP |
| `LetsDoIt/firebase/functions/index.js` | 3 | Add `onEventCreated`, `onEventUpdated`, possibly `cleanupPastEvents` |
| `Views/HomeView.swift` | 4, 7 | Add Events tab (tag 3), handle `.event` deep link route |
| `Services/DeepLinkRouter.swift` | 7 | Add `case event(String)`, parse `eventId` from FCM |
| `AppDelegate.swift` | 7 | May need minor changes if FCM payload parsing needs updating |

---

## Key Decisions

1. **Top-level `events` collection** — Events are shared resources (multiple invitees), not user-scoped. Invitee-based read rules restrict access to participants only.

2. **RSVPs as map on event doc** — Small group sizes (contacts list) make a map efficient. Avoids a subcollection and extra reads. Real-time listener on the event doc automatically picks up RSVP changes.

3. **Optional conversation linkage** — `conversationId` is nullable. If the user creates a group chat from the event form, `MessagingManager.createGroup()` is called and the ID stored. The "Open Chat" button only appears when non-nil. This keeps Sprint 1 dependency soft.

4. **Security rule expansion for RSVPs** — Rather than routing RSVPs through a Cloud Function (adds latency), the Firestore rule is expanded to allow invitees to update only the `rsvps` field. This gives instant RSVP feedback in the UI.

5. **Cloud Functions in messaging project** — Event triggers are Firestore document triggers (v1 API), same as `onMessageCreated`. Keeping all Firestore trigger functions together in one project simplifies deployment.

6. **Fourth tab, not nested** — Events get their own top-level tab rather than being nested under Activity. This matches the PLAN.md spec and keeps the tab bar discoverable.

7. **Reuse MultiContactPickerView** — Third sprint reusing the same picker. No changes needed.

---

## Implementation Order

Recommended: **Phase 1 → Phase 2 → Phase 3**, steps sequential within each phase.

Phase 1 builds the data layer and Cloud Functions. Phase 2 builds all the UI. Phase 3 wires up deep linking and runs integration testing.

Within Phase 1: Step 1 (model) before Step 2 (service that uses it + rule change) before Step 3 (Cloud Functions that trigger on event docs).

Within Phase 2: Step 4 (tab + list) before Step 5 (create/edit forms the list navigates to) before Step 6 (detail view that create/list navigate to).

Within Phase 3: Step 7 (deep linking) before Step 8 (integration testing that verifies everything).

---

## Workflow Format — ALL Implementation Sessions Must Follow This

Every implementation task must follow this exact format:

1. **Plan** — Read the step's requirements and context files. Present a concrete implementation plan (specific files to create/modify, API design, key decisions) before writing any code.
2. **Present & confirm** — Wait for explicit user approval before implementing.
3. **Implement** — Create/modify files. Follow existing code conventions from the project.
4. **Verify** — For Swift changes: run `xcodebuild -scheme LetsDoIt -destination 'platform=iOS Simulator,name=iPhone 17' build` and confirm BUILD SUCCEEDED. For Cloud Function changes: verify syntax with `node --check` against the correct functions project. Fix any errors.
5. **Document** — Create a step implementation log in `Sprints/Sprint 3 - Event Scheduling/` named `Phase X - Step Y - [Name].md`, matching the format of Sprint 1's logs. Update this breakdown file to mark the step complete.
6. **Commit handoff** — Ask the user to commit locally and provide the list of changed files. Then give the user a ready-to-paste prompt for a fresh session to handle the NEXT step as defined in the BREAKDOWN.md. The handoff prompt MUST:
   - Reference the BREAKDOWN.md file explicitly and instruct the next session to read it to determine what step comes next
   - Include the project path (/Users/adamgrow/hermGameTest/LetsDoIt)
   - List which context files to re-read
   - Name the specific next step (Phase X, Step Y, name) by looking at the BREAKDOWN.md step sequence
   - Include a reminder of this workflow format
   - When the current phase's last step is complete, the next prompt must target the NEXT PHASE's first step (e.g., Phase 1 Step 3 → Phase 2 Step 4, NOT "Phase 1 Step 4")

IMPORTANT: The commit handoff prompt must be given as plain text only. Do NOT use markdown formatting (no code fences, no bold, no backticks, no lists) in the prompt block. It must be raw plain text that the user can copy and paste directly into a new chat.

CRITICAL: Do NOT increment step numbers blindly. Always consult the BREAKDOWN.md to determine what step comes next. The phases and steps are:
- Phase 1: Step 1, Step 2, Step 3
- Phase 2: Step 4, Step 5, Step 6
- Phase 3: Step 7, Step 8

After Step 3, the next step is Step 4 (Phase 2). After Step 6, the next step is Step 7 (Phase 3). After Step 8, the sprint is complete.

### Implementation Log Format (reference)

Each implementation log must match the structure of Sprint 1's Phase 1 logs. See these files for the exact format:
- `Sprints/Sprint 1 - Messaging/Phase 1 - Step 3 - Data Models.md`
- `Sprints/Sprint 1 - Messaging/Phase 1 - Step 4 - MessagingManager.md`

Required sections in each log:
- Title, date, build status badge
- "What Was Done" — tables of new/modified files
- Detailed section per file/service with property/method tables
- "Architecture Decisions" — numbered list of design rationale
- "Build Verification" — the exact build/check command and result

### Context Files for Each Step

Steps should read these files before planning:

| Step | Must Read |
|------|-----------|
| 1 | `Models/Conversation.swift` (model pattern reference), `Models/CustomActivity.swift` (model pattern reference), `Sprints/Sprint 3 - Event Scheduling/BREAKDOWN.md` |
| 2 | `Services/MessagingManager.swift` (singleton + listener pattern), `Services/EventManager.swift` (from Step 1 — model it uses), `firebase/rules/firestore.rules` (current event rules to update), `Services/ContactManager.swift` (for name resolution) |
| 3 | `LetsDoIt/firebase/functions/index.js` (messaging functions project — where to add triggers), `LetsDoIt/firebase/functions/package.json` (verify v1/v2 API availability) |
| 4 | `Views/HomeView.swift` (TabView structure — adding 4th tab), `Views/MessagesTabView.swift` (tab shell pattern reference), `Services/EventManager.swift` (from Step 2) |
| 5 | `Views/Messaging/MultiContactPickerView.swift` (reuse for invitee picker), `Views/Activities/CreateCustomActivityView.swift` (form pattern reference), `Services/EventManager.swift` (from Step 2), `Services/MessagingManager.swift` (for optional group chat creation) |
| 6 | `Services/EventManager.swift` (RSVP method), `Services/ContactManager.swift` (name resolution), `Services/DeepLinkRouter.swift` (for "Open Chat" routing), `Views/Activities/MatchDetailView.swift` (detail view pattern reference) |
| 7 | `Services/DeepLinkRouter.swift` (extend with event route), `Views/HomeView.swift` (add event notification handling), `Views/Events/EventsTabView.swift` (from Step 4 — observe route), `AppDelegate.swift` (notification handling) |
| 8 | All files from Steps 1–7, `Sprints/Sprint 1 - Messaging/Phase 4 - Step 13 - Integration Testing.md` (test log format reference), `Sprints/Sprint 2 - Customizable Activities/Phase 4 - Step 9 - Integration Testing.md` (test log format reference) |
