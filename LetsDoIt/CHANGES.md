# Changes

## Per-Contact Activity Preferences

**Date:** 2026-04-06

**Problem:** Activity preferences (enable/disable activities) were global per user — disabling "Drinks" in Activity Settings disabled it for ALL contacts.

**Fix:** Preferences are now scoped per-contact. You can disable "Drinks" for Alice but keep it enabled for Bob.

### What Changed

**Firestore:** New collection `users/{userId}/contactActivityPreferences/{contactUid}_{activityId}` storing `{ enabled: Bool }`. Legacy global `activityPreferences` docs are kept as a fallback — no migration needed.

**`Services/ActivityManager.swift`**
- Added `contactPreferences: [String: Bool]` (keyed as `"{contactUid}_{activityId}"`)
- Added `startListeningContactPreferences()` / `stopListeningContactPreferences()` / `loadContactPreferences()`
- Added `isEnabled(for contactUid: activityId:)` — checks per-contact pref first, falls back to legacy global pref, defaults to `true`
- Added `togglePreference(for contactUid: activityId:)` — writes to the new collection
- `getEffectiveActivities(for:)` now uses `isEnabled(for:activityId:)` for the current user's catalog filtering
- Legacy `isEnabled(_:)` and `togglePreference(activityId:)` retained for backward compatibility

**`Views/Activities/ActivitySettingsView.swift`**
- Requires `let contactUid: String` parameter — all toggles are scoped to that contact

**`Views/ActivityTabView.swift`**
- Passes `contact.uid` to `ActivitySettingsView`
- Starts/stops the contact preferences listener alongside existing listeners

**`Views/Activities/MatchesLandingView.swift`**
- Removed settings gear button — per-contact settings require a selected contact

**`firebase/rules/firestore.rules`**
- Added `match /contactActivityPreferences/{prefId}` rule block (owner-only access)

**Cloud Functions:** No changes needed — `checkForMatches` does not read preferences.

### How It Works

1. Select a contact → tap gear → toggle activities for *that* contact → Done
2. `getEffectiveActivities(for:)` computes the mutual list using both users' per-contact prefs
3. If no per-contact pref exists for a given activity, the legacy global pref is used as a fallback
4. If neither exists, the activity defaults to enabled
