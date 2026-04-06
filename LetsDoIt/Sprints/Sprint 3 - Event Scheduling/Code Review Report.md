# Sprint 3: Event Scheduling — Code Review Report

**Date:** 2026-04-06
**Reviewer:** Qwen Code
**Scope:** All Sprint 3 implementation code (Steps 1–8)
**Result:** Sprint 3 has 4 issues to address (1 medium, 2 low, 1 info)

---

## 1. Deliverables Checklist Verification

| # | Deliverable | Status | Notes |
|---|------------|--------|-------|
| 1 | `Event` model with `RSVPStatus` and `EventStatus` enums | **Verified** | All fields present, correct types, pure Swift, Codable/Identifiable/Hashable |
| 2 | `EventManager` service (CRUD, RSVP, real-time listener) | **Verified** | All responsibilities implemented |
| 3 | Firestore security rule updated for invitee RSVP | **Verified** | Rule correctly allows creator full updates + invitee-only `rsvps` field updates |
| 4 | `onEventCreated` Cloud Function (FCM push to invitees) | **Verified** | Correct trigger, excludes creator, builds FCM payload with `eventId` |
| 5 | `onEventUpdated` Cloud Function (FCM push on changes/RSVPs) | **Verified** | RSVP changes → creator; detail changes → all invitees; both include `eventId` in data |
| 6 | `cleanupPastEvents` Cloud Function (daily cleanup) | **Verified** | Scheduled daily at 3 AM UTC, queries events > 7 days past with `status == "active"`, batch deletes |
| 7 | Events tab (4th tab) in TabView | **Verified** | Tag 3, `EventsTabView` in `HomeView` |
| 8 | Events list with upcoming/past sections | **Verified** | Two sections, correct sort orders, empty state, swipe-to-delete |
| 9 | Create event form with invitee picker and optional group chat | **Verified** | All fields, validation, `MultiContactPickerView` reuse, group chat toggle |
| 10 | Edit event form (creator only) | **Verified** | Pre-filled form, save, cancel event button, danger zone |
| 11 | Event detail with RSVP buttons, attendee list, "Open Chat" | **Verified** | All UI elements present, conditional chat/edit buttons, creator label |
| 12 | Deep link router extended for events | **Verified** | `.event(String)` route, Codable, `handleFCMPayload` parses `eventId`, `.openEvent` notification |
| 13 | Event notification tap → navigates to event detail | **Verified** | `HomeView` switches to tab 3, `EventsTabView` observes `router.route`, sets `selectedEventId` |
| 14 | Integration tested with two accounts | **Verified** | Test log complete, 23/28 passed, 5 deferred (FCM push-related) |

---

## 2. Model Correctness (`Event.swift`)

**Verified — no issues found.**

- **Pure Swift**: No `FirebaseFirestore` import. ✅
- **Codable conformance**: `Event`, `RSVPStatus`, `EventStatus` all `Codable`. ✅
- **Identifiable**: `id: String` with `UUID().uuidString` default. ✅
- **Hashable**: Custom `hash(into:)` combines only `id`; `==` compares only `id`. ✅
- **All fields match spec**:
  - `id`, `title`, `description?`, `location?`, `dateTime: Date`, `createdBy: String`, `createdAt?`, `updatedAt?`, `invitees: [String]`, `rsvps: [String: RSVPStatus]`, `conversationId?`, `status: EventStatus` ✅
- **`RSVPStatus`**: `.accepted`, `.declined`, `.maybe` — String-backed, `CaseIterable`, with `displayLabel` and `colorName` computed properties. ✅
- **`EventStatus`**: `.active`, `.cancelled` — String-backed, `CaseIterable`. ✅
- **CodingKeys**: Explicit enum present, matches all property names. ✅

---

## 3. Service Correctness (`EventManager.swift`)

**Verified — minor concern noted, but no blocking issues.**

- **Singleton pattern**: `static let shared`, `@MainActor`, `ObservableObject`. ✅
- **`@Published` arrays**: `events` (upcoming, sorted ascending), `pastEvents` (past, sorted descending). ✅
- **CRUD**:
  - `createEvent`: Creates doc, auto-adds creator to invitees, auto-accepts creator RSVP, optionally creates group chat via `MessagingManager.createGroup()`, uses `FieldValue.serverTimestamp()`. ✅
  - `updateEvent`: Checks `createdBy == uid`, updates all mutable fields + `updatedAt`. ✅
  - `cancelEvent`: Verifies creator, sets `status = .cancelled`. ✅
  - `deleteEvent`: Verifies creator, deletes doc. ✅
