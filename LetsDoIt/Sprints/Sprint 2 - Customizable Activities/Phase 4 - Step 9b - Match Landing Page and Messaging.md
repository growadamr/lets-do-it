# Phase 4, Step 9b: Match Landing Page and Messaging Integration

**Date:** 2026-04-06
**Status:** ✅ Complete — BUILD SUCCEEDED

---

## What Was Done

### New Files Created

| File | Purpose |
|------|---------|
| `Services/MatchManager.swift` | Singleton service: real-time listener for `matched: true` selections across all contacts. Publishes `@Published var matches: [Match]` for UI consumption. |
| `Views/Activities/MatchesLandingView.swift` | Landing page for Activity tab when no contact is selected. Shows match list (like Messages conversation list) or "Let's do it!" empty state. |
| `Views/Activities/MatchDetailView.swift` | Sheet for a single match — shows activity details, contact name, and "Message [Contact]" button that creates/finds a DM and navigates to Messages tab with prefilled text. |

### Files Modified

| File | Change |
|------|--------|
| `Views/ActivityTabView.swift` | Replaced static `landingView` with `MatchesLandingView`. Added `MatchManager.shared` listener lifecycle (`startListening`/`stopListening`). Cleaned up unused state variables (`showingContacts`, `showCreateCode`, `showJoinCode`). Removed `showingContacts` flag from `contactSelectedView` conditional. |
| `Services/ActivityManager.swift` | Fixed `getEffectiveActivities(for:)` — changed custom activities from **intersection** to **union**. Previously required both users to own the same custom activity (always empty). Now shows any custom activity where the creator has the viewer in `visibleTo`. |
| `Services/MatchManager.swift` (listener) | Moved listener start/stop from `ActivitySettingsView` to `ActivityTabView.task`/`.onDisappear`. Changed `ActivityListView`, `ActivitySettingsView`, `CreateCustomActivityView`, `EditCustomActivityView` from `@StateObject` → `@ObservedObject` for consistent singleton ownership. |
| `Services/DeepLinkRouter.swift` | Added `openConversationWithMessage` notification name. Added `ChatPrefillStore` singleton for keyed prefilled message storage (consume-once pattern). |
| `Views/Messaging/ChatView.swift` | Added optional `prefilledMessage: String?` parameter. `.task` block checks `ChatPrefillStore` first, then falls back to `prefilledMessage` parameter. Only fills if `messageText` is empty. |
| `Views/MessagesTabView.swift` | Added `.onReceive` for `openConversationWithMessage` notification — appends `conversationId` to navPath. Removed persistent `@State prefilledMessage` (replaced by `ChatPrefillStore`). |
| `Views/HomeView.swift` | Added `.onReceive` for `openConversationWithMessage` — switches to Messages tab (tag 1). |
| `firebase/firestore.indexes.json` | Added composite index for `pendingNotifications` collection (`sent` ASC + `sendAt` ASC). Required for `sendPendingNotifications` Cloud Function. |

---

## Bug Fixes

### B1: Custom Activities Never Appeared in Activity List

**Root cause:** `getEffectiveActivities(for:)` used an **intersection** of custom activity IDs between the two users. Since only one user creates a custom activity, the intersection was always empty.

**Fix:** Changed to **union** with deduplication. A custom activity appears if the creator has the viewer in `visibleTo`.

```swift
// Before (wrong):
let mutualCustomIds = myCustomIds.intersection(theirCustomIds)
let mutualCustoms = myVisibleCustoms.filter { mutualCustomIds.contains($0.id) }

// After (correct):
var seenCustomIds = Set<String>()
var mutualCustoms: [any ActivityDisplayable] = []
for activity in myVisibleCustoms + contactVisibleCustoms {
    if !seenCustomIds.contains(activity.id) {
        seenCustomIds.insert(activity.id)
        mutualCustoms.append(activity)
    }
}
```

### B2: ActivityManager Listeners Only Started in ActivitySettingsView

