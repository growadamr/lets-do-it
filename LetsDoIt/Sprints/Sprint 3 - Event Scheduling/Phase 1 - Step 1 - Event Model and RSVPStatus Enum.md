# Phase 1, Step 1: Event Model and RSVPStatus Enum — Implementation Log

**Date:** 2026-04-06
**Status:** ✅ Complete — BUILD SUCCEEDED

---

## What Was Done

### New Files Created

| File | Purpose |
|------|---------|
| `Models/Event.swift` | `Event` struct, `RSVPStatus` enum, `EventStatus` enum |

### Files Modified

None.

---

## Model Details

### `RSVPStatus`

```swift
enum RSVPStatus: String, Codable, CaseIterable
```

| Case | Raw Value | Display Label | Color |
|------|-----------|---------------|-------|
| `.accepted` | `"accepted"` | "Accepted" | green |
| `.declined` | `"declined"` | "Declined" | red |
| `.maybe` | `"maybe"` | "Maybe" | yellow |

**Computed properties:**
- `displayLabel: String` — Human-readable label for UI display
- `colorName: String` — Semantic color name for future theming

### `EventStatus`

```swift
enum EventStatus: String, Codable, CaseIterable
```

| Case | Raw Value |
|------|-----------|
| `.active` | `"active"` |
| `.cancelled` | `"cancelled"` |

### `Event`

```swift
struct Event: Identifiable, Codable, Hashable
```

| Property | Type | Notes |
|---|---|---|
| `id` | `String` | Firestore doc ID from `events/{id}` |
| `title` | `String` | Required, 1–100 characters (validated at UI layer) |
| `description` | `String?` | Optional event description |
| `location` | `String?` | Optional location string |
| `dateTime` | `Date` | Pure Swift Date, not Timestamp |
| `createdBy` | `String` | UID of event creator |
| `createdAt` | `Date?` | Server timestamp |
| `updatedAt` | `Date?` | Server timestamp on edit |
| `invitees` | `[String]` | Array of invited user UIDs |
| `rsvps` | `[String: RSVPStatus]` | UID → RSVP status map |
| `conversationId` | `String?` | Links to Sprint 1 group conversation |
| `status` | `EventStatus` | `.active` or `.cancelled` |

**Computed properties (planned for future use):**
- `isCreator(currentUid:) -> Bool` — convenience check (to be added when service layer needs it)
- `rsvpSummary -> String` — e.g. "2 accepted, 1 maybe, 1 declined" (to be used in EventsListView)

---

## Architecture Decisions

1. **Pure Swift model — no FirebaseFirestore import** — Following the pattern established in `Conversation.swift` and `CustomActivity.swift`, the `Event` model uses `Date` directly (not `Timestamp`). The `EventManager` service layer will handle `Date` ↔ `Timestamp` conversion when reading/writing to Firestore. This keeps the model layer framework-agnostic.

2. **`CodingKeys` with snake_case to match Firestore schema** — The `CodingKeys` enum uses the exact field names from the Firestore schema defined in BREAKDOWN.md (e.g., `dateTime`, `createdBy`, `conversationId`). This ensures `Codable` maps directly to the Firestore document structure without custom encoding/decoding logic in the model.

3. **`Hashable` via `id` only** — Same pattern as `CustomActivity`. Two `Event` instances with the same `id` are considered equal regardless of field differences, which is appropriate for SwiftUI list identity and diffing.

4. **`RSVPStatus` and `EventStatus` as separate files would be overkill** — Both enums are small, tightly coupled to `Event`, and serve no other purpose. Colocating them in `Event.swift` follows the principle of keeping related types together for discoverability, matching how `ConversationType`, `LastMessage`, and `ConversationMetadata` are colocated with `Conversation`.

5. **`CaseIterable` on both enums** — Enables iteration for UI rendering (e.g., RSVP button generation, status filters) without manual case enumeration.

---

## Build Verification
```
xcodebuild -scheme LetsDoIt -destination 'platform=iOS Simulator,name=iPhone 17' build
→ BUILD SUCCEEDED
```
