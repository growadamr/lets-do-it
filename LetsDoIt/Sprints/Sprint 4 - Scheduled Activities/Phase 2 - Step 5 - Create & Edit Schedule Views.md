# Phase 2 — Step 5: Create & Edit Schedule Views

**Date:** April 6, 2026
**Build Status:** ✅ BUILD SUCCEEDED

---

## What Was Done

### New Files (4)

| File | Purpose |
|------|---------|
| `Views/Scheduling/RecurrencePickerView.swift` | Sheet-based picker for recurrence type (one-time/daily/weekly/custom) with day-of-week circles |
| `Views/Scheduling/CreateScheduleView.swift` | Form for creating a new scheduled activity with contact, activity, date/time, and recurrence pickers |
| `Views/Scheduling/EditScheduleView.swift` | Form for editing an existing schedule, with save and delete |
| `Views/Scheduling/SingleContactPickerView.swift` | Lightweight single-select contact picker with search |

### Modified Files (1)

| File | Change |
|------|--------|
| `Views/Scheduling/ScheduledActivitiesListView.swift` | Added `scheduleToEdit` state and `.navigationDestination` to navigate to `EditScheduleView` on tap |

---

## RecurrencePickerView

A sheet-based picker bound to `Binding<RecurrenceRule?>`.

### UI Layout
- **Recurrence Type Picker**: Segmented options — "One-time", "Daily", "Weekly", "Custom"
- **Custom Day Selection**: When "Custom" is selected, shows 7 tappable circles (S M T W T F S) representing Sunday=0 through Saturday=6
- **Validation**: Done button disabled if "Custom" selected with zero days; error message shown

### Key Properties/Methods

| Property/Method | Type | Purpose |
|-----------------|------|---------|
| `recurrence` | `Binding<RecurrenceRule?>` | Input/output binding for the selected recurrence rule |
| `selectedType` | `RecurrenceType` | Internal state for the selected recurrence type |
| `selectedDays` | `Set<Int>` | Internal state for custom day-of-week selection |
| `weekdaySymbols` | `[String]` | Very short weekday symbols (S, M, T, W, T, F, S), Sunday-first |
| `applyRecurrence()` | `Void` | Converts picker state to `RecurrenceRule?` and dismisses |

### RecurrenceRule Display Helper

Added `displaySummary` computed property on `RecurrenceRule`:
- `daily` → "Daily"
- `weekly` → "Weekly"
- `custom` with days → "Every S, M, W" (uses very short weekday symbols)

---

## SingleContactPickerView

A lightweight single-select contact picker, mirroring the `MultiContactPickerView` pattern but with `Binding<String?>` instead of `Binding<[String]>`.

### UI Layout
- `List` of contacts with avatars and checkmark indicator for selected
- Search bar for filtering contacts
- Tap selects the contact and dismisses immediately
- Cancel button to abort

### Key Properties

| Property | Type | Purpose |
|----------|------|---------|
| `selectedUid` | `Binding<String?>` | Single selected contact UID |
| `filteredContacts` | `[Contact]` | Search-filtered contact list |

---

## CreateScheduleView

Form for creating a new scheduled activity.

### Sections
1. **Contact**: Button opens `SingleContactPickerView`, shows selected contact name or "Select a contact" (red)
2. **Activity**: `Picker` showing effective activities for the selected contact (emoji + label), loaded via `ActivityManager.getEffectiveActivities(for:)`
3. **Date & Time**: `DatePicker` with future dates only (`.date` + `.hourAndMinute`)
4. **Recurrence**: Button opens `RecurrencePickerView`, shows recurrence summary ("One-time", "Daily", "Weekly", "Every Mon, Wed, Fri")

### Validation
- Contact: required
- Activity: required
- Date: must be in the future (`scheduledAt > Date()`)
- Custom recurrence: at least one day required (enforced by `RecurrencePickerView`)

### Pre-selection Support
- `preselectedContactUid`: Auto-selects contact when navigated from a contact-specific view
- `preselectedActivityId`: Auto-selects activity when navigated from "Schedule This Activity"
- When contact changes, activity list reloads and pre-selected activity is restored if still valid

### Save Flow
```swift
try await scheduleManager.createSchedule(
    activityId: activityId,
    targetContactUid: contactUid,
    scheduledAt: scheduledAt,
    recurrence: recurrence
)
```
On success: calls `onCreate` callback and dismisses.

---

## EditScheduleView

Form for editing an existing `ScheduledActivity`. Same layout as `CreateScheduleView`, pre-filled with existing values.

### Key Differences from CreateScheduleView
- Contact is pre-set (non-optional `String` state), but still changeable via picker
- Activity is pre-selected
- Date/time pre-filled (still enforces future date for saves)
- Recurrence pre-filled
- **Delete button**: Destructive section with confirmation dialog
- No `onCreate` callback — changes saved directly via `ScheduleManager.updateSchedule()`

### Save Flow
```swift
let newSchedule = ScheduledActivity(
    id: schedule.id,
    activityId: activityId,
    targetContactUid: selectedContactUid,
    scheduledAt: scheduledAt,
    recurrence: recurrence,
    enabled: schedule.enabled,
    createdAt: schedule.createdAt,
    lastActivatedAt: schedule.lastActivatedAt
)
try await scheduleManager.updateSchedule(newSchedule)
```

### Delete Flow
```swift
try await scheduleManager.deleteSchedule(id: schedule.id)
```
On success: dismisses.

---

## ScheduledActivitiesListView (Modified)

### Changes
- Added `@State private var scheduleToEdit: ScheduledActivity?`
- Tap gesture on schedule rows now sets `scheduleToEdit` (was a placeholder comment)
- Added `.navigationDestination(item: $scheduleToEdit) { schedule in EditScheduleView(schedule: schedule) }`

---

## Architecture Decisions

1. **SingleContactPickerView instead of reusing MultiContactPickerView**: The existing `MultiContactPickerView` uses `Binding<[String]>` for multi-select. Creating a dedicated single-select picker with `Binding<String?>` is cleaner and avoids adapter code. The two views share the same row pattern (`ContactPickerRow` / `SingleContactRow`) with checkmark indicators.

2. **Activity picker as inline Picker (not a sheet)**: Since the effective activity list is a manageable size (catalog ~15 items + a few custom activities), an inline `Picker` within the form is simpler than a separate sheet. This also matches the project's existing form patterns.

3. **EditScheduleView uses non-optional `selectedContactUid`**: Since a schedule always has a target contact, the edit view's contact state is initialized as a non-optional `String`. The binding to `SingleContactPickerView` is adapted using a custom `Binding(get:set:)` wrapper.

4. **Future date validation in EditScheduleView**: The edit view also enforces `scheduledAt > Date()` via the DatePicker's `in: Date()...` range. This prevents editing a schedule to a past date (which wouldn't make sense for scheduling).

5. **Recurrence picker defaults to "Daily" in init**: When no existing recurrence is provided, the picker defaults to `.daily` type. This is a reasonable default — the user sees "Daily" pre-selected rather than a confusing empty state.

6. **`displaySummary` extension on `RecurrenceRule`**: Provides a reusable human-readable summary for both the recurrence picker's preview and the create/edit forms' recurrence row.

---

## Build Verification

**Command:** `xcodebuild -scheme LetsDoIt -destination 'platform=iOS Simulator,name=iPhone 17' build`
**Result:** BUILD SUCCEEDED
**Warnings:** 0
**Errors:** 0