- **RSVP**: `rsvp(eventId:status:)` verifies invitee membership, uses dot-notation `rsvps.{uid}`. ✅
- **Real-time listener**: `startListening()` uses `arrayContains: uid` query, splits upcoming/past with `Date()` comparison, sorts correctly. ✅
- **`stopListening()`**: Removes listener, clears both arrays. ✅
- **`isCreator(_ event:)`**: Helper present. ✅
- **`inviteeName(for:in:)`**: Resolves from `ContactManager`, falls back to "Unknown". ✅
- **`Date` ↔ `Timestamp` conversion**: Service handles conversion; model uses `Date`. ✅
- **Error types**: `EventManagerError` with `notAuthenticated`, `eventNotFound`, `notCreator`, `notInvitee`, `invalidEventData` — all with `LocalizedError` conformance. ✅

**Concern (non-blocking):**
- **`@ObservedObject` in `CreateEventView` and `EditEventView`**: Both views use `@ObservedObject private var eventManager = EventManager.shared`. Since `EventManager.shared` is a singleton that outlives these views, this works in practice, but the conventionally correct property wrapper for an externally-owned observable object is `@StateObject` (for the owner) or simply accessing it directly without a wrapper. This is a **pattern consistency concern** — `MessagingManager` is referenced directly (no wrapper) in some places, and `@StateObject` is used in `EventsTabView`. Not a functional bug but a stylistic inconsistency.

---

## 4. Cloud Functions (`firebase/functions/index.js`)

**Verified — all 3 functions present and correct.**

- **`onEventCreated`**:
  - Trigger: `events/{eventId}` `.onCreate` ✅
  - Excludes creator from recipients ✅
  - Looks up FCM tokens from `users/{uid}.fcmToken` ✅
  - Builds notification with title, date, location preview ✅
  - Data payload: `{ eventId }` ✅
  - Uses `admin.messaging().sendEachForMulticast()` ✅

- **`onEventUpdated`**:
  - Trigger: `events/{eventId}` `.onUpdate` ✅
  - RSVP change detection: compares `before.rsvps` vs `after.rsvps`, finds changed UIDs ✅
  - RSVP notification: personalized push to creator with verb ("accepted/declined/said maybe to your event") ✅
  - Detail change detection: `dateTime`, `location`, `status` — with `isEqual()` for Timestamp comparison ✅
  - Detail notification: contextual message to all invitees ✅
  - Data payload: `{ eventId }` for both types ✅

- **`cleanupPastEvents`**:
  - Schedule: `"0 3 * * *"` UTC (daily at 3 AM) ✅
  - Query: `dateTime < sevenDaysAgo` AND `status == "active"` ✅
  - Batch deletes all matching documents ✅
  - Throws on failure for retry ✅

---

## 5. Firestore Security Rules

**Verified — rule is correct.**

```
allow update: if isAuthenticated() &&
  (request.auth.uid == resource.data.createdBy ||
   (request.auth.uid in resource.data.invitees &&
    request.resource.data.diff(resource.data).affectedKeys().hasOnly(['rsvps'])));
```

- Creator can update all fields. ✅
- Invitees can ONLY update the `rsvps` field. ✅
- `hasOnly(['rsvps'])` ensures no other fields can be modified by invitees. ✅

---

## 6. UI Completeness

### `EventsListView.swift`
**Verified.**
- Two sections: "Upcoming" (from `eventManager.events`) and "Past" (from `eventManager.pastEvents`). ✅
- Sort orders: upcoming ascending (soonest first), past descending (most recent first) — done in `EventManager`. ✅
- Empty state: `ContentUnavailableView("No Events Yet", ...)`. ✅
- Swipe-to-delete: `.onDelete(perform: deleteEvents)` on upcoming section, gated by `isCreator`. ✅
- Confirmation dialog before delete. ✅
- RSVP summary: counts accepted/declined/maybe, joined with "·". ✅
- Event row: title + cancelled badge, date, location, RSVP summary. ✅

**Concern (non-blocking):**
- The `.onDelete` modifier only applies to the "Upcoming" section's `ForEach`. Past events cannot be swipe-deleted from the list view. This is likely intentional (past events are archival), but the spec does not explicitly exclude past events from deletion. The `EventManager.deleteEvent` method would still work if called programmatically.

