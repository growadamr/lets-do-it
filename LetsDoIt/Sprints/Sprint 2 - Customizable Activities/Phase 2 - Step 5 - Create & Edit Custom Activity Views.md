# Phase 2, Step 5: Create & Edit Custom Activity Views — Implementation Log

**Date:** 2026-04-06
**Status:** ✅ Complete — BUILD SUCCEEDED

---

## What Was Done

### New Files Created

| File | Purpose |
|------|---------|
| `Views/Activities/EmojiPickerView.swift` | Grid-based emoji selector organized by 8 categories with search |
| `Views/Activities/CreateCustomActivityView.swift` | Form for creating a new custom activity with validation |
| `Views/Activities/EditCustomActivityView.swift` | Same form pre-filled with an existing activity's values for editing |

### Files Modified

| File | Change |
|------|--------|
| `Views/Activities/ActivitySettingsView.swift` | Uncommented `NavigationLink` for create/edit; replaced disabled button with `NavigationLink` to `CreateCustomActivityView` |

---

## View Details

### `EmojiPickerView`

```swift
struct EmojiPickerView: View
    let onEmojiSelected: (String) -> Void
```

| Component | Description |
|---|---|
| Layout | `List` with `LazyVGrid` (6 columns) per category section |
| Categories | Smileys & People, Activities & Sports, Food & Drink, Travel & Places, Nature, Objects, Symbols & Shapes |
| Search | `.searchable` modifier filters sections client-side |
| Selection | Tapping an emoji calls `onEmojiSelected` and auto-dismisses |
| Total emojis | ~370 across 8 categories |

### `CreateCustomActivityView`

```swift
struct CreateCustomActivityView: View
    var onComplete: ((CustomActivity) -> Void)?
```

| Section | Fields |
|---|---|
| Activity | Emoji picker button, label `TextField`, category `Picker` (`.menu` style) |
| Visible To | Contact count button → presents `MultiContactPickerView` sheet |
| Validation | Save button disabled until: emoji ≠ empty, label 1–50 chars, ≥1 contact selected |

**Validation rules:**
- Emoji: required, single emoji character (picked from `EmojiPickerView`)
- Label: required, trimmed, 1–50 characters
- Category: required, one of `ActivityCategory.allCases`
- VisibleTo: at least one contact UID required

**Save flow:** Calls `ActivityManager.createCustomActivity(emoji:label:category:visibleTo:)`, receives the created `CustomActivity` back, calls `onComplete` callback, then dismisses.

### `EditCustomActivityView`

```swift
struct EditCustomActivityView: View
    let activity: CustomActivity
    var onComplete: (() -> Void)?
```

| Property | Init behavior |
|---|---|
| `selectedEmoji` | Pre-filled from `activity.emoji` |
| `label` | Pre-filled from `activity.label` |
| `selectedCategory` | Pre-filled from `activity.category` |
| `visibleToUids` | Pre-filled from `activity.visibleTo` |

**Same validation as CreateCustomActivityView.**

**Save flow:** Constructs a new `CustomActivity` with the original `id` and `createdAt`, updated fields, and calls `ActivityManager.updateCustomActivity(_:)`. Dismisses on success.

### `ActivitySettingsView` Changes

| Before | After |
|---|---|
| Custom activity rows were `HStack` with `.disabled(true)` | Rows are now `NavigationLink` → `EditCustomActivityView(activity:)` |
| "Create Custom Activity" was a disabled `Button` | Now a `NavigationLink` → `CreateCustomActivityView()` |

---

## Architecture Decisions

1. **Closure-based callback over `@Environment` or shared state** — `onEmojiSelected: (String) -> Void` and `onComplete: ((CustomActivity) -> Void)?` keep each view self-contained. The `ActivityManager`'s `@Published` arrays already handle reactive UI updates, so callbacks are only needed for explicit post-action notifications (e.g., settings list refreshing).

2. **`init(activity:)` on EditCustomActivityView initializes all `@State` vars** — This avoids the anti-pattern of using `.onAppear` to populate state. SwiftUI guarantees `@State` initialization in `init` runs before `body` evaluation.

3. **MultiContactPickerView reused as-is** — The existing picker from Sprint 1 already handles multi-select, search, and returns `[String]` UIDs. It works without modification for the `visibleTo` selection in both create and edit forms.

4. **EmojiPickerView uses a flat emoji array per category (not searchable by name)** — Search filters by matching the emoji character itself (unicode scalar). For ~370 emojis this is sufficient; users primarily browse by category. A name-based search index could be added later if needed.

5. **Create returns `CustomActivity` via callback, Edit returns `Void`** — The create flow gives the parent the newly-created activity (useful for navigation or confirmation). Edit operates on an existing activity the parent already knows about, so a simple `onComplete` notification is sufficient.

6. **Validation is inline (not a separate validator)** — The form is small enough that `isValid` computed property directly expresses the rules. No need for a separate validator struct at this scale.

---

## Build Verification
```
xcodebuild -scheme LetsDoIt -destination 'platform=iOS Simulator,name=iPhone 17' build
→ BUILD SUCCEEDED
```
