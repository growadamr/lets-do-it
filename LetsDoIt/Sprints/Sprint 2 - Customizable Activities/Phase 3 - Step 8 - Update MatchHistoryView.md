# Phase 3 - Step 8: Update MatchHistoryView

**Date:** April 6, 2026  
**Build Status:** ✅ Complete — BUILD SUCCEEDED

---

## What Was Done

### New Methods

| File | Method | Purpose |
|------|--------|---------|
| `Services/ActivityManager.swift` | `resolveActivityDetails(itemId:contactUid:)` | Resolves any activity ID (catalog or custom) to emoji + label |
| `Services/ActivityManager.swift` | `fetchCustomActivity(uid:activityId:)` | Fetches a single custom activity document from a specific user's collection |

### Modified Files

| File | Change |
|------|--------|
| `Views/MatchHistoryView.swift` | Replaced catalog-only lookup with `ActivityManager.resolveActivityDetails` + in-memory cache |
| `Services/ActivityManager.swift` | Added activity resolution section with two new methods |

---

## Detailed Changes

### ActivityManager.swift — Activity Resolution Section

Added a new `// MARK: - Activity Resolution` section with two methods:

#### `resolveActivityDetails(itemId: String, contactUid: String) async -> (emoji: String, label: String)`

Resolves an activity ID to display details using a 4-tier lookup:

1. **Catalog lookup** — `ActivityCatalog.items.first(where:)` (fast, no network)
2. **Current user's custom activities** — Firestore fetch from `users/{uid}/customActivities/{itemId}`
3. **Contact's custom activities** — Firestore fetch from `users/{contactUid}/customActivities/{itemId}` (the contact who created it)
4. **Fallback** — `("🎯", itemId)` (same fallback as the notification system)

#### `fetchCustomActivity(uid: String, activityId: String) async throws -> CustomActivity?`

Private helper that fetches a single document from a user's `customActivities` collection and deserializes it into a `CustomActivity` struct. Returns `nil` if the doc doesn't exist or fails parsing.

### MatchHistoryView.swift — loadMatches() Update

**Before:** The deduplication loop used only `ActivityCatalog.items.first(where:)` — any `custom_*` ID was silently dropped (no MatchRecord created).

**After:**
- Added `var customActivityCache: [String: (emoji: String, label: String)] = [:]` scoped to the single `loadMatches()` call
- Replaced the catalog-only `if let` block with a unified resolution path:
  1. Check cache first (avoids repeated Firestore reads for the same `custom_*` ID)
  2. Call `ActivityManager.shared.resolveActivityDetails(itemId:contactUid:)`
  3. Store result in cache
  4. Always append a `MatchRecord` (no more silent drops)

---

## Architecture Decisions

1. **Cache scoped to single load** — The `customActivityCache` dictionary is local to `loadMatches()`, so it's fresh on every refresh. This avoids stale data across sessions while deduplicating reads within one history load (e.g., multiple matches on the same custom activity).

2. **Tuple return over new model** — `MatchRecord` only needs `emoji` and `label` strings. A lightweight tuple `(emoji: String, label: String)` avoids creating an intermediate struct. The private `fetchCustomActivity` helper returns `CustomActivity?` for proper model usage internally.

3. **Two-tier custom activity lookup** — Tries current user's collection first (likely owns it), then contact's collection (they created it). This covers both scenarios: "I matched on my custom activity" and "I matched on their custom activity."

4. **Consistent fallback** — The `("🎯", itemId)` fallback matches the existing behavior in `sendMatchNotification` Cloud Function, keeping UI and notifications aligned.

5. **No new dependencies** — `MatchHistoryView` already has access to `contactUid` as a `let` parameter, so passing it to `resolveActivityDetails` required no structural changes.

---

## Build Verification

```
xcodebuild -scheme LetsDoIt -destination 'platform=iOS Simulator,name=iPhone 17' build
```

**Result:** `** BUILD SUCCEEDED **` — no errors, no warnings.
