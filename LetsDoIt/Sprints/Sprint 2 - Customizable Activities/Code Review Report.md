# Sprint 2: Customizable Activities — Code Review Report

**Date:** April 6, 2026
**Reviewer:** Qwen Code
**Scope:** Full code review of all Sprint 2 deliverables against BREAKDOWN.md requirements

---

## Executive Summary

Sprint 2 is **well-implemented and meets all BREAKDOWN.md requirements**. The architecture is clean, security rules are correct, and the end-to-end match → message flow works as specified.

**Findings:** 1 medium-severity functional bug (emoji search), 2 medium-severity convention issues, and 5 low-priority items. No high-severity or blocking issues.

| Category | Count |
|----------|-------|
| ✅ Requirements satisfied | 8/8 |
| 🔴 High-severity issues | 0 |
| 🟡 Medium-severity issues | 3 |
| 🟢 Low-priority items | 5 |

---

## Requirement Validation

### 1. ActivityDisplayable Protocol ✅ PASS

**Files reviewed:** `Models/ActivityItem.swift`, `Models/CustomActivity.swift`

| Check | Result | Notes |
|-------|--------|-------|
| Protocol exposes `id`, `emoji`, `label`, `category` | ✅ | Read-only `get` requirements — correct for immutable `let` properties |
| `ActivityItem` conforms | ✅ | Trivial conformance — all 4 properties already existed |
| `CustomActivity` conforms | ✅ | Additional fields (`createdAt`, `visibleTo`) don't affect rendering |
| `Hashable` based on `id` only | ✅ | Correct for deduplication in effective activity list |
| `Codable` synthesized | ✅ | `ActivityCategory` made `Codable` (String-backed enum — raw value serialization) |
| No `FirebaseFirestore` import in models | ✅ | Pure Swift — `Date` not `Timestamp` |

**Assessment:** Clean implementation. Protocol unifies catalog items and custom activities without coupling rendering code to either type.

---

### 2. Effective Activity List Computation ✅ PASS

**File reviewed:** `Services/ActivityManager.swift` — `getEffectiveActivities(for:)`

**Logic verified step-by-step:**

| Step | Expected | Implemented | Match |
|------|----------|-------------|-------|
| 1. My enabled catalog items | Filter by `isEnabled($0.id)`, missing pref = enabled | `ActivityCatalog.items.filter { isEnabled($0.id) }` | ✅ |
| 2. My custom activities visible to contact | Filter by `visibleTo.contains(contactUid)` | `customActivities.filter { $0.visibleTo.contains(contactUid) }` | ✅ |
| 3. Contact's enabled catalog items | Fetch their prefs, invert disabled set | `getDocuments()` → build `contactDisabled` set → filter | ✅ |
| 4. Contact's custom activities visible to me | `arrayContains` query on `visibleTo` | `fetchVisibleCustomActivities(for: contactUid)` | ✅ |
| 5. Catalog intersection | Both must enable | `myEnabledIds.intersection(contactEnabledIds)` | ✅ |
| 6. Custom activities union | Either side owns it, deduplicated | `myVisibleCustoms + contactVisibleCustoms` with `seenCustomIds` | ✅ |
| 7. Sort by category order then label | `ActivityCategory.allCases` order | `categoryOrder` dict → sort by order, then `label` | ✅ |

**Race condition note:** The `customActivities` `@Published` array is populated by a real-time listener. If `getEffectiveActivities` is called before the listener fires, `customActivities` will be empty. **Mitigation:** `ActivityTabView.task` starts listeners before sub-views render. In practice the listener fires quickly. **Severity:** Low — acceptable at current scale.

---

### 3. Custom Activity CRUD ✅ PASS

**File reviewed:** `Services/ActivityManager.swift` + view layer

| Operation | Method | Firestore Behavior | Verified |
|-----------|--------|--------------------|----------|
| **Create** | `createCustomActivity(emoji:label:category:visibleTo:)` | `custom_<uuid>` doc ID, `Timestamp(date:)` for createdAt | ✅ |
| **Update** | `updateCustomActivity(_:)` | `setData(_:merge: true)` — safe for partial updates | ✅ |
| **Delete** | `deleteCustomActivity(id:)` | `ref.delete()` | ✅ |
| **Real-time listen** | `startListeningCustomActivities()` | Ordered by `createdAt` ASC, proper deserialization | ✅ |
| **Cross-user fetch** | `fetchVisibleCustomActivities(for:)` | `arrayContains` query + security rule gate | ✅ |