### `EventsTabView.swift`
**Verified.**
- `NavigationStack` with `NavigationPath`. ✅
- Toolbar "+" button with `placement: .topBarTrailing`. ✅
- Create event sheet: `$showCreateEvent`. ✅
- Edit event sheet: `eventToEdit` with `.sheet(item:)`. ✅
- Deep link observation: `onChange(of: router.route)` for `.event(let id)`. ✅
- `findEvent(by:)` searches both `events` and `pastEvents`. ✅
- `.task { startListening }` and `.onDisappear { stopListening }` at `NavigationStack` level (Bug B2 fix). ✅

### `CreateEventView.swift`
**Verified.**
- All form fields: title, description, location, date/time, invitees, group chat toggle. ✅
- Validation: title 1–100 chars (`trimmedTitle.count <= 100`), future date (`dateTime > Date()`), at least one invitee (`!selectedUids.isEmpty`). ✅
- `MultiContactPickerView` reused via `.sheet`. ✅
- Group chat toggle: defaults to `true`, explanatory text. ✅
- Save calls `EventManager.createEvent()`. ✅
- Cancel/Dismiss buttons in toolbar. ✅

**Concern (non-blocking):**
- `@ObservedObject` used for singleton `EventManager.shared` (see concern in section 3 above).

### `EditEventView.swift`
**Verified.**
- Pre-filled form from `event` properties in `init(event:onUpdate:)`. ✅
- Same fields as create form. ✅
- Save calls `EventManager.updateEvent()` with rebuilt `Event`. ✅
- Cancel event button in "Danger Zone" section with confirmation alert. ✅
- Group chat toggle only shown if `event.conversationId != nil`. ✅
- Invitee management: filters out creator from `selectedUids`, re-adds on save. ✅

**Concern (non-blocking):**
- Same `@ObservedObject` pattern as `CreateEventView`.
- The `init(event:onUpdate:)` uses `Auth.auth().currentUser?.uid` directly to filter invitees. This means if the current user changes between view initialization and save, the invitee list could be inconsistent. In practice this is very unlikely (auth changes would require re-login), but it's a minor coupling risk.

### `EventDetailView.swift`
**Verified.**
- Header: title (via `.navigationTitle`), date/time, location, description. ✅
- Cancelled badge: shown when `event.status == .cancelled`. ✅
- 3 RSVP buttons (Accept/Maybe/Decline) with highlight for current selection. ✅
- Attendee list grouped by status: Accepted, Maybe, Declined, No Response. ✅
- "Open Chat" button: conditional on `conversationId != nil && !isEmpty`. ✅
- "Edit" button: conditional on `isCreator`. ✅
- Creator label: "Created by {name}". ✅
- RSVP error display. ✅
- Edit sheet with `.onDisappear` to handle cancellation/deletion. ✅

**Concern (non-blocking):**
- `EventDetailView` receives `event` as a value parameter and uses `@EnvironmentObject var eventManager`. When the real-time listener updates `eventManager.events`, the `event` parameter is a *stale copy* of the event at navigation time. The view does not re-fetch the event from the manager when the manager's data changes. In practice, this may cause the detail view to not reflect real-time changes (like another invitee's RSVP) unless the view is re-pushed. The attendee list and RSVP display are derived from the `event` parameter, not from `eventManager.events`. **This is the most significant finding in the review** — the detail view could become stale during active RSVP changes.

---

## 7. Deep Linking

**Verified.**

- `DeepLinkRouter`: `.event(String)` case present. ✅
- Codable conformance updated for `event` type in `init(from:)` and `encode(to:)`. ✅
- `handleFCMPayload`: extracts `eventId` from `userInfo["data"]` or top-level, calls `handle(.event(eventId))`. ✅
- `.openEvent` notification name defined. ✅
- `HomeView`: `.onReceive(.openEvent)` switches `selectedTab = 3` and calls `router.handle(.event(eventId))`. ✅
- `HomeView`: `.onChange(of: router.route)` switches to tab 3 for `.event` case. ✅
- `EventsTabView`: `.onChange(of: router.route)` sets `selectedEventId` for `.event(let id)`. ✅

---

## 8. Key Design Decisions

