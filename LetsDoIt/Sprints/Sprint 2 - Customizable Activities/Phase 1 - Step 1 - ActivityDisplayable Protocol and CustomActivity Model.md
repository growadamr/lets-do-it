# Phase 1, Step 1: ActivityDisplayable Protocol & CustomActivity Model

**Date:** April 5, 2026
**Build Status:** ✅ Complete — BUILD SUCCEEDED

---

## What Was Done

### New Files

| File | Purpose |
|------|---------|
| `Models/CustomActivity.swift` | CustomActivity struct conforming to ActivityDisplayable, Codable, Identifiable, Hashable |

### Modified Files

| File | Change |
|------|--------|
| `Models/ActivityItem.swift` | Added `ActivityDisplayable` protocol; conformed `ActivityItem` to it; added `Codable` to `ActivityCategory` |

---

## ActivityDisplayable Protocol

```swift
protocol ActivityDisplayable: Identifiable, Hashable {
    var id: String { get }
    var emoji: String { get }
    var label: String { get }
    var category: ActivityCategory { get }
}
```

The protocol unifies catalog items (`ActivityItem`) and custom activities (`CustomActivity`) so that rendering code (`ActivityRow`, `ActivityListView`, `MatchHistoryView`) can work with `any ActivityDisplayable` without caring about the underlying type.

### Conforming Types

| Type | Source | Notes |
|------|--------|-------|
| `ActivityItem` | Static catalog (hardcoded 16 items) | Already had all four properties; trivial conformance |
| `CustomActivity` | User-created, stored in Firestore | New struct with additional fields (`createdAt`, `visibleTo`) |

---

## CustomActivity Model

```swift
struct CustomActivity: ActivityDisplayable, Identifiable, Codable, Hashable {
    let id: String          // prefixed with "custom_" when created by service
    let emoji: String
    let label: String
    let category: ActivityCategory
    let createdAt: Date?    // optional — nil for catalog items
    let visibleTo: [String] // array of contact UIDs who can see this activity
}
```

### Properties

| Property | Type | Notes |
|----------|------|-------|
| `id` | `String` | Unique identifier; service will prefix with `custom_` |
| `emoji` | `String` | Single emoji character for display |
| `label` | `String` | User-facing label (e.g. "Play piano together?") |
| `category` | `ActivityCategory` | Same category enum as catalog items |
| `createdAt` | `Date?` | Creation timestamp; optional for forward compatibility |
| `visibleTo` | `[String]` | UIDs of contacts who can see this activity |

### Hashable Conformance

Hashing and equality based on `id` only, consistent with how `ActivityItem` works. This enables deduplication in effective activity list computation.

### Codable

Fully synthesized `Codable` conformance. `ActivityCategory` (a `String`-backed enum) also conforms to `Codable` via its raw value, enabling seamless Firestore document serialization.

---

## Architecture Decisions

1. **Protocol with `{ get }` requirements** — Both conforming types use immutable `let` properties, so read-only protocol requirements are sufficient and avoid unnecessary `set` constraints.

2. **`visibleTo` as `[String]`** — Plain array of UIDs. The security rule (`request.auth.uid in resource.data.visibleTo`) handles cross-user read access. The service layer manages the array contents.

3. **`createdAt` as `Date?` not `Timestamp`** — Following the Sprint 1 pattern: models use pure Swift types (`Date`), and the service layer handles `Date` ↔ `Timestamp` conversion on Firestore read/write. No `FirebaseFirestore` import in model files.

4. **Added `Codable` to `ActivityCategory`** — Required for `CustomActivity`'s synthesized `Codable` conformance. Since it's a `String`-backed enum, the raw value is used directly as the encoded form.

5. **No changes to `ActivityCatalog.swift`** — The static catalog remains the single source of truth for the 16 built-in items. It is not modified in this step.

---

## Build Verification

**Command:**
```
xcodebuild -scheme LetsDoIt -destination 'platform=iOS Simulator,name=iPhone 17' build
```

**Result:** BUILD SUCCEEDED
