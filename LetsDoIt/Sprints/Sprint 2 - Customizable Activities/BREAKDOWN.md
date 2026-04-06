# Sprint 2: Customizable Activities — Implementation Breakdown

**Estimated duration:** 1.5–2 weeks  
**Complexity:** MEDIUM  
**Key risk:** Cross-user reads for custom activity visibility, match system extension

---

## Overview

The app currently has a hardcoded 16-item activity catalog (`ActivityCatalog.swift`). Sprint 2 adds:
- **Toggle catalog items** on/off per user (preferences stored in Firestore)
- **Create custom activities** (emoji + label + category)
- **Per-contact visibility** for custom activities (e.g. spouse-only activities hidden from friends)
- **Effective activity list** per contact pair = intersection of both users' enabled + mutually visible activities
- **Match system update** so `checkForMatches` validates custom activity visibility before confirming a match

### Firestore Schema (New Collections)

```
users/{userId}/activityPreferences/{activityId}
  enabled: Bool         // default true for catalog items

users/{userId}/customActivities/{activityId}
  id, emoji, label, category, createdAt
  visibleTo: [uid1, uid2, ...]   // which contacts can see this
```

### Security Rules (Already Deployed — Sprint 1, Phase 1, Step 2)

Both collections already have rules in `firebase/rules/firestore.rules`, deployed during Sprint 1's Firebase setup (Step 2 explicitly pre-authored rules for future sprints):
- `activityPreferences` — owner read/write
- `customActivities` — owner read/write, plus `request.auth.uid in resource.data.visibleTo` for cross-user reads

No rules deployment is needed for this sprint.

### Cloud Function Change

**Important: Two separate Cloud Functions projects exist.**
- **Messaging functions** — `LetsDoIt/firebase/functions/index.js` (v1 API, Firestore triggers)
- **Match/notification functions** — `/hermGameTest/functions/index.js` (v2 API, `onSchedule`, `onDocumentCreated`)

Sprint 2 modifies only the **match functions** project at `/hermGameTest/functions/index.js`:
- **`checkForMatches`** — Must validate that custom activity IDs (`custom_*` prefix) are visible to both users before confirming a match. Currently only checks `itemId` equality.
- **`sendMatchNotification`** — Must resolve `custom_*` IDs to emoji/label from Firestore (currently uses hardcoded `ITEM_LABELS` map which only covers catalog items).

### Existing Assets to Reuse

- `MultiContactPickerView.swift` — built in Sprint 1 (Phase 2, Step 7) for messaging, reuse as-is for per-contact visibility selection
- `ActivityRow.swift` — currently renders `ActivityItem`, will be adapted to render any `ActivityDisplayable`
- `ActivityCatalog.swift` — static catalog, stays as-is (read-only reference)

### Patterns Established in Sprint 1 (Must Follow)

These patterns were set during Sprint 1's Phase 1 and must be followed for consistency:

1. **Pure Swift models** (Sprint 1, Step 3) — Models use `Date` not `Timestamp`, no `FirebaseFirestore` import. The service layer handles `Date` ↔ `Timestamp` conversion on read/write.

2. **Singleton service pattern** (Sprint 1, Step 4) — `@MainActor class ActivityManager: ObservableObject` with `static let shared`, `@Published` arrays for reactive UI, real-time listeners managed with `ListenerRegistration`. Same as `ContactManager.shared`, `MessagingManager.shared`.

3. **Activity tab navigation** (Sprint 1, Step 1) — `ActivityTabView` has a `NavigationStack` with two states: landing page (no contact) and contact-selected view. The landing page uses `fullScreenCover` for contacts and `sheet` for modals. Settings access via toolbar must work in **both** states (landing and contact-selected).

4. **Error types in service file** (Sprint 1, Step 4) — Error enums defined at bottom of the service file with `LocalizedError` conformance (e.g. `ActivityManagerError`).

---

## Phase 1: Data Layer & Service (Steps 1–3)

Build the models, protocol, and service that all UI depends on.

### Step 1: ActivityDisplayable Protocol & CustomActivity Model

**Goal:** Create a shared protocol so both catalog items and custom activities render uniformly, plus the CustomActivity model.

