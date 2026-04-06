# Phase 3, Step 7: Integration Testing — Implementation Log

**Date:** 2026-04-06
**Status:** ⏳ In Progress

---

## What Was Done

### New Files Created

| File | Purpose |
|------|---------|
| `Sprints/Sprint 4 - Scheduled Activities/Phase 3 - Step 7 - Integration Testing.md` | This implementation log — structured test plan with pass/fail tracking |

### Files Modified (Bugs Fixed During Testing)

| File | Bug | Change |
|------|-----|--------|
| `Views/Scheduling/ScheduledActivitiesListView.swift` | Missing "+" button to create schedules | Added toolbar "+" button + `showingCreateSchedule` state + `.sheet` presenting `CreateScheduleView` with pre-selected contact |
| `Views/Scheduling/CreateScheduleView.swift` | Activity picker showed no items (Picker rendering bug with existential types) | Replaced `Picker` with button-based activity list using `ActivityOption` concrete struct. Added `loadingActivities` spinner. Guarded `.task` with `didApplyPreselection` to prevent repeated resets. Guarded `.onChange` to skip reload when contact hasn't changed. |

---

## Overview

Step 7 is a **manual integration testing** step. No code changes are required beyond bug fixes. The deliverable is this structured test log documenting the results of end-to-end testing across two simulator instances, with Firestore document verification.

This is the final step of Sprint 4 (Scheduled Activities). It verifies all features built in Steps 1–6 work correctly together:
- ScheduledActivity model with RecurrenceRule/RecurrenceType (Step 1)
- ScheduleManager service with CRUD, toggle, real-time listener (Step 2)
- processScheduledActivities Cloud Function (Step 3)
- Scheduled activities list view with toggle, swipe-to-delete (Step 4)
- Create and Edit schedule views with contact/activity pickers, recurrence (Step 5)
- Integration into Activity tab: calendar toolbar button + context menu (Step 6)

---

## Test Setup Checklist

| # | Setup Step | Status | Notes |
|---|-----------|--------|-------|
| 1 | Two iOS simulators running (e.g., iPhone 17 + iPhone 17 Pro) | ⏳ | |
| 2 | Anonymous auth signed in on both (different UIDs) | ⏳ | |
| 3 | Both users have display names set (via `SetNameView`) | ⏳ | |
| 4 | Both users have each other as contacts added | ⏳ | Required for contact picker |
| 5 | App connected to remote test Firestore database | ⏳ | |
| 6 | Firebase Console accessible | ⏳ | |
| 7 | Cloud Functions deployed (`processScheduledActivities`, `checkForMatches`) | ⏳ | |

**User A UID:** `________________________`

**User B UID:** `________________________`

---

## Test Cases (14)

### Schedule Creation & One-Time Activation

| # | Test | Expected Result | Status | Notes |
|---|------|----------------|--------|-------|
| 1 | Create one-time schedule for Contact B, activity "Walk" at future time | Schedule appears in list with correct emoji, label, contact name, time, "One-time", toggle ON. Firestore doc has correct fields. | ⏳ | |
| 2 | Wait for scheduledAt time, manually trigger `processScheduledActivities` | Selection doc created in `users/{uidA}/selections/`. Function logs show activation event. | ⏳ | |
| 3 | Verify selection doc schema matches `ContactManager.toggleSelection()` | Fields: `userId`, `targetUserId`, `itemId`, `createdAt`, `expiresAt` (+1hr), `matched: false` | ⏳ | |
| 4 | Contact B also selects "Walk" → wait for `checkForMatches` | Match detected. Both selections `matched: true`. `pendingNotifications` doc created. | ⏳ | |
| 5 | Verify one-time schedule is deleted after activation | `users/{uidA}/scheduledActivities/{docId}` no longer exists | ⏳ | |

### Recurring Schedules

