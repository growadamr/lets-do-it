# Sprint 4: Scheduled Activities — Implementation Breakdown

**Estimated duration:** 1.5–2 weeks  
**Complexity:** MEDIUM  
**Key risk:** Server-side recurrence calculation, collection group index, schedule-to-selection pipeline

---

## Overview

Sprint 4 adds the ability to schedule activities that auto-activate at future times:
- **One-time schedules** — fire once at a specific time, then auto-delete
- **Recurring schedules** — daily, weekly, or custom days of the week
- **Cloud Function processing** — runs every 5 minutes, creates normal selection docs for due schedules. The existing `checkForMatches` function picks them up with zero changes.
- **Enable/disable toggle** — pause a schedule without deleting it
- **Per-contact scheduling** — each schedule targets a specific contact + activity pair

The key design insight: **activation = normal selection creation**. The Cloud Function creates the exact same `selections` docs that `ContactManager.toggleSelection()` creates. This means the existing match system (`checkForMatches`, `sendPendingNotifications`, `MatchManager`) all work automatically.

### Firestore Schema

```
users/{userId}/scheduledActivities/{scheduleId}
  activityId: String              // catalog ID or custom_* ID
  targetContactUid: String        // which contact this schedule is for
  scheduledAt: Timestamp          // next activation time
  recurrence: {                   // null for one-time
    type: "daily" | "weekly" | "custom"
    daysOfWeek: [0-6]?            // Sunday=0, for "custom" type
  }
  enabled: Bool                   // pause without deleting
  createdAt: Timestamp
  lastActivatedAt: Timestamp?     // set each time the function fires
```

### Security Rules (Already Deployed — Sprint 1, Phase 1, Step 2)

`scheduledActivities` rules were pre-authored during Sprint 1's Firebase setup:
```
match /scheduledActivities/{scheduleId} {
  allow read, write: if isOwner(userId);
}
```
Owner-only read/write. No rule changes needed.

### Cloud Function

**`processScheduledActivities`** goes in the **match functions project** (`/hermGameTest/functions/index.js`, v2 API with `onSchedule`). This is where `checkForMatches` lives — the schedule processor creates selection docs that `checkForMatches` then picks up on its next 5-minute scan.

**Logic:**
1. Collection group query: all `scheduledActivities` where `enabled == true` and `scheduledAt <= now`
2. For each due schedule:
   - Create a selection doc in `users/{userId}/selections/` with the same schema as `ContactManager.toggleSelection()`: `{ userId, targetUserId, itemId, createdAt, expiresAt (1 hour), matched: false }`
   - Update `lastActivatedAt` to now
   - For recurring: calculate next `scheduledAt` based on recurrence rules, update the doc
   - For one-time: delete the schedule doc
3. **Requires**: Firestore collection group index on `scheduledActivities` (`enabled` ASC, `scheduledAt` ASC)

### Selection Doc Schema (Reference — Created by Cloud Function)

The Cloud Function must create selection docs matching this exact schema (from `ContactManager.toggleSelection()`):
```
users/{userId}/selections/{autoId}
  userId: String
  targetUserId: String
  itemId: String
  createdAt: Timestamp
  expiresAt: Timestamp       // createdAt + 1 hour (60 * 60 * 1000 ms)
  matched: false
```

### Existing Assets to Reuse

- `ActivityDisplayable` protocol + `ActivityManager.shared` — for resolving activity details in the schedule list and picker
- `ContactManager.shared` — for contact picker and name resolution
- `AppConfig.selectionExpiryDuration` — 1 hour, use the same value in the Cloud Function

### Patterns Established in Sprints 1–3 (Must Follow)

1. **Pure Swift models** — `ScheduledActivity` uses `Date` not `Timestamp`, no `FirebaseFirestore` import.

2. **Singleton service pattern** — `@MainActor class ScheduleManager: ObservableObject` with `static let shared`, `@Published` arrays, `ListenerRegistration`.

3. **Error types in service file** — `ScheduleManagerError` enum at file bottom with `LocalizedError` conformance.

4. **Activity tab integration** — Sprint 2 changed the Activity tab landing to `MatchesLandingView`. Sprint 4 adds schedule access from the `contactSelectedView` (when matching with a contact, you can schedule activities for that contact).

5. **Cloud Function in match project** — v2 API (`onSchedule`), same project as `checkForMatches`. Uses `getFirestore`, `Timestamp`, `FieldValue` from `firebase-admin`.

### Sprint 2 Soft Dependency

Sprint 2 added custom activities with `custom_*` IDs. The schedule picker should show the effective activity list (catalog + custom activities visible to the target contact) so users can schedule custom activities too. Use `ActivityManager.getEffectiveActivities(for:)`.

---

## Phase 1: Data Layer & Service (Steps 1–3)