**New files:**
- `Models/CustomActivity.swift` — `CustomActivity` struct (Codable, Identifiable, Hashable) with fields: `id`, `emoji`, `label`, `category` (ActivityCategory), `createdAt` (Date?), `visibleTo: [String]`. **Pure Swift — no FirebaseFirestore import.** Uses `Date` not `Timestamp`, following the pattern from Sprint 1 Step 3.

**Modified files:**
- `Models/ActivityItem.swift` — Add `ActivityDisplayable` protocol with `id`, `emoji`, `label`, `category` properties. Conform both `ActivityItem` and `CustomActivity` to it.

**Why protocol:** `ActivityListView`, `ActivityRow`, and `MatchHistoryView` all need to render both types without caring which one they have. A protocol is cleaner than a wrapper enum because both types are simple value types with the same display fields.

---

### Step 2: ActivityManager Service

**Goal:** Central service for preferences CRUD, custom activity CRUD, and effective activity list computation.

**New files:**
- `Services/ActivityManager.swift` — `@MainActor class ActivityManager: ObservableObject` (singleton `.shared`)

**Follows Sprint 1 service pattern exactly:**
- `@MainActor class ActivityManager: ObservableObject` with `static let shared = ActivityManager()`
- `@Published` arrays for `customActivities`, `preferences`
- `private let db = Firestore.firestore()`
- `private var listener: ListenerRegistration?` for real-time updates
- `Date` ↔ `Timestamp` conversion in read/write methods (not in models)
- `ActivityManagerError` enum at file bottom with `LocalizedError` conformance

**Responsibilities:**
1. **Preferences** — `activityPreferences/{activityId}` CRUD
   - `loadPreferences()` — fetch all preference docs, default to enabled for catalog items with no doc
   - `togglePreference(activityId:)` — set enabled true/false
   - `isEnabled(_ activityId: String) -> Bool`

2. **Custom Activities** — `customActivities/{activityId}` CRUD
   - `createCustomActivity(emoji:label:category:visibleTo:)` — ID prefixed with `custom_`
   - `updateCustomActivity(_:)` — update fields
   - `deleteCustomActivity(id:)` — delete doc
   - `loadMyCustomActivities()` — real-time listener on own custom activities
   - `fetchVisibleCustomActivities(from uid:)` — one-time fetch of another user's custom activities where current user is in `visibleTo`

3. **Effective Activity List** — the key computation
   - `getEffectiveActivities(for contactUid: String) -> [any ActivityDisplayable]`
   - Logic: take my enabled catalog items + my custom activities visible to this contact, intersect with their enabled catalog items + their custom activities visible to me
   - Returns the union of mutually visible items, sorted by category then label

---

### Step 3: Update checkForMatches Cloud Function

**Goal:** Prevent matches on custom activities where visibility isn't mutual.

**Modified files:**
- `/hermGameTest/functions/index.js` — update `checkForMatches` and `sendMatchNotification`

**Important:** This is the **match/notification functions project** (v2 API with `onSchedule`), NOT the messaging functions project at `LetsDoIt/firebase/functions/index.js` (v1 API with Firestore triggers). They are separate Firebase deployments.

**Changes to `checkForMatches`:**
When `itemId` starts with `custom_`, before confirming a match:
1. Read `users/{userA}/customActivities/{itemId}` — check `visibleTo` includes `userB`
2. Read `users/{userB}/customActivities/{itemId}` — check `visibleTo` includes `userA`
3. A custom activity match requires **at least one** user to own the activity with the other in `visibleTo` (since both users selected the same `itemId`, and they can only select items visible to them)
4. Skip the match (continue to next selection) if visibility check fails

**Changes to `sendMatchNotification`:**
- Currently uses hardcoded `ITEM_LABELS[itemId]` which only covers the 16 catalog items
- Add fallback: if `itemId` starts with `custom_`, fetch the custom activity doc from either user's collection to get `emoji` and `label` for the notification body
- Default to `{ emoji: "🎯", label: itemId }` if the doc can't be found (already the existing fallback behavior)

---

## Phase 2: Settings & Management UI (Steps 4–6)

Build the screens for managing preferences and custom activities.

