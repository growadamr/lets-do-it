# Phase 1 - Step 3: processScheduledActivities Cloud Function

**Date:** April 6, 2026
**Build Status:** ✅ SYNTAX CHECK PASSED

---

## What Was Done

Added the `processScheduledActivities` Cloud Function to the match functions project, plus a `scheduleProcessInterval` reference constant in `AppConfig.swift` and a Firestore collection group index.

### Modified Files

| File | Change |
|------|--------|
| `/hermGameTest/functions/index.js` | Added `processScheduledActivities` function + `calculateNextActivation` helper |
| `Models/AppConfig.swift` | Added `scheduleProcessInterval` constant (5 minutes) |
| `firebase/firestore.indexes.json` | Added collection group index on `scheduledActivities` (enabled + scheduledAt) |

---

## processScheduledActivities Function

### Schedule

`every 5 minutes` (matches `checkForMatches` cadence)

### Query

Collection group query on `scheduledActivities`:
- `enabled == true`
- `scheduledAt <= now`

### Activation Logic (per due schedule)

1. **Re-fetch in transaction** — avoids double-processing race conditions
2. **Validate fields** — skip if `userId`, `targetContactUid`, or `activityId` is missing
3. **Create selection doc** in `users/{userId}/selections/` with schema matching `ContactManager.toggleSelection()`:
   - `userId`: the schedule owner
   - `targetUserId`: from `targetContactUid`
   - `itemId`: from `activityId` (works for both catalog and `custom_*` IDs)
   - `createdAt`: `Timestamp.now()`
   - `expiresAt`: `now + 3600000ms` (1 hour, matches `AppConfig.selectionExpiryDuration`)
   - `matched`: `false`
4. **Set `lastActivatedAt`** to now
5. **Recurrence handling**:
   - If `recurrence` is non-null → calculate next `scheduledAt`, update the doc
   - If `recurrence` is null (one-time) → delete the schedule doc

### Recurrence Calculation (`calculateNextActivation`)

| Type | Logic |
|------|-------|
| `daily` | Add 24 hours to now |
| `weekly` | Add 7 days to now |
| `custom` with `daysOfWeek` | Find the next matching day of week (Sunday=0) within 7 days, starting from tomorrow to avoid same-day double-fire. Preserves the original hour/minute from `now`. |
| Invalid/empty | Returns `null` → schedule is deleted |

### Error Handling

- Invalid/missing fields: logged with `console.warn`, schedule skipped
- Transaction failure: logged with `console.error`, continues to next schedule
- Unresolvable recurrence: schedule is deleted (prevents infinite broken-state loops)

---

## Architecture Decisions

1. **Transactions prevent double-activation** — Each schedule is re-fetched within a transaction and checked again for `enabled` and `scheduledAt <= now`. This prevents race conditions where two function invocations both pick up the same schedule.

2. **Selection doc schema matches `ContactManager.toggleSelection()` exactly** — Same fields (`userId`, `targetUserId`, `itemId`, `createdAt`, `expiresAt`, `matched`). This means `checkForMatches` picks up scheduled selections with zero changes.

3. **Collection group query for efficiency** — Single query across all users' `scheduledActivities` subcollections instead of iterating users. Requires a collection group index but is far more efficient.

4. **Same 5-minute cadence as `checkForMatches`** — The schedule processor and match checker run on the same interval. A scheduled activity creates a selection, and within ~5 minutes `checkForMatches` will detect any mutual matches.

5. **One-time schedules auto-delete** — After activation, the schedule doc is removed to keep the collection clean. The selection doc persists independently (has its own expiry and is cleaned up by `cleanupExpiredSelections`).

6. **Custom recurrence starts from tomorrow** — When finding the next matching day of the week, we start from `i = 1` (tomorrow) to avoid same-day double-fire. If a schedule fires at 9 AM Monday and the custom rule includes Monday, we don't want it to fire again at the next 5-minute check on the same Monday.

7. **Preserves original time for custom recurrence** — The `calculateNextActivation` function preserves the hour/minute from the current `now` timestamp when computing the next custom day, so schedules maintain consistent activation times.

---

## AppConfig Change

Added `scheduleProcessInterval` to the Cloud Functions section:

```swift
/// How often `processScheduledActivities` runs (server-side).
static let scheduleProcessInterval: TimeInterval = 5 * 60  // 5 minutes
```

This is a documented reference for the function's cadence, matching the pattern of `matchCheckInterval`, `notificationSendInterval`, and `cleanupInterval`.

---

## Firestore Index

Added to `firebase/firestore.indexes.json`:

```json
{
  "collectionGroup": "scheduledActivities",
  "queryScope": "COLLECTION_GROUP",
  "fields": [
    { "fieldPath": "enabled", "order": "ASCENDING" },
    { "fieldPath": "scheduledAt", "order": "ASCENDING" }
  ]
}
```

Required for the collection group query: `where("enabled", "==", true).where("scheduledAt", "<=", now)`.

---

## Build Verification

```
node --check /Users/adamgrow/hermGameTest/functions/index.js
✅ No errors (exit code 0)

node -e "JSON.parse(fs.readFileSync('firebase/firestore.indexes.json'))"
✅ Valid JSON
```
