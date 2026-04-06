# Phase 1 - Step 1: ScheduledActivity Model & RecurrenceRule

**Date:** April 6, 2026
**Build Status:** ✅ BUILD SUCCEEDED

---

## What Was Done

Created the data model for scheduled activities: `ScheduledActivity` struct, `RecurrenceRule` struct, and `RecurrenceType` enum.

### New Files

| File | Purpose |
|------|---------|
| `Models/ScheduledActivity.swift` | `ScheduledActivity`, `RecurrenceRule`, `RecurrenceType` — pure Swift models |

---

## Models

### `RecurrenceType` enum

| Case | Raw Value | Display Label |
|------|-----------|---------------|
| `.daily` | `"daily"` | "Daily" |
| `.weekly` | `"weekly"` | "Weekly" |
| `.custom` | `"custom"` | "Custom" |

- `String`-backed, `Codable`, `CaseIterable`
- `displayLabel` computed property for UI rendering

### `RecurrenceRule` struct

| Property | Type | Notes |
|----------|------|-------|
| `type` | `RecurrenceType` | Daily, weekly, or custom |
| `daysOfWeek` | `[Int]?` | Sunday=0 through Saturday=6; only used for `.custom` |

- `Codable`, `Hashable`
- `daysOfWeek` is `nil` for `.daily` and `.weekly` types

### `ScheduledActivity` struct

| Property | Type | Notes |
|----------|------|-------|
| `id` | `String` | UUID, defaults to `UUID().uuidString` |
| `activityId` | `String` | Catalog ID or `custom_*` ID |
| `targetContactUid` | `String` | The contact this schedule targets |
| `scheduledAt` | `Date` | Next activation time (server-time reference) |
| `recurrence` | `RecurrenceRule?` | `nil` for one-time schedules |
| `enabled` | `Bool` | Defaults to `true` |
| `createdAt` | `Date?` | When the schedule was created |
| `lastActivatedAt` | `Date?` | Set each time the Cloud Function fires |

- `Identifiable`, `Codable`, `Hashable`
- `Hashable` via `id` only (matching `Event` and `CustomActivity` patterns)
- Explicit `CodingKeys` enum
- **No `FirebaseFirestore` import** — uses `Date`, not `Timestamp`

---

## Architecture Decisions

1. **Single file for all three types** — `RecurrenceType` and `RecurrenceRule` are tightly coupled to `ScheduledActivity` and small enough to live in the same file (matching how `RSVPStatus` and `EventStatus` live alongside `Event`).

2. **`Date` not `Timestamp`** — Pure Swift models with no Firebase import. `Date` ↔ `Timestamp` conversion happens in the `ScheduleManager` service layer (Step 2), following the established pattern from `Event` and `CustomActivity`.

3. **`Hashable` via `id` only** — Consistent with `Event.swift` and `CustomActivity.swift`. Two `ScheduledActivity` instances with the same `id` are equal regardless of other field differences (important for `@Published` array diffing and SwiftUI `List` identity).

4. **`enabled` defaults to `true`** — New schedules are active by default. The toggle is only needed for pausing an existing schedule.

5. **`daysOfWeek: [Int]?`** — Uses integer representation (Sunday=0 through Saturday=6) matching JavaScript `Date.getDay()` convention, which the Cloud Function will use for server-side recurrence calculation.

---

## Build Verification

```
xcodebuild -scheme LetsDoIt -destination 'platform=iOS Simulator,name=iPhone 17' build
** BUILD SUCCEEDED **
```