### Step 4: Activity Settings View

**Goal:** Screen to toggle catalog items on/off and access custom activity management.

**New files:**
- `Views/Activities/ActivitySettingsView.swift`

**UI layout:**
- Section: "Catalog Activities" — List of all `ActivityCatalog.items` with toggle switches, grouped by category
- Section: "My Custom Activities" — List of user's custom activities with swipe-to-delete, tap to edit
- Button: "Create Custom Activity" — navigates to create form
- Navigation: accessible from Activity tab (gear icon in toolbar)

---

### Step 5: Create & Edit Custom Activity Views

**Goal:** Forms for creating and editing custom activities.

**New files:**
- `Views/Activities/CreateCustomActivityView.swift` — form with emoji picker, label text field, category picker, contact visibility picker (using `MultiContactPickerView`)
- `Views/Activities/EditCustomActivityView.swift` — same form pre-filled with existing values, save updates
- `Views/Activities/EmojiPickerView.swift` — grid of commonly used emojis by category (food, sports, objects, etc.) with search

**Validation:**
- Emoji: required, single emoji character
- Label: required, 1–50 characters
- Category: required, one of `ActivityCategory.allCases`
- VisibleTo: at least one contact selected

---

### Step 6: Integrate Settings into Activity Tab

**Goal:** Wire up the settings view and add navigation from the Activity tab.

**Modified files:**
- `Views/ActivityTabView.swift` — Add toolbar gear icon that presents `ActivitySettingsView`

**Activity tab structure context (from Sprint 1, Step 1):**
`ActivityTabView` has a `NavigationStack` with two view states:
- `landingView` — shown when `contactManager.selectedContact == nil` (has "View Contacts" button, uses `fullScreenCover` and `sheet` modals)
- `contactSelectedView(contact:)` — shown when a contact is selected (shows `ActivityListView`)

The gear icon must appear in the toolbar in **both** states. Use `.sheet` to present `ActivitySettingsView` (consistent with existing modal pattern in the tab — `fullScreenCover` is reserved for the contacts picker).

**No other UI changes yet** — the actual activity list integration happens in Phase 3.

---

## Phase 3: Activity List Integration & Match History (Steps 7–8)

Replace the hardcoded catalog with the effective activity list.

### Step 7: Update ActivityListView

**Goal:** Replace `ActivityCatalog.grouped` with `ActivityManager.getEffectiveActivities(for:)`.

**Modified files:**
- `Views/ActivityListView.swift`
  - Inject `@StateObject ActivityManager.shared`
  - Call `getEffectiveActivities(for: contactUid)` to get the list
  - Group results by category for sectioned display
  - `ActivityRow` already works if items conform to `ActivityDisplayable`
  - Handle loading state while fetching the other user's visible activities
  - Custom activity selections use `custom_` prefixed IDs in Firestore selections

**Modified files:**
- `Views/ActivityRow.swift` — Accept `any ActivityDisplayable` instead of `ActivityItem` (should be a minimal change since the protocol exposes the same fields)

---

### Step 8: Update MatchHistoryView

**Goal:** Custom activity matches show correct emoji/label instead of being silently dropped.

**Modified files:**
- `Views/MatchHistoryView.swift`
  - Currently looks up `ActivityCatalog.items.first(where:)` — misses `custom_*` IDs
  - Add fallback: if catalog lookup fails and ID starts with `custom_`, fetch the custom activity doc from either user's collection
  - Cache fetched custom activities to avoid repeated reads within the same history load

---

## Phase 4: Testing & Polish (Step 9)

### Step 9: Integration Testing

**Goal:** End-to-end verification with two simulator accounts.

**Test cases:**
1. Toggle catalog item off — verify it disappears from activity list for all contacts
2. Toggle catalog item back on — verify it reappears
3. Create custom activity visible to Contact B — verify it appears in B's activity list when matching with you
4. Verify custom activity does NOT appear for Contact C (not in visibleTo)
5. Both users select same custom activity — verify match fires via `checkForMatches`
6. User A selects custom activity, User B can't see it — verify NO match
7. Edit custom activity (change label/emoji) — verify updates reflect in activity list
8. Delete custom activity — verify it disappears from all lists
9. Match history shows custom activity matches with correct emoji/label
10. New user with no preferences — verify all catalog items default to enabled (no upfront data creation)