| Decision | Verified |
|----------|----------|
| Top-level `events` collection | ✅ — `db.collection("events")` in EventManager |
| RSVPs as map on event doc (not subcollection) | ✅ — `rsvps: [String: RSVPStatus]` on Event, dot-notation update |
| `conversationId` nullable | ✅ — `String?`, chat button conditional |
| `MultiContactPickerView` reused | ✅ — used in both `CreateEventView` and `EditEventView` |
| Fourth tab in TabView | ✅ — tag 3 in `HomeView` |

---

## 9. Patterns from Sprints 1 & 2

| Pattern | Verified |
|---------|----------|
| Pure Swift models (no FirebaseFirestore in Event.swift) | ✅ |
| Singleton service with `@MainActor` and `@Published` | ✅ — `EventManager` matches `MessagingManager` pattern |
| Error types in service file with `LocalizedError` | ✅ — `EventManagerError` at bottom of file |
| Tab NavigationStack pattern | ✅ — each tab has own `NavigationStack`, modals via `.sheet` |
| Cross-tab via `NotificationCenter` + `DeepLinkRouter` | ✅ — `.openEvent` notification, router observes route |
| `Date` ↔ `Timestamp` conversion in service, not model | ✅ |
| Invitee name resolution via `ContactManager` | ✅ — same pattern as `MessagingManager.fetchDisplayName` |

---

## 10. Integration Test Bug Fixes

### B1: Toolbar placement
**Fix verified.** The `.toolbar` modifier is correctly placed inside the `NavigationStack` content, chained after `.navigationTitle`. The "+" button renders correctly. ✅

### B2: Listener lifecycle
**Fix verified.** `.task { startListening }` and `.onDisappear { stopListening }` moved from `EventsListView` to `NavigationStack` level. Listener survives navigation pushes to detail view. ✅

---

## Issues Summary

| # | Severity | Category | File(s) | Description |
|---|----------|----------|---------|-------------|
| I1 | **Medium** | UI Staleness | `Views/Events/EventDetailView.swift` | `EventDetailView` receives `event` as a value parameter. When the real-time listener in `EventManager` updates, the detail view's `event` property does **not** update — it's a snapshot from navigation time. RSVP changes from other users will not reflect in real-time on the detail view unless the user navigates back and re-enters. The attendee list (`attendeesByStatus`), cancelled badge, and all derived data are computed from this stale `event`. |
| I2 | **Low** | Pattern Consistency | `Views/Events/CreateEventView.swift`, `Views/Events/EditEventView.swift` | `CreateEventView` and `EditEventView` use `@ObservedObject` for the singleton `EventManager.shared`. While functionally correct (the singleton never deallocates), this differs from the established pattern where `EventsTabView` uses `@StateObject` and other views access managers directly. Consistency would favor either removing the wrapper (accessing `EventManager.shared` directly) or using `@StateObject` to match the tab view. |
| I3 | **Low** | Delete Scope | `Views/Events/EventsListView.swift` | Swipe-to-delete (`.onDelete`) is only applied to the "Upcoming" section of `EventsListView`. Past events cannot be deleted via the list UI. The `EventManager.deleteEvent` method works for any event, so this is a UI gap rather than a functional one. |
| I4 | **Info** | Edit View Auth Coupling | `Views/Events/EditEventView.swift` | `EditEventView.init(event:onUpdate:)` captures `Auth.auth().currentUser?.uid` at initialization time to filter invitees. If auth state changes between init and save, the reconstructed `allInvitees` array could be incorrect. Very low risk in practice. |

---

## Final Verdict

**Sprint 3 has 4 issues to address** (1 medium, 2 low, 1 info).

All 14 deliverables in the checklist are present and functional. The model, service, Cloud Functions, security rules, deep linking, and key design decisions all match the spec. Pattern consistency with Sprints 1 & 2 is largely maintained.

**Priority for future fixes:**
1. **I1 (Medium)** — `EventDetailView` staleness: the detail view should observe the `EventManager`'s published events and re-derive its displayed event from the manager's live data, rather than holding a static copy. This ensures real-time RSVP updates appear without requiring navigation.
2. **I2 (Low)** — Standardize the property wrapper for `EventManager.shared` across all views to match the established pattern.
3. **I3 (Low)** — Decide whether past events should be deletable from the list UI. If yes, add `.onDelete` to the Past section's `ForEach`.
4. **I4 (Info)** — Defer auth state capture to save time rather than init time in `EditEventView`.
