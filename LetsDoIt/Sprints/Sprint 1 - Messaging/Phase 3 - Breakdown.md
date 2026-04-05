# Phase 3: Rich Messages — Implementation Breakdown

**Parent:** Sprint 1 — Messaging
**Estimated duration:** 1 week
**Complexity:** MEDIUM
**Prerequisites:** Phase 1 (Foundation) + Phase 2 (Core Messaging UI) complete

---

## Deliverables Checklist

- [ ] **Step 8: Link Previews**
  - [ ] `LinkPreviewGenerator` utility — `LPMetadataProvider` wrapper for fetching Open Graph metadata
  - [ ] `LinkPreviewView` — renders a link preview card (title, description, thumbnail image)
  - [ ] Auto-detect URLs in outgoing message text, generate preview, store in message doc
  - [ ] `MessageBubbleView` updated to render `LinkPreviewView` above message text when `message.linkPreview` is non-nil
- [x] **Step 9: Read Receipts & Unread Tracking**
  - [x] "Seen by" indicator in `ChatView` below message bubbles (show names of users who read the message)
  - [x] Verify `markMessagesRead` flow: writes to `readBy` map in message doc + updates `lastReadAt` in membership doc
  - [x] Ensure unread badge in `ConversationsListView` correctly reflects read state (validated end-to-end)
- [ ] **Step 10: Cloud Functions (Deploy)**
  - [x] `onMessageCreated` — denormalizes `lastMessage` on conversation doc, triggers FCM push notification
  - [x] `onConversationCreated` — creates `conversationMemberships` for each participant
  - [ ] Test with Firebase Emulator Suite (manual — see implementation log for procedure)

---

## Dependencies (Existing Code)

| Dependency | File | Used By |
|---|---|---|
| `Message.linkPreview` | `Models/Message.swift` | Step 8 |
| `MessagingManager.sendMessage` | `Services/MessagingManager.swift` | Step 8 (store link preview) |
| `Message.readBy` | `Models/Message.swift` | Step 9 |
| `MessagingManager.markMessagesRead` | `Services/MessagingManager.swift` | Step 9 |
| `ConversationMembership.lastReadAt` | `Models/ConversationMembership.swift` | Step 9 (unread badges) |
| `MessagingManager.memberships` | `Services/MessagingManager.swift` | Step 9 (unread badges) |
| `MessagingManager.conversations` | `Services/MessagingManager.swift` | Step 10 (lastMessage denorm) |
| `AuthManager` | `Services/AuthManager.swift` | All steps (current user ID) |

---

## Step 8: Link Previews

### 8.1 — LinkPreviewGenerator utility
**Dependencies:** `LinkPresentation` framework, `LPMetadataProvider`
**Files to create:**
- `Services/LinkPreviewGenerator.swift`

**Sub-tasks:**
- [ ] Create `LinkPreviewGenerator` as a `struct` with a static async method: `func generatePreview(url: String) async -> LinkPreview?`
- [ ] Use `LPMetadataProvider.startFetchingMetadata(for: URL)` to fetch Open Graph data
- [ ] Extract: `title`, `description`, `imageURL` (from `LPLinkMetadata`)
- [ ] Return a `LinkPreview` struct matching the model (`url`, `title`, `description`, `imageUrl`)
- [ ] Handle errors gracefully (invalid URL, timeout, no metadata found) — return `nil` on failure
- [ ] Set a reasonable timeout (e.g., 5 seconds) to avoid blocking message sends

### 8.2 — LinkPreviewView
**Dependencies:** `LinkPreview` model
**Files to create:**
- `Views/Messaging/LinkPreviewView.swift`

**Sub-tasks:**
- [ ] Create `LinkPreviewView` accepting `linkPreview: LinkPreview`
- [ ] Layout: rounded rectangle card with subtle border/shadow, containing:
  - Title label (bold, `.subheadline`)
  - Description label (`.caption`, secondary color, 2-line limit)
  - Optional `AsyncImage` thumbnail at top of card (aspect-fill, clipped to rounded rect, ~120px height)
- [ ] Tap gesture: open URL in Safari via `UIApplication.shared.open`
- [ ] Skeleton/placeholder state while image loads
- [ ] Handle missing fields gracefully (hide description if nil, hide image if nil)

### 8.3 — Wire link preview into ChatView send flow
**Dependencies:** `LinkPreviewGenerator`, `MessagingManager.sendMessage`, `ChatView`
**Files to modify:**
- `Views/Messaging/ChatView.swift`
- `Services/MessagingManager.swift`