**Firestore verification:**
- `activityPreferences` docs created/updated on toggle
- `customActivities` docs have correct `visibleTo` arrays
- Selections with `custom_*` IDs are created correctly
- `checkForMatches` respects visibility (check function logs)

---

## Deliverables Checklist

- [x] `ActivityDisplayable` protocol unifying catalog + custom items
- [x] `CustomActivity` model
- [x] `ActivityManager` service (preferences, custom CRUD, effective list computation)
- [x] `checkForMatches` updated for custom activity visibility
- [x] Activity settings screen with catalog toggles
- [x] Create/edit custom activity forms with emoji picker
- [x] Per-contact visibility via `MultiContactPickerView`
- [x] `ActivityListView` uses effective activity list per contact
- [x] `MatchHistoryView` resolves custom activity matches
- [x] Firestore security rules verified (already deployed)
- [x] Integration tested with two accounts
- [x] Match landing page with real-time match list
- [x] Match detail view with "Message" button → DM creation with prefilled text

---

## Files Summary

### New Files (~7)

| File | Step | Purpose |
|------|------|---------|
| `Models/CustomActivity.swift` | 1 | CustomActivity struct + Codable |
| `Services/ActivityManager.swift` | 2 | Preferences, custom activities, effective list |
| `Views/Activities/ActivitySettingsView.swift` | 4 | Catalog toggles + custom activity management |
| `Views/Activities/CreateCustomActivityView.swift` | 5 | Create form with emoji picker + visibility |
| `Views/Activities/EditCustomActivityView.swift` | 5 | Edit form pre-filled |
| `Views/Activities/EmojiPickerView.swift` | 5 | Emoji grid selector |
| `Sprints/Sprint 2 - Customizable Activities/BREAKDOWN.md` | — | This document |

### Modified Files (~6)

| File | Step | Change |
|------|------|--------|
| `Models/ActivityItem.swift` | 1 | Add `ActivityDisplayable` protocol |
| `/hermGameTest/functions/index.js` | 3 | `checkForMatches` validates custom activity visibility; `sendMatchNotification` resolves `custom_*` IDs from Firestore ✅ |
| `Views/ActivityTabView.swift` | 6 | Toolbar gear icon → settings ✅ (pre-wired in Step 5) |
| `Views/ActivityListView.swift` | 7 | Use `ActivityManager.getEffectiveActivities(for:)` |
| `Views/ActivityRow.swift` | 7 | Accept `any ActivityDisplayable` |
| `Views/MatchHistoryView.swift` | 8 | Resolve `custom_*` IDs |

---

## Key Decisions

1. **Protocol over enum for activity types** — Both `ActivityItem` and `CustomActivity` are simple value types with identical display fields. A protocol keeps rendering code clean without wrapper overhead.

2. **`custom_` prefix for IDs** — Distinguishes custom from catalog at the data layer. The matcher, history view, and notification system all use this prefix to decide whether a catalog lookup or Firestore fetch is needed.

3. **Catalog items default enabled** — No Firestore docs created for new users. A missing `activityPreferences/{id}` doc means "enabled." Only toggling off creates a doc. This avoids seeding 16 docs per new user.

