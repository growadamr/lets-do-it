# Phase 3, Step 7: Update ActivityListView — Implementation Log

**Date:** 2026-04-06
**Status:** ✅ Complete — BUILD SUCCEEDED

---

## What Was Done

### New Files Created

None.

### Files Modified

| File | Change |
|------|--------|
| `Views/ActivityListView.swift` | Replaced `ActivityCatalog.grouped` with `ActivityManager.getEffectiveActivities(for:)`; added `@StateObject ActivityManager.shared`; separated loading states for selections vs. activities; updated `selectItem` to accept `any ActivityDisplayable` |
| `Views/ActivityRow.swift` | Changed `item: ActivityItem` → `item: any ActivityDisplayable` |

---

## Changes Detail

### `ActivityListView.swift`

**New/modified properties:**

| Property | Type | Purpose |
|---|---|---|
| `activityManager` | `@StateObject ActivityManager` | Injects singleton for effective activity list computation |
| `effectiveActivities` | `@State [any ActivityDisplayable]` | Stores the computed activity list for the selected contact |
| `isActivitiesLoading` | `@State Bool` | Separate loading state for effective activities fetch |

**New/modified methods:**

| Method | Change |
|---|---|
| `groupedActivities` (computed var) | New — groups `effectiveActivities` by `ActivityCategory` for sectioned display, mirrors `ActivityCatalog.grouped` structure |
| `refreshAll()` | New — calls both `refreshSelections()` and `loadEffectiveActivities()` in parallel |
| `loadEffectiveActivities()` | New — calls `activityManager.getEffectiveActivities(for: contactUid)`, handles empty contact guard and error state |
| `selectItem(_:)` | Changed parameter from `ActivityItem` to `any ActivityDisplayable` |

**Body changes:**
- Loading state now checks `isLoading || isActivitiesLoading` (either being true shows `ProgressView`)
- ProgressView text changed from "Loading selections..." to "Loading activities..."
- Error retry button calls `refreshAll()` instead of just `refreshSelections()`
- `ForEach` iterates over `groupedActivities` instead of `ActivityCatalog.grouped`
- Inner `ForEach` uses explicit `id: \.id` for protocol-type compatibility

### `ActivityRow.swift`

**Changed property:**

| Property | Before | After |
|---|---|---|
| `item` | `ActivityItem` | `any ActivityDisplayable` |

No other changes needed — the view already accesses `item.emoji` and `item.label` which are protocol requirements.

---

## Architecture Decisions

1. **Separate loading states for selections and activities** — The original `isLoading` tracked only selection refreshes. A new `isActivitiesLoading` state was added so the UI can accurately reflect which data is still loading. Both are OR'd together in the view's outer `Group` to show a single `ProgressView` while either is in flight. This keeps the UX simple (one loading indicator) while allowing independent refresh cycles.

2. **`groupedActivities` as a computed var, not `@State`** — Grouping is a pure transformation of `effectiveActivities`. Computing it on demand avoids stale state bugs and is cheap for the ~16–30 items expected.

3. **`ForEach` inner loop uses `id: \.id` explicitly** — Since `effectiveActivities` is typed as `[any ActivityDisplayable]`, Swift needs an explicit key path for `Identifiable` conformance on the protocol existential. Using `id: \.id` resolves this.

4. **`@StateObject` for `ActivityManager.shared`** — The shared instance is an `ObservableObject` singleton. Using `@StateObject` ensures SwiftUI observes `@Published` changes (`customActivities`, `preferences`) and re-renders when the effective activity list changes due to preference toggles or custom activity CRUD operations.

5. **`refreshAll()` called in `.task`** — Both data sources (selections + effective activities) are fetched on view appearance. The timer still only refreshes selections (selections have a 60-min expiry and need periodic checking; activities only change when preferences/custom activities are modified, which triggers via `@Published` updates).

---

## Build Verification
```
xcodebuild -scheme LetsDoIt -destination 'platform=iOS Simulator,name=iPhone 17' build
→ BUILD SUCCEEDED
```