### Step 1: ScheduledActivity Model & RecurrenceRule ✅ COMPLETE

**Goal:** Create the ScheduledActivity model and recurrence types.

**Implemented:** April 6, 2026. BUILD SUCCEEDED.
**Log:** `Phase 1 - Step 1 - ScheduledActivity Model and RecurrenceRule.md`

---

### Step 2: ScheduleManager Service

**Goal:** Central service for schedule CRUD and real-time listener.

**New files:**
- `Services/ScheduleManager.swift` — `@MainActor class ScheduleManager: ObservableObject` (singleton `.shared`)

**Follows established singleton pattern:**
- `static let shared = ScheduleManager()`
- `@Published var schedules: [ScheduledActivity] = []` — real-time listener, sorted by `scheduledAt` ascending
- `private let db = Firestore.firestore()`
- `private var listener: ListenerRegistration?`
- `Date` ↔ `Timestamp` conversion in read/write methods

**Responsibilities:**

1. **CRUD**
   - `createSchedule(activityId:targetContactUid:scheduledAt:recurrence:)` — creates doc with `enabled: true`
   - `updateSchedule(_:)` — updates fields (merge)
   - `deleteSchedule(id:)` — deletes doc
   - `toggleEnabled(id:enabled:)` — updates `enabled` field only

2. **Real-time listener**
   - `startListening()` — listens to `users/{uid}/scheduledActivities`, sorted by `scheduledAt` ascending
   - `stopListening()` — removes listener, clears array

3. **Helpers**
   - `schedulesForContact(_ contactUid: String) -> [ScheduledActivity]` — filters by `targetContactUid`
   - `nextActivationDescription(_ schedule: ScheduledActivity) -> String` — human-readable "Tomorrow at 3:00 PM", "Every Mon, Wed, Fri at 8:00 AM", etc.

---

### Step 3: processScheduledActivities Cloud Function

**Goal:** Server-side function that creates selection docs for due schedules.

**Modified files:**
- `/hermGameTest/functions/index.js` — add `processScheduledActivities`

**Important:** This is the **match functions project** (v2 API with `onSchedule`), the same project as `checkForMatches`. NOT the messaging functions project.

**Function spec:**
- Schedule: `every 5 minutes` (matches `checkForMatches` cadence)
- Collection group query: `scheduledActivities` where `enabled == true` and `scheduledAt <= now`
- For each due schedule:
  1. Create selection doc in `users/{userId}/selections/` with: `userId`, `targetUserId` (from `targetContactUid`), `itemId` (from `activityId`), `createdAt: Timestamp.now()`, `expiresAt: now + 60*60*1000ms`, `matched: false`
  2. Set `lastActivatedAt` to now
  3. If `recurrence` is non-null: calculate next `scheduledAt` and update the doc
  4. If `recurrence` is null (one-time): delete the schedule doc
- **Recurrence calculation** (server-side to avoid clock skew):
  - `daily`: add 24 hours
  - `weekly`: add 7 days
  - `custom` with `daysOfWeek`: find the next matching day of the week from now