**Root cause:** `startListeningCustomActivities()` and `startListeningPreferences()` were called only in `ActivitySettingsView.task`. When a user opened the Activity tab without first opening Settings, `ActivityManager.customActivities` was empty → `getEffectiveActivities` returned nothing.

**Fix:** Moved listener lifecycle to `ActivityTabView.task`/`.onDisappear` — the root of the Activity tab. All sub-views (`ActivityListView`, `ActivitySettingsView`, `CreateCustomActivityView`) now benefit from a single shared listener. Changed `@StateObject` → `@ObservedObject` in child views for correct ownership semantics.

### B3: No In-App Match Awareness

**Root cause:** Match detection was entirely server-side → FCM push. There was no client-side listener or UI to show matched activities. `MatchHistoryView` existed but was never presented anywhere in the app.

**Fix:** Created `MatchManager` (real-time listener on `matched: true` selections) and `MatchesLandingView` (replaces the static "Let's do it!" landing page). Matches now appear as a scrollable list on the Activity tab's landing page, similar to the Messages conversation list.

### B4: `sendPendingNotifications` Crashed Every Minute

**Root cause:** The `pendingNotifications` collection was missing a composite index (`sent` + `sendAt`). The `sendPendingNotifications` Cloud Function queried `where("sent", "==", false).where("sendAt", "<=", now)` — Firestore requires a composite index for multi-field equality/inequality queries.

**Fix:** Added index to `firestore.indexes.json` and deployed via Firebase Console.

---

## Architecture Decisions

1. **`MatchManager` as separate singleton** — Follows the established Sprint 1 service pattern (like `ContactManager`, `MessagingManager`, `ActivityManager`). `@MainActor` with `@Published` for reactive SwiftUI, `startListening`/`stopListening` lifecycle. Keeps match logic separate from activity management.

2. **Union (not intersection) for custom activities** — A custom activity should appear in the effective list if the creator has the contact in `visibleTo`. Unlike catalog items (which require mutual enablement), custom activities are owned by one user and shared with specific contacts. The union approach also handles the edge case where both users independently create custom activities with the same ID (deduplicated by `seenCustomIds`).

3. **`ChatPrefillStore` keyed by conversation ID** — Avoids the race condition of passing prefilled messages through `@State` on `MessagesTabView` (which persisted and leaked into unrelated chats). The store is set-once, consumed-once, and scoped to a specific conversation. After consumption, the entry is deleted.

4. **Notification-based cross-tab navigation** — `MatchDetailView` posts `openConversationWithMessage` with the `conversationId` in `userInfo`. `HomeView` switches to the Messages tab, and `MessagesTabView` handles the navigation. This decouples the Activity tab from the Messages tab's internal navigation state.

5. **6-hour match window** — `MatchManager` filters out matches older than 6 hours during document processing. This keeps the landing page focused on recent matches without requiring Firestore cleanup of old `matched: true` selection documents.

6. **MatchManager deduplication by composite key** — Each match produces two selection documents (one per user, both `matched: true`). Deduplication uses `itemId_timestamp` as a key to avoid showing duplicate rows for the same match event.

---

## Match Flow (End-to-End)

1. User A creates a custom activity with User B in `visibleTo`
2. Custom activity appears in both users' activity lists (via `ActivityManager` listeners + `getEffectiveActivities` union)
3. Both users select the same activity
4. `checkForMatches` Cloud Function (every 5 min) detects the match
5. `sendPendingNotifications` Cloud Function (every 1 min) logs the match notification
6. `MatchManager` real-time listener picks up `matched: true` on the selection docs
7. `MatchesLandingView` refreshes — new match row appears
8. User taps match → `MatchDetailView` shows details + "Message [Name]" button
9. User taps "Message" → creates/finds DM, stores prefilled message in `ChatPrefillStore`, switches to Messages tab
10. `ChatView` opens with prefilled text: "Want to [activity label]? [emoji]"

---

## Build Verification

```bash
xcodebuild -scheme LetsDoIt -destination 'platform=iOS Simulator,name=iPhone 17' build
```

**Result:** BUILD SUCCEEDED
