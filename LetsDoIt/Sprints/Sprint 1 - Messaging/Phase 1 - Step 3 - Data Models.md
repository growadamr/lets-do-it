# Phase 1, Step 3: Data Models — Implementation Log

**Date:** 2026-04-05
**Status:** ✅ Complete — BUILD SUCCEEDED

---

## What Was Done

### New Files Created

| File | Purpose |
|------|---------|
| `Models/Conversation.swift` | `Conversation` struct with `ConversationType` enum (`dm`, `group`, `event`), nested `LastMessage` and `ConversationMetadata` structs |
| `Models/Message.swift` | `Message` struct with nested `LinkPreview` struct for Open Graph data |
| `Models/ConversationMembership.swift` | `ConversationMembership` struct for per-user conversation state (last read, mute, join time) |

### Files Modified

None.

---

## Model Details

### `Conversation`

```swift
struct Conversation: Identifiable, Codable, Hashable
```

| Property | Type | Notes |
|---|---|---|
| `id` | `String` | Firestore doc ID from `conversations/{id}` |
| `type` | `ConversationType` | Enum: `.dm`, `.group`, `.event` |
| `participants` | `[String]` | Array of user UIDs |
| `createdBy` | `String` | UID of creator |
| `createdAt` | `Date?` | Server timestamp |
| `lastMessage` | `LastMessage?` | Denormalized for list sorting |
| `metadata` | `ConversationMetadata?` | Group name or event link |
| `participantNames` | `[String: String]` | UID → display name cache |

**Nested types:**
- `LastMessage` — `text`, `senderUid`, `senderName`, `timestamp`
- `ConversationMetadata` — `name?`, `eventId?`

### `Message`

```swift
struct Message: Identifiable, Codable, Hashable
```

| Property | Type | Notes |
|---|---|---|
| `id` | `String` | Firestore doc ID from `messages/{id}` |
| `senderUid` | `String` | UID of sender |
| `senderName` | `String` | Display name at send time |
| `text` | `String` | Message body |
| `createdAt` | `Date?` | Server timestamp |
| `imageUrl` | `String?` | Firebase Storage URL |
| `linkPreview` | `LinkPreview?` | Open Graph preview data |
| `readBy` | `[String: Date]` | UID → read timestamp map |

**Nested type:**
- `LinkPreview` — `url`, `title?`, `description?`, `imageUrl?`

### `ConversationMembership`

```swift
struct ConversationMembership: Codable, Hashable
```

| Property | Type | Notes |
|---|---|---|
| `conversationId` | `String` | Reference to parent conversation |
| `lastReadAt` | `Date?` | Updated when user opens conversation |
| `muted` | `Bool` | Defaults to `false` |
| `joinedAt` | `Date?` | Server timestamp |

---

## Architecture Decisions

1. **Models are pure Swift — no FirebaseFirestore dependency** — The `Date` type is used directly throughout (not `Timestamp`). This keeps models framework-agnostic and avoids coupling the model layer to a specific backend. The `MessagingManager` service layer will handle `Date` ↔ `Timestamp` conversion when reading/writing to Firestore. This is a standard pattern: models describe the domain, adapters handle wire format.

2. **Nested structs instead of dictionaries for structured data** — `LastMessage` and `LinkPreview` are their own `Codable` structs rather than `[String: Any]` dictionaries. This gives compile-time safety and clear contracts for downstream view code.

3. **`Identifiable` on Conversation and Message only** — `ConversationMembership` doesn't need `Identifiable` because it's identified by its `conversationId` (the doc ID in Firestore matches). It conforms to `Codable` and `Hashable` for use in collections and equality checks.

4. **`participantNames` as a denormalized cache** — Storing display names directly on the conversation avoids a cross-user lookup for every row in the conversation list. Updated by the `MessagingManager` when conversation metadata changes.

---

## Build Verification
```
xcodebuild -scheme LetsDoIt -destination 'platform=iOS Simulator,name=iPhone 17' build
→ BUILD SUCCEEDED
```