**UI layer:**
- `CreateCustomActivityView` — validation: emoji required, label 1–50 chars, ≥1 contact. Uses `MultiContactPickerView`. ✅
- `EditCustomActivityView` — `@State` vars initialized in `init(activity:)`. Correct pattern. ✅
- `ActivitySettingsView` — swipe-to-delete, tap-to-edit via `.sheet`, `NavigationLink` for create. ✅

---

### 4. Per-Contact Visibility (visibleTo) ✅ PASS

**Three layers of enforcement:**

| Layer | Mechanism | Verified |
|-------|-----------|----------|
| **Firestore Security Rules** | `allow read: if isOwner(userId) \|\| (isAuthenticated() && request.auth.uid in resource.data.visibleTo)` | ✅ |
| **Client-side service** | `fetchVisibleCustomActivities` uses `arrayContains` query; `getEffectiveActivities` filters by `visibleTo.contains(contactUid)` | ✅ |
| **Cloud Function (match validation)** | `checkCustomActivityVisibility` checks both directions before confirming match | ✅ |

**Defense-in-depth confirmed.** Even if one layer fails, the others block unauthorized access.

---

### 5. Match Landing Page (6-Hour Window, Real-Time) ✅ PASS

**Files reviewed:** `Services/MatchManager.swift`, `Views/Activities/MatchesLandingView.swift`

| Check | Result | Notes |
|-------|--------|-------|
| Real-time listener on `matched: true` selections | ✅ | `whereField("matched", isEqualTo: true)` |
| 6-hour prune | ✅ | `if createdAt.dateValue() < sixHoursAgo { continue }` |
| Deduplication by composite key | ✅ | `itemId_timestamp` per contact |
| Activity details resolved via `ActivityManager` | ✅ | `resolveActivityDetails(itemId:contactUid:)` |
| Sorted by date descending | ✅ | `allMatches.sorted { $0.date > $1.date }` |
| Empty state with "View Contacts" | ✅ | `MatchesLandingView` shows "Let's do it!" when no matches |
| Gear icon in toolbar | ✅ | Presents `ActivitySettingsView` via `.sheet` |
| Tap match → detail sheet | ✅ | `MatchDetailView` with activity info, contact name, message button |

**Nit:** `@StateObject private var matchManager = MatchManager.shared` — should be `@ObservedObject` since the singleton owns itself. No functional impact, but inconsistent with `@ObservedObject var activityManager` pattern in child views.

---

### 6. MatchDetailView "Message" Button → DM + Prefill ✅ PASS

**Files reviewed:** `Views/Activities/MatchDetailView.swift`, `Services/DeepLinkRouter.swift`, `Views/Messaging/ChatView.swift`, `Views/MessagesTabView.swift`, `Views/HomeView.swift`

**End-to-end flow verified:**

| Step | Component | Behavior | Verified |
|------|-----------|----------|----------|
| 1 | `MatchDetailView.startConversation()` | Creates/finds DM via `MessagingManager.createDM(with:)` | ✅ |
| 2 | `ChatPrefillStore.shared.set(message, for: convId)` | Stores suggested message | ✅ |
| 3 | `NotificationCenter.post(name: .openConversationWithMessage)` | Posts with `userInfo["id"] = conversationId` | ✅ |
| 4 | `HomeView` receives notification | Switches to Messages tab (`selectedTab = 1`) | ✅ |
| 5 | `MessagesTabView` receives notification | Appends `conversationId` to `navPath` | ✅ |
| 6 | `ChatView.task` consumes prefill | `ChatPrefillStore.shared.consume(for:)` → sets `messageText` | ✅ |
| 7 | Guard: only fills if `messageText.isEmpty` | Prevents overwriting user input | ✅ |

**Suggested message format:** `"Want to \(match.label.lowercased())? \(match.emoji)"` — correct.

**ChatPrefillStore:** Set-once, consume-once, keyed by conversation ID. Race-condition safe. ✅

---

### 7. 6-Hour Prune in MatchManager ✅ PASS

```swift
let sixHoursAgo = Date().addingTimeInterval(-6 * 60 * 60)
if createdAt.dateValue() < sixHoursAgo { continue }
```

This is a **read-time filter** — old `matched: true` selection documents remain in Firestore but are excluded from the published matches array. This is correct behavior:
- Keeps the landing page focused on recent matches.
- `MatchHistoryView` provides the full historical record.
- No Firestore cleanup needed (document count is small at current scale).

**Future consideration:** Old `matched: true` documents are never cleaned. At scale, the listener reads increasingly more documents only to discard most. Not a concern now.

---

### 8. Security, Performance, and Architecture Assessment

#### Security Rules — ✅ PASS

`firebase/rules/firestore.rules` verified:

