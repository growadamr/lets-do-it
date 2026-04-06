# Phase 1, Step 2: ActivityManager Service — Implementation Log

**Date:** 2026-04-05
**Status:** ✅ Complete — BUILD SUCCEEDED

---

## What Was Done

### New Files Created

| File | Purpose |
|------|---------|
| `Services/ActivityManager.swift` | Activity preferences CRUD, custom activity CRUD, effective activity list computation, real-time listeners |

### Files Modified

None.

---

## Service Details

### `ActivityManager`

```swift
@MainActor class ActivityManager: ObservableObject
```

| Property | Type | Notes |
|---|---|---|
| `shared` | `static ActivityManager` | Singleton instance |
| `customActivities` | `@Published [CustomActivity]` | Auto-updated by real-time listener |
| `preferences` | `@Published [String: Bool]` | ActivityId → enabled (missing = enabled) |

### Preference Operations

| Method | Description |
|---|---|
| `startListeningPreferences()` | Real-time listener on `users/{uid}/activityPreferences`. Populates `@Published preferences` dict. |
| `stopListeningPreferences()` | Removes listener, clears published array. |
| `loadPreferences()` | One-time fetch of all preference docs. |
| `togglePreference(activityId:)` | Creates/updates preference doc with inverted `enabled` value. |
| `isEnabled(_:)` | Returns `preferences[activityId] ?? true` — missing defaults to enabled. |

### Custom Activity Operations

| Method | Description |
|---|---|
| `startListeningCustomActivities()` | Real-time listener on `users/{uid}/customActivities`, ordered by `createdAt` ascending. Populates `@Published customActivities`. |
| `stopListeningCustomActivities()` | Removes listener, clears published array. |
| `createCustomActivity(emoji:label:category:visibleTo:)` | Creates doc with `custom_<uuid>` ID. Returns the `CustomActivity` model. |
| `updateCustomActivity(_:)` | Full doc update with all fields. |
| `deleteCustomActivity(id:)` | Deletes the custom activity doc. |
| `fetchVisibleCustomActivities(for:)` | One-time fetch of another user's custom activities where current user is in `visibleTo` (uses `arrayContains` query). |

### Effective Activity List

| Method | Description |
|---|---|
| `getEffectiveActivities(for:)` | Computes the mutually visible activity list for a contact pair. Returns `[any ActivityDisplayable]` sorted by category order then label. |

**`getEffectiveActivities` logic:**
1. My enabled catalog items (all catalog items where `isEnabled` is true)
2. My custom activities visible to this contact (from `@Published customActivities`, filtered by `visibleTo`)
3. Contact's enabled catalog items (fetch their `activityPreferences` — items not in prefs = enabled)
4. Contact's custom activities visible to me (one-time `arrayContains` query)
5. Intersection: catalog items enabled by both + custom activities mutually visible to both
6. Sort by `ActivityCategory` order then label

---

## Architecture Decisions

1. **Two separate listeners** (preferences + custom activities) for clean reactive state, matching the `MessagingManager` pattern of multiple independent listeners.

2. **`preferences` as `[String: Bool]` dict** instead of array — O(1) lookup for `isEnabled`, mirrors how prefs are keyed by activityId in Firestore.

3. **Service layer handles Date ↔ Timestamp conversion** — `CustomActivity` model uses pure `Date?` (established in Step 1). The service converts `Timestamp` → `Date` on read via `.dateValue()` and uses `Timestamp(date:)` on write. Models have no `FirebaseFirestore` import.

4. **`getEffectiveActivities` does NOT cache contact data** — called fresh each time since contact switching is infrequent and data volume is small. Avoids stale state complexity.

5. **`custom_` prefix for generated IDs** — `createCustomActivity` generates `custom_<uuid>` as the document ID. This prefix is used downstream by `checkForMatches` and `MatchHistoryView` to distinguish custom from catalog items.

6. **Error types defined in same file** — `ActivityManagerError` enum follows the `ContactError` / `MessagingError` pattern — defined at file bottom with `LocalizedError` conformance.

---

## Build Verification
```
xcodebuild -scheme LetsDoIt -destination 'platform=iOS Simulator,name=iPhone 17' build
→ BUILD SUCCEEDED
```