**Requires:** Firestore collection group index on `scheduledActivities`:
- `enabled` (ASC) + `scheduledAt` (ASC)
- Add to `firebase/firestore.indexes.json` (or the match project's indexes config)

**Also add to `AppConfig.swift`:**
- `static let scheduleProcessInterval: TimeInterval = 5 * 60` — documented reference for the function's cadence

---

## Phase 2: Scheduling UI (Steps 4–6)

### Step 4: Scheduled Activities List View

**Goal:** View showing all of the user's schedules with status and controls.

**New files:**
- `Views/Scheduling/ScheduledActivitiesListView.swift`

**UI layout:**
- List of all schedules, grouped by contact (using `ContactManager` for names)
- Each row shows: activity emoji + label (resolved via `ActivityManager`), contact name, next activation time (formatted), recurrence description, enabled/disabled toggle
- Swipe-to-delete
- Empty state: "No scheduled activities yet"
- Tap to edit (navigates to edit view — Step 5)

---

### Step 5: Create & Edit Schedule Views

**Goal:** Forms for creating and editing scheduled activities.

**New files:**
- `Views/Scheduling/CreateScheduleView.swift` — form with:
  - Contact picker (single contact — not multi-select, since each schedule targets one contact)
  - Activity picker showing the effective activity list for the selected contact (uses `ActivityManager.getEffectiveActivities(for:)`)
  - Date/time picker for `scheduledAt`
  - Recurrence picker (one-time, daily, weekly, custom days)
  - On save, calls `ScheduleManager.createSchedule()`
- `Views/Scheduling/EditScheduleView.swift` — same form pre-filled, save calls `ScheduleManager.updateSchedule()`. Delete button.
- `Views/Scheduling/RecurrencePickerView.swift` — picker for recurrence type + day-of-week selection for "custom". Days shown as tappable circles (S M T W T F S).

**Validation:**
- Contact: required
- Activity: required
- ScheduledAt: required, must be in the future (for creation)
- Recurrence custom days: if custom type selected, at least one day required

---

### Step 6: Integrate into Activity Tab

**Goal:** Wire schedule access into the Activity tab and activity list.

**Modified files:**
- `Views/ActivityTabView.swift` — In `contactSelectedView`, add a toolbar button or navigation link to `ScheduledActivitiesListView` (filtered to the selected contact). Also add a "+" button or menu to create a new schedule for this contact.
- `Views/ActivityListView.swift` — Add a context menu or long-press action on each activity row: "Schedule This Activity" → presents `CreateScheduleView` pre-filled with the activity and current contact.

**Navigation pattern:** Use `.sheet` for create/edit forms (consistent with Sprint 2 settings and Sprint 3 event creation). Use `NavigationLink` or `.navigationDestination` for the schedules list (it's a drill-down, not a modal).

---

## Phase 3: Testing & Polish (Step 7)

### Step 7: Integration Testing

**Goal:** End-to-end verification with two simulator accounts.

**Test cases:**

1. Create one-time schedule for Contact B, activity "Walk" at a future time — schedule appears in list with correct details
2. Wait for `processScheduledActivities` to fire (or trigger manually via emulator) — selection doc created in Firestore
3. Verify the selection doc schema matches `ContactManager.toggleSelection()` output exactly
4. Verify `checkForMatches` picks up the scheduled selection and matches if Contact B also selected "Walk"
5. Verify one-time schedule is deleted after activation
6. Create recurring daily schedule — verify `scheduledAt` advances by 24 hours after activation
7. Create recurring weekly schedule — verify `scheduledAt` advances by 7 days
8. Create recurring custom (Mon, Wed, Fri) schedule — verify next `scheduledAt` is correct day
9. Toggle schedule disabled — verify it's skipped by the Cloud Function
10. Toggle back enabled — verify it fires on next cycle
11. Edit schedule (change time, recurrence) — verify updates saved correctly
12. Delete schedule — removed from list and Firestore
13. Schedule a custom activity (`custom_*` ID) — verify it works end-to-end through matching
14. "Schedule This Activity" from activity list context menu — verify CreateScheduleView pre-fills correctly

**Firestore verification:**
- `scheduledActivities` docs have correct fields and types
- Selection docs created by Cloud Function match `ContactManager` schema
- `lastActivatedAt` updates on activation
- `scheduledAt` recalculates correctly for recurring
- Collection group index exists and is active

**Cloud Functions emulator:**
- `processScheduledActivities` runs on 5-minute schedule
- Creates selection docs correctly
- Handles one-time deletion and recurring advancement
- Logs activation events

---

## Deliverables Checklist

- [ ] `ScheduledActivity` model with `RecurrenceRule` and `RecurrenceType`
- [ ] `ScheduleManager` service (CRUD, toggle, real-time listener)
- [ ] `processScheduledActivities` Cloud Function (creates selections, handles recurrence)
- [ ] Collection group index for `scheduledActivities`
- [ ] Scheduled activities list view with enable/disable toggle
- [ ] Create schedule form with contact picker, activity picker, date/time, recurrence
- [ ] Edit schedule form with delete
- [ ] Recurrence picker (daily, weekly, custom days)
- [ ] "Schedule This Activity" action on activity list rows
- [ ] Schedule access from Activity tab contact view
- [ ] Firestore security rules verified (already deployed)
- [ ] Integration tested with two accounts

---

## Files Summary

### New Files (~6)

| File | Step | Purpose |
|------|------|---------|
| `Models/ScheduledActivity.swift` | 1 | ScheduledActivity struct, RecurrenceRule, RecurrenceType |
| `Services/ScheduleManager.swift` | 2 | Schedule CRUD, real-time listener |
| `Views/Scheduling/ScheduledActivitiesListView.swift` | 4 | Schedule list with toggle, swipe-to-delete |
| `Views/Scheduling/CreateScheduleView.swift` | 5 | Create form with pickers |
| `Views/Scheduling/EditScheduleView.swift` | 5 | Edit form with delete |
| `Views/Scheduling/RecurrencePickerView.swift` | 5 | Recurrence type + day selection |

### Modified Files (~4)

| File | Step | Change |
|------|------|--------|
| `/hermGameTest/functions/index.js` | 3 | Add `processScheduledActivities` function |
| `Models/AppConfig.swift` | 3 | Add `scheduleProcessInterval` reference constant |
| `Views/ActivityTabView.swift` | 6 | Add schedule access in contact-selected view |
| `Views/ActivityListView.swift` | 6 | Add "Schedule This Activity" context menu on rows |

---

## Key Decisions

1. **Activation = selection creation** — The Cloud Function creates the exact same `selections` docs as the client. Zero changes to `checkForMatches`, `sendPendingNotifications`, `MatchManager`, or any match UI. This is the highest-leverage design choice in the sprint.

2. **Recurrence calculated server-side** — Avoids clock skew between client and server. The function always uses `Timestamp.now()` and computes the next activation time relative to server time.

3. **`scheduledActivities` nested under users** — Private to the user. Contacts don't see your schedules. Owner-only read/write rules.

4. **Collection group query** — `processScheduledActivities` queries across ALL users' `scheduledActivities` subcollections in a single query. Requires a collection group index but is far more efficient than iterating users.

5. **Match project for the function** — `processScheduledActivities` creates selection docs that `checkForMatches` scans. Keeping them in the same project ensures consistent Firestore access and deployment.

6. **Effective activity list in picker** — `CreateScheduleView` uses `ActivityManager.getEffectiveActivities(for:)` so users can schedule both catalog and custom activities. Custom activities respect the same `visibleTo` rules.

7. **One-time auto-delete** — One-time schedules are deleted after activation to keep the collection clean. The selection doc persists independently (it has its own expiry and cleanup).

---

## Implementation Order

Recommended: **Phase 1 → Phase 2 → Phase 3**, steps sequential within each phase.

Phase 1 builds the data layer and Cloud Function. Phase 2 builds all the UI. Phase 3 runs integration testing.

Within Phase 1: Step 1 (model) before Step 2 (service that uses it) before Step 3 (Cloud Function that processes schedules).

Within Phase 2: Step 4 (list view) before Step 5 (create/edit/recurrence forms the list navigates to) before Step 6 (wiring into Activity tab and activity list).

---

## Workflow Format — ALL Implementation Sessions Must Follow This

Every implementation task must follow this exact format:

1. **Plan** — Read the step's requirements and context files. Present a concrete implementation plan (specific files to create/modify, API design, key decisions) before writing any code.
2. **Present & confirm** — Wait for explicit user approval before implementing.
3. **Implement** — Create/modify files. Follow existing code conventions from the project.
4. **Verify** — For Swift changes: run `xcodebuild -scheme LetsDoIt -destination 'platform=iOS Simulator,name=iPhone 17' build` and confirm BUILD SUCCEEDED. For Cloud Function changes: verify syntax with `node --check` against the correct functions project. Fix any errors.
5. **Document** — Create a step implementation log in `Sprints/Sprint 4 - Scheduled Activities/` named `Phase X - Step Y - [Name].md`, matching the format of Sprint 1's logs. Update this breakdown file to mark the step complete.
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
- Phase 3: Step 7

After Step 3, the next step is Step 4 (Phase 2). After Step 6, the next step is Step 7 (Phase 3). After Step 7, Sprint 4 is complete.

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
| 1 | `Models/Event.swift` (model pattern reference from Sprint 3), `Models/CustomActivity.swift` (model pattern reference from Sprint 2), `Sprints/Sprint 4 - Scheduled Activities/BREAKDOWN.md` |
| 2 | `Services/EventManager.swift` (singleton + listener pattern from Sprint 3), `Services/ActivityManager.swift` (for activity resolution), `Services/ContactManager.swift` (for contact resolution + selection schema reference — see `toggleSelection` method), `Models/ScheduledActivity.swift` (from Step 1) |
| 3 | `/hermGameTest/functions/index.js` (match functions project — where to add the function), `Services/ContactManager.swift` lines 272-310 (selection doc schema reference — the Cloud Function must create identical docs), `Models/AppConfig.swift` (expiry duration reference) |
| 4 | `Services/ScheduleManager.swift` (from Step 2), `Services/ActivityManager.swift` (for activity detail resolution), `Services/ContactManager.swift` (for contact name resolution), `Views/Events/EventsListView.swift` (list view pattern reference from Sprint 3) |
| 5 | `Views/Events/CreateEventView.swift` (form pattern reference from Sprint 3), `Views/Messaging/MultiContactPickerView.swift` (available but Sprint 4 needs single-contact selection), `Services/ActivityManager.swift` (`getEffectiveActivities` for activity picker), `Services/ScheduleManager.swift` (from Step 2) |
| 6 | `Views/ActivityTabView.swift` (where to integrate — `contactSelectedView` toolbar), `Views/ActivityListView.swift` (where to add context menu), `Views/Scheduling/ScheduledActivitiesListView.swift` (from Step 4), `Views/Scheduling/CreateScheduleView.swift` (from Step 5) |
| 7 | All files from Steps 1–6, `Sprints/Sprint 3 - Event Scheduling/Phase 3 - Step 8 - Integration Testing.md` (test log format reference) |