| Collection | Rule | Correct |
|------------|------|---------|
| `activityPreferences/{activityId}` | `allow read, write: if isOwner(userId)` | ✅ |
| `customActivities/{activityId}` | `allow read: if isOwner(userId) \|\| (isAuthenticated() && request.auth.uid in resource.data.visibleTo)` | ✅ |
| `customActivities/{activityId}` | `allow create, update, delete: if isOwner(userId)` | ✅ |

No unauthorized cross-user reads possible. Owner-only writes prevent tampering.

#### Cloud Function Visibility Check — ✅ PASS

`/hermGameTest/functions/index.js`:

| Function | Purpose | Verified |
|----------|---------|----------|
| `checkCustomActivityVisibility(userId, targetUserId, itemId)` | Validates custom activity match before confirming | ✅ |
| `resolveItemInfo(itemId, userAId, userBId)` | Resolves emoji+label for catalog and custom items in notifications | ✅ |
| `checkForMatches` — visibility insertion | `if (!isVisible) { continue }` before transaction | ✅ |
| `sendMatchNotification` — dynamic resolution | `await resolveItemInfo(...)` replaces hardcoded `ITEM_LABELS` lookup | ✅ |

Parallel Firestore reads via `Promise.all` — correct performance pattern.

---

## Issues Found

### 🟡 Medium Severity (3)

#### M1: EmojiPickerView Search Is Non-Functional

**File:** `Views/Activities/EmojiPickerView.swift`

**Bug:** The `filteredSections` computed property captures `searchText` from `.searchable` but never uses it to filter emoji:

```swift
private var filteredSections: [(category: String, emojis: [String])] {
    guard !searchText.isEmpty else { return emojiSections }
    return emojiSections.compactMap { section in
        let filtered = section.emojis  // ← No filtering applied
        return filtered.isEmpty ? nil : (section.category, filtered)
    }
}
```

The `compactMap` never returns `nil` (all sections have non-empty emoji arrays), so the search bar appears but returns all ~370 emojis regardless of input.

**Fix:** Add emoji filtering, e.g.:
```swift
let filtered = section.emojis.filter { emoji in
    emoji.contains(searchText) || // Unicode scalar match
    // Optional: add name-based search index
    true
}
```

**Impact:** Users expect search to work. Currently they must browse 8 categories manually.

---

#### M2: `@StateObject` Used for Singleton `MatchManager`

**File:** `Views/Activities/MatchesLandingView.swift`

```swift
@StateObject private var matchManager = MatchManager.shared
```

`@StateObject` implies ownership (initialization and lifecycle management). Since `MatchManager.shared` is a singleton that owns itself, `@ObservedObject` is the semantically correct wrapper — consistent with `@ObservedObject var activityManager = ActivityManager.shared` in `ActivityListView`, `ActivitySettingsView`, `CreateCustomActivityView`, and `EditCustomActivityView`.