**Sub-tasks:**
- [ ] In `ChatView.sendMessage()`, after clearing text, detect if text contains a URL (simple regex: `https?://\\S+`)
- [ ] If URL found, call `LinkPreviewGenerator.generatePreview(url:)` asynchronously in the same Task
- [ ] Pass the resulting `LinkPreview?` into `MessagingManager.sendMessage(text:conversationId:linkPreview:)`
- [ ] Add `linkPreview: LinkPreview?` parameter to `sendMessage` method
- [ ] Store `linkPreview` in the message doc as a nested map (`linkPreview.url`, `linkPreview.title`, etc.)
- [ ] Update `decodeMessage` in `MessagingManager` to parse `linkPreview` field (already present in model but ensure decoding works)
- [ ] Non-blocking: if link preview generation fails or times out, still send the message without the preview

### 8.4 — Render link preview in MessageBubbleView
**Dependencies:** `LinkPreviewView`, `Message.linkPreview`
**Files to modify:**
- `Views/Messaging/MessageBubbleView.swift`

**Sub-tasks:**
- [ ] In `MessageBubbleView.bubble`, check if `message.linkPreview` is non-nil
- [ ] If present, render `LinkPreviewView(linkPreview:)` above the text label (below any image)
- [ ] Ensure the link preview card fits within the bubble width
- [ ] For messages from current user: use blue-tinted card background; for others: system gray

---

## Step 9: Read Receipts & Unread Tracking

### 9.1 — "Seen by" indicator
**Dependencies:** `Message.readBy`, `Conversation.participants`, `ChatView`
**Files to create:**
- `Views/Messaging/ReadReceiptsView.swift` (optional — or inline in ChatView)

**Files to modify:**
- `Views/Messaging/ChatView.swift`

**Sub-tasks:**
- [ ] After the last message sent by the current user, show a "Seen by" label below the bubble
- [ ] Compute read names: filter `message.readBy` keys to exclude current user's UID, map remaining UIDs to names via `conversation.participantNames`
- [ ] Display: "Seen by Alice" or "Seen by Alice, Bob" (comma-separated, max 2 names before truncating to "Alice + 2 others")
- [ ] Only show for messages from current user (no need to show "seen by me")
- [ ] Only show for the most recent self-sent message (avoid cluttering every bubble)
- [ ] If no one has read it yet, show nothing (or optionally "Delivered" as a single-dot state)

### 9.2 — Validate end-to-end read tracking
**Dependencies:** `MessagingManager.markMessagesRead`, `ConversationMembership.lastReadAt`
**Files to modify:**
- `Services/MessagingManager.swift` (minor: verify correctness)

**Sub-tasks:**
- [ ] Verify `markMessagesRead` correctly updates `readBy[uid]` on all unread messages in the conversation
- [ ] Verify it also updates `lastReadAt` on the membership doc (used for unread badge calculation)
- [ ] Test: open a conversation, verify badge clears in `ConversationsListView`
- [ ] Test: switch away from conversation, receive new messages, verify badge reappears
- [ ] Test: open conversation again, verify badge clears
- [ ] If gaps found, fix in `MessagingManager`

---

## Step 10: Cloud Functions (Deploy)

### 10.1 — `onMessageCreated` function
**Dependencies:** Firebase Cloud Functions (Node.js), `conversations` collection structure
**Files to create:**
- `firebase/functions/index.js` (or extend existing functions file)

**Sub-tasks:**
- [ ] Create Cloud Function triggered `onCreate` of `conversations/{conversationId}/messages/{messageId}`
- [ ] On trigger: update the parent conversation doc's `lastMessage` field with denormalized data:
  - `text`: message text (truncated to 100 chars)
  - `senderUid`: message sender UID
  - `senderName`: message sender name
  - `timestamp`: message `createdAt`
  - `imageUrl`: message `imageUrl` (if present)
- [ ] Trigger FCM push notification to all conversation participants except the sender
  - Query `users/{uid}/conversationMemberships/{conversationId}` to get participant list
  - Exclude sender's UID
  - For each remaining participant, look up their `fcmToken` from their user doc
  - Send push via Firebase Admin SDK with title ("New message from {name}") and body (message text or "📷 Photo")
  - Include deep-link data: `conversationId` for routing
- [ ] Handle errors gracefully (missing FCM token, participant left conversation)
- [ ] Deploy via `firebase deploy --only functions`

### 10.2 — `onConversationCreated` function
**Dependencies:** Firebase Cloud Functions, `conversationMemberships` collection structure
**Files to create:**
- Extend `firebase/functions/index.js` with second function

**Sub-tasks:**
- [ ] Create Cloud Function triggered `onCreate` of `conversations/{conversationId}`
- [ ] On trigger: read `participants` array from the new conversation doc
- [ ] For each participant UID, create a `users/{uid}/conversationMemberships/{conversationId}` doc with:
  - `conversationId`: the conversation ID
  - `joinedAt`: server timestamp
  - `lastReadAt`: server timestamp
  - `muted`: false