| # | Test | Expected Result | Status | Notes |
|---|------|----------------|--------|-------|
| 6 | Create recurring daily schedule → trigger function | Selection created. `scheduledAt` advanced by 24h. `lastActivatedAt` set. | ⏳ | |
| 7 | Create recurring weekly schedule → trigger function | Selection created. `scheduledAt` advanced by 7d. `lastActivatedAt` set. | ⏳ | |
| 8 | Create recurring custom (Mon/Wed/Fri) → trigger function | Selection created. `scheduledAt` advanced to next valid day (from tomorrow). `lastActivatedAt` set. | ⏳ | |

### Enable/Disable Toggle

| # | Test | Expected Result | Status | Notes |
|---|------|----------------|--------|-------|
| 9 | Toggle schedule disabled → trigger function | No selection created. Schedule remains in Firestore with `enabled: false`. | ⏳ | |
| 10 | Toggle back enabled → trigger function | Selection created. `lastActivatedAt` set. `scheduledAt` advanced or doc deleted (one-time). | ⏳ | |

### Edit & Delete

| # | Test | Expected Result | Status | Notes |
|---|------|----------------|--------|-------|
| 11 | Edit schedule (change time, recurrence) → Save | List updates. Firestore: `scheduledAt` changed, `recurrence` updated. `createdAt` preserved. | ⏳ | |
| 12 | Swipe to delete → confirm | Schedule removed from list immediately. Firestore doc deleted. | ⏳ | |

### Custom Activity & Context Menu

| # | Test | Expected Result | Status | Notes |
|---|------|----------------|--------|-------|
| 13 | Schedule a custom activity (`custom_*` ID) | Schedule created with custom activity ID. Selection created by Cloud Function. Match works end-to-end. | ⏳ | |
| 14 | "Schedule This Activity" from activity list context menu | `CreateScheduleView` opens with contact and activity pre-filled. Tapable activity rows visible. | ⏳ | |

---

## Firestore Document Verification

### `users/{uid}/scheduledActivities/{scheduleId}`

| Field | Type | Verified | Notes |
|-------|------|----------|-------|
| `activityId` | String | ⏳ | |
| `targetContactUid` | String | ⏳ | |
| `scheduledAt` | Timestamp | ⏳ | |
| `recurrence` | Map or null | ⏳ | `{ type, daysOfWeek? }` |
| `enabled` | Boolean | ⏳ | |
| `createdAt` | Timestamp | ⏳ | |
| `lastActivatedAt` | Timestamp? | ⏳ | Set on each activation |

### `users/{uid}/selections/{autoId}` (created by Cloud Function)

| Field | Type | Verified | Notes |
|-------|------|----------|-------|
| `userId` | String | ⏳ | Schedule owner's UID |
| `targetUserId` | String | ⏳ | Target contact's UID |
| `itemId` | String | ⏳ | Activity ID |
| `createdAt` | Timestamp | ⏳ | Function execution time |
| `expiresAt` | Timestamp | ⏳ | `createdAt` + 60 min |
| `matched` | Boolean | ⏳ | `false` initially |

---

## Bugs Found During Testing

| # | Bug Description | Severity | Status | Notes |
|---|----------------|----------|--------|-------|
| B1 | `ScheduledActivitiesListView` has no "+" button to create new schedules — only accessible via context menu on activity list rows | Medium | Fixed | Added toolbar "+" button + sheet presenting `CreateScheduleView` with pre-selected contact |
| B2 | Activity `Picker` in `CreateScheduleView` shows no items — data loads (2 items confirmed via logs) but SwiftUI `Picker` inside conditional `Form` Section with existential `[any ActivityDisplayable]` doesn't render rows | High | Fixed | Replaced `Picker` with button-based `ForEach` activity list using concrete `ActivityOption` struct. Added loading spinner. |
| B3 | `.task` fires repeatedly on view appearance, resetting `selectedContactUid` and causing flash-back to loading state | High | Fixed | Added `didApplyPreselection` guard to `.task`. Added `oldValue != newValue` guard to `.onChange`. |

---

## Test Results Summary