4. **Effective list computed client-side** — Requires two reads (my prefs + contact's visible customs), but avoids a Cloud Function for every list render. The security rule allows cross-user reads only for items where the reader is in `visibleTo`.

5. **Reuse MultiContactPickerView** — Already built and tested in Sprint 1. Used as-is for the `visibleTo` selection in create/edit custom activity forms.

6. **Match validation in existing function** — Adding visibility checks to `checkForMatches` (not creating a new function) keeps the match system as a single scheduled scan. The additional reads only happen for `custom_*` IDs.

---

## Implementation Order

Recommended: **Phase 1 → Phase 2 → Phase 3 → Phase 4**, steps sequential within each phase.

Phase 1 builds the data layer everything depends on. Phase 2 builds the management UI (settings, create/edit). Phase 3 wires the effective activity list into the existing views. Phase 4 is integration testing.

Within Phase 1: Step 1 (protocol + model) before Step 2 (service that uses them) before Step 3 (Cloud Function that validates them).

Within Phase 2: Step 4 (settings list) before Step 5 (create/edit forms it navigates to) before Step 6 (wiring into Activity tab).

---

## Workflow Format — ALL Implementation Sessions Must Follow This

Every implementation task must follow this exact format:

1. **Plan** — Read the step's requirements and context files. Present a concrete implementation plan (specific files to create/modify, API design, key decisions) before writing any code.
2. **Present & confirm** — Wait for explicit user approval before implementing.
3. **Implement** — Create/modify files. Follow existing code conventions from the project.
4. **Verify** — For Swift changes: run `xcodebuild -scheme LetsDoIt -destination 'platform=iOS Simulator,name=iPhone 17' build` and confirm BUILD SUCCEEDED. For Cloud Function changes (Step 3): verify syntax with `node --check /Users/adamgrow/hermGameTest/functions/index.js`. Fix any errors.
5. **Document** — Create a step implementation log in `Sprints/Sprint 2 - Customizable Activities/` named `Phase X - Step Y - [Name].md`, matching the format of Sprint 1's logs. Update this breakdown file to mark the step complete.
6. **Commit handoff** — End by asking the user to commit locally, and provide the list of changed files. Then give the user a ready-to-paste prompt for a fresh session to handle the next step. The prompt must include:
   - The project path (/Users/adamgrow/hermGameTest/LetsDoIt)
   - Which context files to re-read at the start of the next session
   - The specific next step to work on
   - A reminder of this workflow format (Plan -> Present & confirm -> Implement -> Verify -> Document -> Commit handoff)

IMPORTANT: The commit handoff prompt for the next step must be given as plain text only. Do NOT use markdown formatting (no code fences, no bold, no backticks, no lists) in the prompt block. It must be raw plain text that the user can copy and paste directly into a new chat.

### Implementation Log Format (reference)

Each implementation log must match the structure of Sprint 1's Phase 1 logs. See these files for the exact format:
- `Sprints/Sprint 1 - Messaging/Phase 1 - Step 3 - Data Models.md`
- `Sprints/Sprint 1 - Messaging/Phase 1 - Step 4 - MessagingManager.md`

Required sections in each log:
- Title, date, build status badge (✅ Complete — BUILD SUCCEEDED)
- "What Was Done" — tables of new/modified files
- Detailed section per file/service with property/method tables
- "Architecture Decisions" — numbered list of design rationale
- "Build Verification" — the exact build/check command and result

### Context Files for Each Step

Steps should read these files before planning:

| Step | Must Read |
|------|-----------|
| 1 | `Models/ActivityItem.swift`, `Models/ActivityCatalog.swift`, `Sprints/Sprint 2 - Customizable Activities/BREAKDOWN.md` |
| 2 | `Services/ContactManager.swift` (singleton pattern reference), `Services/MessagingManager.swift` (singleton pattern reference), `Models/CustomActivity.swift` (from Step 1) |
| 3 | `/hermGameTest/functions/index.js` (the match functions project — NOT `LetsDoIt/firebase/functions/index.js`) |
| 4 | `Views/Activities/` (from Steps 1–2), `Services/ActivityManager.swift` (from Step 2), `Models/ActivityCatalog.swift` |
| 5 | `Views/Messaging/MultiContactPickerView.swift` (reuse for visibility picker), `Views/Activities/ActivitySettingsView.swift` (from Step 4) |
| 6 | `Views/ActivityTabView.swift` (dual-state navigation structure), `Views/Activities/ActivitySettingsView.swift` (from Step 4) |
| 7 | `Views/ActivityListView.swift`, `Views/ActivityRow.swift`, `Services/ActivityManager.swift` (from Step 2), `Services/ContactManager.swift` (for `selectedContact`) |
| 8 | `Views/MatchHistoryView.swift`, `Services/ActivityManager.swift` (from Step 2) |
| 9 | All files from Steps 1–8, `Sprints/Sprint 1 - Messaging/Phase 4 - Step 13 - Integration Testing.md` (format reference) |