- [ ] Handle case where memberships already exist (idempotent — use `set` with `merge: true`)
- [ ] Deploy alongside `onMessageCreated`
- [ ] **Note:** The client-side `MessagingManager` already creates memberships in `createMemberships()`. This Cloud Function serves as a safety net for edge cases (e.g., server-side conversation creation in Sprint 3). Use `set({ ... }, { merge: true })` to avoid conflicts.

### 10.3 — Test with Firebase Emulator Suite
**Dependencies:** Firebase Emulator, local functions code
**Files to modify:**
- `firebase/firebase.json` (emulator config if needed)

**Sub-tasks:**
- [ ] Start Firebase Emulator: `firebase emulators:start`
- [ ] Test `onMessageCreated`: create a test message via Firestore emulator UI, verify `lastMessage` is denormalized on the conversation doc
- [ ] Test `onConversationCreated`: create a test conversation, verify membership docs are created for all participants
- [ ] Test error cases: send message to non-existent conversation, create conversation with invalid participants
- [ ] Document test results in the implementation log

---

## File Summary

### New Files (5)
| File | Step | Purpose |
|------|------|---------|
| `Services/LinkPreviewGenerator.swift` | 8 | `LPMetadataProvider` wrapper for fetching Open Graph metadata |
| `Views/Messaging/LinkPreviewView.swift` | 8 | Renders a link preview card (title, description, thumbnail) |
| `Views/Messaging/ReadReceiptsView.swift` | 9 | "Seen by" indicator showing who read a message |
| `firebase/functions/index.js` | 10 | Cloud Functions: `onMessageCreated`, `onConversationCreated` |
| `Sprints/Sprint 1 - Messaging/Phase 3 - Step 8 - Link Previews.md` | — | Implementation log (created during implementation) |

### Modified Files (4)
| File | Step | Change |
|------|------|--------|
| `Views/Messaging/ChatView.swift` | 8, 9 | Add URL detection + link preview generation on send; add "Seen by" indicator |
| `Views/Messaging/MessageBubbleView.swift` | 8 | Render `LinkPreviewView` when `message.linkPreview` is non-nil |
| `Services/MessagingManager.swift` | 8, 9 | Add `linkPreview` param to `sendMessage`; verify `markMessagesRead` correctness |
| `firebase/firebase.json` | 10 | Emulator config (if not already present) |

---

## Implementation Order

Recommended: **8 → 9 → 10**

Step 8 (Link Previews) is the most visible user-facing feature and has the most code changes. Step 9 (Read Receipts) validates and completes the existing unread/read infrastructure. Step 10 (Cloud Functions) is server-side deployment work that can be done independently but benefits from seeing the client-side data flow first.

---

## Workflow Format — ALL Implementation Sessions Must Follow This

Every implementation task must follow this exact format:

1. **Plan** — Read the step's requirements and context files. Present a concrete implementation plan (specific files to create/modify, API design, key decisions) before writing any code.
2. **Present & confirm** — Wait for explicit user approval before implementing.
3. **Implement** — Create/modify files. Follow existing code conventions from the project.
4. **Verify** — Run `xcodebuild -scheme LetsDoIt -destination 'platform=iOS Simulator,name=iPhone 17' build` and confirm BUILD SUCCEEDED. Fix any errors.
5. **Document** — Create a "Phase 3 - Step X - [Name].md" implementation log in `Sprints/Sprint 1 - Messaging/` matching the format of the Phase 1 logs (`Phase 1 - Step 3 - Data Models.md` and `Phase 1 - Step 4 - MessagingManager.md`). Update this breakdown file to mark the step complete.
6. **Commit handoff** — End by asking the user to commit locally, and provide the list of changed files. Then give the user a ready-to-paste prompt for a fresh session to handle the next step. The prompt must include:
   - The project path (/Users/adamgrow/hermGameTest/LetsDoIt)
   - Which context files to re-read at the start of the next session
   - The specific next step to work on
   - A reminder of this workflow format (Plan -> Present & confirm -> Implement -> Verify -> Document -> Commit handoff)

IMPORTANT: The commit handoff prompt for the next step must be given as plain text only. Do NOT use markdown formatting (no code fences, no bold, no backticks, no lists) in the prompt block. It must be raw plain text that the user can copy and paste directly into a new chat.

### Implementation Log Format (reference)

Each implementation log must match the structure of the Phase 1 logs. See these files for the exact format:
- `Sprints/Sprint 1 - Messaging/Phase 1 - Step 3 - Data Models.md`
- `Sprints/Sprint 1 - Messaging/Phase 1 - Step 4 - MessagingManager.md`

Required sections in each log:
- Title, date, build status badge (✅ Complete — BUILD SUCCEEDED)
- "What Was Done" — tables of new/modified files
- Detailed section per file/service with property/method tables
- "Architecture Decisions" — numbered list of design rationale
- "Build Verification" — the exact xcodebuild command and result