| Category | Total | Pass | Fail | Skipped |
|----------|-------|------|------|---------|
| Schedule Creation & One-Time (1–5) | 5 | ⏳ | ⏳ | 0 |
| Recurring Schedules (6–8) | 3 | ⏳ | ⏳ | 0 |
| Enable/Disable (9–10) | 2 | ⏳ | ⏳ | 0 |
| Edit & Delete (11–12) | 2 | ⏳ | ⏳ | 0 |
| Custom Activity & Context Menu (13–14) | 2 | ⏳ | ⏳ | 0 |
| Firestore Verification | 13 fields | ⏳ | ⏳ | 0 |
| **Total** | **27** | **⏳** | **⏳** | **0** |

---

## Architecture Decisions

1. **Button-based activity list instead of Picker** — SwiftUI `Picker` inside conditional `Form` sections has known rendering bugs when backed by dynamic arrays, especially with protocol-existential types. A simple `ForEach` of buttons with checkmark selection state is more reliable and visually identical to other pickers in the app.

2. **Concrete `ActivityOption` struct** — Avoids ForEach identity issues with `[any ActivityDisplayable]` existential types. The struct is `Identifiable` + `Hashable`, giving SwiftUI stable identity tracking across state updates.

3. **One-time `.task` execution with `didApplyPreselection` guard** — `.task` on views inside sheets can fire multiple times (on sheet presentation, on appearance changes). Guarding with a boolean flag prevents repeated preselection resets.

---

## Build Verification

N/A — Build verified clean after each bug fix during testing session.

---

## Manual Testing Steps

### Setup: Record UIDs

1. Open **Simulator 1** (iPhone 17). Launch the app. Sign in anonymously. Note display name (e.g., "Alice").
2. Open **Simulator 2** (iPhone 17 Pro). Launch the app. Sign in anonymously. Note display name (e.g., "Bob").
3. In each simulator, note the UID from Firebase Console → Firestore → `users` collection. Record them:
   - **User A (Alice):** `________________________`
   - **User B (Bob):** `________________________`
4. Ensure each user has the other saved as a contact.

---

### Test 1: Create One-Time Schedule

1. On **Simulator 1 (Alice)**: Select Contact B in Activity tab.
2. Tap the `calendar.badge.clock` button → `ScheduledActivitiesListView` appears as sheet.
3. Tap **"+"** → `CreateScheduleView` opens.
4. Contact should be pre-selected. If not, select Contact B.
5. Select activity **"Walk"** from the activity list.
6. Set date/time to ~10 minutes from now.
7. Set recurrence to "One-time".
8. Tap **Create**.

**Verify:**
- [ ] Schedule appears in list: 🚶 "Go for a walk?", Contact name, time, "One-time", toggle ON
- [ ] Firebase Console → `users/{uidA}/scheduledActivities/{docId}`:
  - [ ] `activityId`: `"walk"`
  - [ ] `targetContactUid`: User B's UID
  - [ ] `scheduledAt`: Timestamp (correct future time)
  - [ ] `recurrence`: absent/null
  - [ ] `enabled`: true
  - [ ] `createdAt`: Timestamp
  - [ ] `lastActivatedAt`: absent

---

### Test 2: Manual Function Trigger — Selection Created

1. Wait for the schedule's `scheduledAt` time to pass.
2. Manually trigger `processScheduledActivities` via Firebase Console → Functions → `processScheduledActivities` → **Run** (or via `firebase functions:shell`).

**Verify:**
- [ ] `users/{uidA}/selections/{autoId}` document created
- [ ] Function logs show: `Activated schedule ...`

---

### Test 3: Selection Doc Schema Verification

**Verify in Firebase Console → `users/{uidA}/selections/{docId}`:**
- [ ] `userId`: User A's UID
- [ ] `targetUserId`: User B's UID
- [ ] `itemId`: `"walk"`
- [ ] `createdAt`: Timestamp
- [ ] `expiresAt`: Timestamp = `createdAt` + 60 minutes
- [ ] `matched`: false

---

### Test 4: Match Detection

1. On **Simulator 2 (Bob)**: Select activity "Walk" for User A manually (using the normal matching flow).
2. Wait up to 5 minutes for `checkForMatches` to run.