**Impact:** No runtime bug (SwiftUI won't re-initialize a singleton), but inconsistent with the established pattern across the codebase.

---

#### M3: No Loading State During Async Activity Resolution in MatchManager

**File:** `Services/MatchManager.swift` — `processDocuments(_:)`

`resolveActivityDetails(itemId:contactUid:)` performs async Firestore reads (up to 2 document fetches per custom activity ID) inside `processDocuments`, which is called from the Firestore snapshot listener's `Task`. If many custom activity matches exist, the UI may appear to pause while awaiting Firestore, with no loading indicator.

**Impact:** Low at current scale (few matches), but could cause perceived hangs if match history grows. Consider adding a loading state or caching resolved details.

---

### 🟢 Low Priority (5)

#### L1: ActivityListView Doesn't Re-Fetch When Preferences Change

**File:** `Views/ActivityListView.swift`

`loadEffectiveActivities()` is called in `.task` (once on appearance) and via `refreshAll()` (timer + manual retry). The timer only refreshes selections (`AppConfig.selectionRefreshInterval`), not the effective activity list. If the user toggles a catalog preference in Settings, `@Published preferences` changes but `ActivityListView` doesn't react — the list only re-fetches on the 60-minute timer.

**Suggested fix:** Add `.onChange(of: activityManager.preferences)` or `.onChange(of: activityManager.customActivities)` to trigger `loadEffectiveActivities()`.

---

#### L2: MatchHistoryView Directly Accesses Firestore

**File:** `Views/MatchHistoryView.swift`

This view imports `FirebaseFirestore` and `FirebaseAuth` and queries Firestore directly, rather than going through `MatchManager` or a dedicated service. Not a bug — just architecturally inconsistent with the rest of the app (which uses manager services).

---

#### L3: Inconsistent Service Access Pattern in MatchesLandingView

**File:** `Views/Activities/MatchesLandingView.swift`

```swift
@StateObject private var matchManager = MatchManager.shared  // Should be @ObservedObject
@ObservedObject private var contactManager = ContactManager.shared  // Correct
```

Minor inconsistency — both should be `@ObservedObject` since both are singletons.

---

#### L4: EditCustomActivityView Preview Violates Validation Rule

**File:** `Views/Activities/EditCustomActivityView.swift`

```swift
#Preview {
    EditCustomActivityView(
        activity: CustomActivity(
            id: "preview_1",
            emoji: "🎯",
            label: "Preview Activity",
            category: .activities,
            createdAt: Date(),
            visibleTo: []  // ← Empty array violates ≥1 contact rule
        )
    )
}
```

Preview-only issue — no runtime impact. The preview renders with an empty `visibleTo` array, which would be rejected by the real form's validation.

---

#### L5: CustomActivity Model Allows Empty `visibleTo` at Type Level

**File:** `Models/CustomActivity.swift`

```swift
init(visibleTo: [String] = [])  // Default allows empty array
```

The model type allows `visibleTo: []`, but the business rule (enforced in UI) requires ≥1 contact. Validation is purely UI-layer — the service (`ActivityManager.createCustomActivity`) doesn't enforce this constraint.

**Suggested fix:** Add validation in `createCustomActivity` that throws `ActivityManagerError.invalidVisibleTo` (new case) if `visibleTo.isEmpty`.

---

## Architecture Strengths

1. **Protocol-driven design** — `ActivityDisplayable` cleanly unifies two types without coupling rendering code to either.

2. **Consistent singleton pattern** — `ActivityManager`, `MatchManager`, `ChatPrefillStore` all follow the `@MainActor class X: ObservableObject` + `static let shared` pattern established in Sprint 1.

3. **Defense-in-depth security** — Firestore rules + client-side queries + Cloud Function validation all enforce the `visibleTo` constraint independently.

4. **Pure Swift models** — `Date` not `Timestamp`, no `FirebaseFirestore` imports. Service layer handles conversion.

5. **Clean cross-tab navigation** — `NotificationCenter` + `ChatPrefillStore` decouples Activity tab from Messages tab internals. No tight coupling between tabs.

6. **Set-once, consume-once prefill store** — `ChatPrefillStore` prevents message leakage into unrelated conversations.

7. **Cloud Function parallel reads** — `Promise.all` for both users' collections minimizes latency in visibility checks and notification resolution.

---

## Test Results Summary (from Phase 4, Step 9)

| Category | Pass | Fail | Skipped |
|----------|------|------|---------|
| Catalog Toggle (1–2) | 2 | 0 | 0 |
| Custom Activity Visibility (3–4) | 1 | 0 | 1 (N/A — requires 3rd account) |
| Match Firing (5–6) | 2 | 0 | 0 |
| Edit & Delete (7–8) | 2 | 0 | 0 |
| Match History & Defaults (9–10) | 2 | 0 | 0 |
| Firestore Verification | 14 | 0 | 0 |
| Cloud Functions (CF1–CF4) | 4 | 0 | 0 |
| **Total** | **25** | **0** | **1** |

---

## Bugs Fixed During Sprint (from Integration Testing Log)

| ID | Bug | Severity | Fix |
|----|-----|----------|-----|
| B1 | Custom activities never appeared — `getEffectiveActivities` used intersection instead of union | High | Changed to union with deduplication |
| B2 | `ActivityManager` listeners only started in `ActivitySettingsView` | High | Moved to `ActivityTabView.task`/`.onDisappear` |
| B3 | No in-app match awareness — matches only detectable via FCM push | High | Created `MatchManager`, `MatchesLandingView`, `MatchDetailView` |
| B4 | `sendPendingNotifications` crashed — missing composite index | High | Added index to `firestore.indexes.json` |
| B5 | Swipe-to-delete didn't work — `NavigationLink` intercepts swipes | Medium | Replaced with `.onTapGesture` + `.sheet` |
| B6 | Stale `pendingNotifications` docs had invalid UIDs | Medium | Manually deleted orphaned docs |

---

## Recommendation

**Sprint 2 is approved for production.** All BREAKDOWN.md requirements are satisfied. The 3 medium-severity issues should be addressed in a follow-up patch:

1. **M1 (emoji search)** — Quick fix, ~5 lines. Improves UX significantly.
2. **M2 (@StateObject → @ObservedObject)** — One-word change. Consistency fix.
3. **M3 (loading state for async resolution)** — Optional at current scale. Add if match history grows beyond ~20 entries.

The 5 low-priority items are nice-to-haves. L1 (ActivityListView re-fetch on preference change) is the most impactful if users expect immediate feedback after toggling catalog items.
