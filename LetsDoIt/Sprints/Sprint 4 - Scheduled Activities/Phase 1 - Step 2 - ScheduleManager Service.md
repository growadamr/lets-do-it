# Phase 1 - Step 2: ScheduleManager Service

**Date:** April 6, 2026
**Build Status:** ✅ BUILD SUCCEEDED

---

## What Was Done

Created `ScheduleManager` — the central service for scheduled activity CRUD, real-time listening, and helper utilities.

### New Files

| File | Purpose |
|------|---------|
| `Services/ScheduleManager.swift` | Schedule CRUD, real-time listener, helper methods |

---

## ScheduleManager Service

### Structure

`@MainActor class ScheduleManager: ObservableObject` (singleton `.shared`)

### Properties

| Property | Type | Description |
|----------|------|-------------|
| `schedules` | `@Published [ScheduledActivity]` | All schedules, sorted by `scheduledAt` ascending |

### Schedule CRUD Methods

| Method | Description |
|--------|-------------|
| `createSchedule(activityId:targetContactUid:scheduledAt:recurrence:)` | Creates a new schedule doc with `enabled: true` and `createdAt: serverTimestamp`. Returns the created `ScheduledActivity`. |
| `updateSchedule(_:)` | Merge-updates all mutable fields (activityId, targetContactUid, scheduledAt, enabled, recurrence). Sets `recurrence` to `NSNull()` when nil. |
| `deleteSchedule(id:)` | Deletes the schedule document. |
| `toggleEnabled(id:enabled:)` | Updates only the `enabled` field (pause/resume without deleting). |

### Real-Time Listener

| Method | Description |
|--------|-------------|
| `startListening()` | Listens to `users/{uid}/scheduledActivities` ordered by `scheduledAt` ascending. Decodes into `@Published schedules`. |
| `stopListening()` | Removes listener, clears `schedules` array. |

### Helper Methods

| Method | Description |
|--------|-------------|
| `schedulesForContact(_ contactUid:)` | Filters `schedules` by `targetContactUid`. |
| `nextActivationDescription(_:)` | Returns human-readable string: "Today at 3:00 PM", "Tomorrow at 9:00 AM", "Daily at 8:00 AM", "Every Mon, Wed, Fri at 10:00 AM", etc. |

### Error Types

| Error | Description |
|-------|-------------|
| `.notAuthenticated` | No current user |
| `.scheduleNotFound` | Schedule ID doesn't exist |
| `.invalidRecurrence` | Recurrence rule is malformed |

---

## Architecture Decisions

1. **Follows EventManager pattern exactly** — Same singleton, `@Published` arrays, `ListenerRegistration?`, `currentUid`/`requireUid()` helper pattern. Consistency across services makes the codebase predictable.

2. **`updateSchedule` uses `setData(merge: true)`** — Like `EventManager`, we use merge writes to handle optional fields (like `recurrence` which can be `nil`). When `recurrence` is nil, we explicitly set it to `NSNull()` to clear it from Firestore.

3. **`createSchedule` returns the created model immediately** — Like `EventManager.createEvent`, the returned model has `createdAt` set to `now` locally (the actual server timestamp will be populated by the listener on the next snapshot).

4. **Decoding uses `guard let` for required fields** — `activityId` and `targetContactUid` are required; if missing, the doc is silently skipped (with no crash). Optional fields (`recurrence`, `createdAt`, `lastActivatedAt`) default to `nil`.

5. **Recurrence decoding uses `Firestore.Decoder`** — The `RecurrenceRule` struct is `Codable`, so we use the Firestore encoder/decoder for safe round-trip serialization.

6. **`nextActivationDescription` handles day-of-week mapping** — `daysOfWeek` stores 0=Sunday through 6=Saturday. `Calendar.current.weekdaySymbols` also has Sunday at index 0, so the mapping is direct (`idx = dayIndex`).

7. **Relative date formatting uses `localizedString(for:relativeTo:)`** — `RelativeDateTimeFormatter` doesn't have `localizedRelativeDate`; the correct API is `localizedString(for:relativeTo:)` which returns strings like "in 2 days", "last week", etc.

---

## Build Verification

```
xcodebuild -scheme LetsDoIt -destination 'platform=iOS Simulator,name=iPhone 17' build
** BUILD SUCCEEDED **
```