**Verify:**
- [ ] Both selection docs updated: `matched: true`
- [ ] `pendingNotifications` document created with both UIDs, `itemId: "walk"`
- [ ] Match notification visible in app

---

### Test 5: One-Time Schedule Auto-Deleted

**Verify in Firebase Console:**
- [ ] `users/{uidA}/scheduledActivities/{docId}` no longer exists

---

### Test 6: Recurring Daily Schedule

1. On **Simulator 1 (Alice)**: Create new schedule — "Walk" for Contact B, recurrence = "Daily", time ~5 min from now.
2. Wait for `scheduledAt` to pass, manually trigger `processScheduledActivities`.

**Verify:**
- [ ] Selection doc created in `users/{uidA}/selections/`
- [ ] `scheduledAt` updated to ~24 hours after original time
- [ ] `lastActivatedAt` updated

---

### Test 7: Recurring Weekly Schedule

1. On **Simulator 1 (Alice)**: Create new schedule — "Walk" for Contact B, recurrence = "Weekly", time ~5 min from now.
2. Wait for `scheduledAt` to pass, manually trigger `processScheduledActivities`.

**Verify:**
- [ ] Selection doc created
- [ ] `scheduledAt` updated to ~7 days after original time
- [ ] `lastActivatedAt` updated

---

### Test 8: Recurring Custom (Mon/Wed/Fri)

1. On **Simulator 1 (Alice)**: Create schedule — "Walk" for Contact B, recurrence = "Custom", select Mon/Wed/Fri, time ~5 min from now.
2. Wait for `scheduledAt` to pass, manually trigger `processScheduledActivities`.

**Verify:**
- [ ] Selection doc created
- [ ] `scheduledAt` updated to next Mon/Wed/Fri (from tomorrow)
- [ ] `lastActivatedAt` updated

---

### Test 9: Toggle Disabled — Skipped

1. On **Simulator 1 (Alice)**: Toggle a schedule OFF in the list view.
2. Manually trigger `processScheduledActivities`.

**Verify:**
- [ ] No new selection doc created
- [ ] Schedule doc remains in Firestore with `enabled: false`

---

### Test 10: Toggle Re-Enabled — Fires

1. On **Simulator 1 (Alice)**: Toggle the same schedule back ON.
2. If `scheduledAt` is in the future, edit it to a past time.
3. Manually trigger `processScheduledActivities`.

**Verify:**
- [ ] Selection doc created
- [ ] `lastActivatedAt` updated
- [ ] `scheduledAt` advanced (recurring) or doc deleted (one-time)

---

### Test 11: Edit Schedule

1. On **Simulator 1 (Alice)**: Tap a schedule row → `EditScheduleView` opens.
2. Change date/time. Change recurrence to "Daily".
3. Tap **Save**.

**Verify:**
- [ ] List view shows updated time and "Daily at X:XX PM"
- [ ] Firestore: `scheduledAt` updated, `recurrence.type` = "daily"
- [ ] `createdAt` unchanged

---

### Test 12: Delete Schedule

1. On **Simulator 1 (Alice)**: Swipe left on a schedule → tap **Delete** → confirm.

**Verify:**
- [ ] Schedule disappears from list
- [ ] Firestore doc deleted

---

### Test 13: Custom Activity End-to-End

1. On **Simulator 1 (Alice)**: Create a custom activity (if none exists) via Settings → Custom Activities.
2. Create a schedule for Contact B using that custom activity.
3. Trigger `processScheduledActivities`.

**Verify:**
- [ ] Schedule `activityId`: `"custom_xxx"`
- [ ] Selection doc created with same `itemId`
- [ ] If Contact B also selects the same custom activity → match detected

---

### Test 14: Context Menu Pre-Fill

1. On **Simulator 1 (Alice)**: Activity tab → select Contact B.
2. In activity list, long-press "Walk" → tap "Schedule This Activity".

**Verify:**
- [ ] `CreateScheduleView` opens with Contact B pre-selected
- [ ] "Walk" is pre-selected (checkmark visible)
- [ ] Activity list rows are visible and tappable
- [ ] Cannot save without a future date/time
