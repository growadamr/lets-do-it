# Phase 2: Core Messaging UI — Implementation Breakdown

**Parent:** Sprint 1 — Messaging
**Estimated duration:** 1–1.5 weeks
**Complexity:** HIGH
**Prerequisites:** Phase 1 (TabView migration, Data Models, MessagingManager) complete

---

## Deliverables Checklist

- [x] **Step 5: Conversation List**
  - [x] `ConversationsListView` with `MessagingManager` integration
  - [x] Recency-sorted list with unread badges
  - [x] Swipe actions (delete, mute)
  - [x] Empty state
  - [x] `MessagesTabView` wired to `ConversationsListView`
- [x] **Step 6: Chat Thread**
  - [x] `ChatView` with text input, send button, scroll-to-bottom
  - [x] `MessageBubbleView` with left/right alignment, text + image rendering
  - [x] `ImagePickerView` (PHPickerViewController wrapper)
  - [x] Image attachment button in chat input with upload flow
  - [x] Pagination on scroll-to-top (50 messages/page via `MessagingManager.fetchMessages`)
- [ ] **Step 7: New Conversation Flow**
  - [ ] `MultiContactPickerView` — reusable multi-select contact picker
  - [ ] `NewConversationView` — DM vs group selection, group name input
  - [ ] Navigation: "+" button on `ConversationsListView` → `NewConversationView`
  - [ ] Post-creation: auto-navigate to new conversation thread

---

## Dependencies (Existing Code)

| Dependency | File | Used By |
|---|---|---|
| `MessagingManager` | `Services/MessagingManager.swift` | Steps 5, 6, 7 |
| `Conversation` model | `Models/Conversation.swift` | Steps 5, 7 |
| `Message` model | `Models/Message.swift` | Step 6 |
| `ConversationMembership` model | `Models/ConversationMembership.swift` | Step 5 (unread calc) |
| `ContactManager.Contact` | `Services/ContactManager.swift` | Step 7 (contact picker) |
| `AuthManager` | `Services/AuthManager.swift` | All steps (current user ID) |

---

## Step 5: Conversation List

### 5.1 — ConversationsListView (core list view)
**Dependencies:** `MessagingManager`, `Conversation`, `AuthManager`
**Files to create:**
- `Views/Messaging/ConversationsListView.swift`

**Files to modify:**
- `Views/MessagesTabView.swift` — replace placeholder with `ConversationsListView`

**Sub-tasks:**
- [ ] Create `ConversationsListView` as a `View` with `@StateObject`/`@ObservedObject` reference to `MessagingManager.shared`
- [ ] In `.onAppear`, call `MessagingManager.startListeningConversations()`; in `.onDisappear`, call `stopListeningConversations()`
- [ ] Render `List` or `ForEach` of conversations from `MessagingManager.conversations` (already sorted by `lastMessage.timestamp` desc by the service)
- [ ] Each row shows: conversation title (group name from `metadata.name` for groups, or participant name from `participantNames` for DMs excluding self), last message text snippet, timestamp label
- [ ] Unread badge: compute by comparing `lastMessage.timestamp` vs membership `lastReadAt` — requires `MessagingManager` to also publish memberships, or compute from `conversation.lastMessage` + a local lookup
- [ ] Tap on a row → `NavigationLink` to placeholder `ChatView(conversationId:)` (Step 6 will fill in the destination)
- [ ] Update `MessagesTabView` to embed `ConversationsListView` inside its `NavigationStack`

### 5.2 — Swipe Actions (delete, mute)
**Dependencies:** `MessagingManager.deleteConversation`, mute toggle (needs new method on `MessagingManager`)
**Files to modify:**
- `Views/Messaging/ConversationsListView.swift`
- `Services/MessagingManager.swift` — add `toggleMute(conversationId:)` method

**Sub-tasks:**
- [ ] Add `toggleMute(conversationId:)` method to `MessagingManager` — updates `muted` field on `users/{uid}/conversationMemberships/{conversationId}`
- [ ] Add `.swipeActions(edge: .trailing)` to each conversation row
- [ ] Delete action: destructive, calls `MessagingManager.deleteConversation`, shows confirmation alert
- [ ] Mute action: toggles mute icon, calls `toggleMute`
- [ ] Verify delete removes row from list (published array auto-updates)

### 5.3 — Empty State
**Dependencies:** None
**Files to modify:**
- `Views/Messaging/ConversationsListView.swift`

**Sub-tasks:**
- [ ] When `MessagingManager.conversations.isEmpty`, show centered VStack with message icon, "No conversations yet" title, "Start a new conversation" subtitle
- [ ] Style matches existing empty state in `MessagesTabView` (can reuse or replace it)

---

## Step 6: Chat Thread

### 6.1 — ChatView (structure + text input)
**Dependencies:** `MessagingManager`, `Message`, `Conversation`
**Files to create:**
- `Views/Messaging/ChatView.swift`

**Sub-tasks:**
- [ ] Create `ChatView` accepting `conversationId: String` and optionally `conversation: Conversation` for title
- [ ] `@StateObject`/`@ObservedObject` reference to `MessagingManager.shared`
- [ ] In `.onAppear`: call `startListeningMessages(conversationId:)`, call `markMessagesRead(conversationId:)`
- [ ] In `.onDisappear`: call `stopListeningMessages()`
- [ ] Layout: `ScrollViewReader` with `ScrollView` (or `LazyVStack`) for messages + fixed text input bar at bottom
- [ ] Text input: `TextField` + Send `Button`, bound to `@State` string
- [ ] Send action: calls `MessagingManager.sendMessage(text:conversationId:)`, clears text field
- [ ] Auto-scroll to bottom on new messages using `ScrollViewReader.scrollTo`
- [ ] Navigation title: conversation name (group) or participant name (DM)
- [ ] Handle keyboard dismissal (tap outside, or swipe down)

### 6.2 — MessageBubbleView
**Dependencies:** `Message`, `AuthManager` (to determine sender = self vs other)
**Files to create:**
- `Views/Messaging/MessageBubbleView.swift`

**Sub-tasks:**
- [ ] Create `MessageBubbleView` accepting `message: Message`, `isFromCurrentUser: Bool`
- [ ] Layout: HStack with alignment — if `isFromCurrentUser`, spacer on left, bubble on right; reverse for other
- [ ] Bubble styling: rounded rectangle, blue for self / gray for other (using `.chatBubble` shape or standard rounded rect)
- [ ] Render `message.text` inside bubble (multiline, `fixedSize` not needed)
- [ ] Render sender name above bubble for group conversations only (skip for DMs)
- [ ] Timestamp label below bubble (formatted with `Date` formatter)
- [ ] Placeholder for image rendering — if `message.imageUrl` is non-nil, show `AsyncImage` above text in bubble (Step 6.4 will wire this up fully)

### 6.3 — ImagePickerView (PHPickerViewController wrapper)
**Dependencies:** UIKit `PHPickerViewController`, SwiftUI `UIViewControllerRepresentable`
**Files to create:**
- `Views/Messaging/ImagePickerView.swift`

**Sub-tasks:**
- [ ] Create `ImagePickerView` as `UIViewControllerRepresentable` wrapping `PHPickerViewController`
- [ ] Configuration: `PHPickerConfiguration(photoLibrary: .shared())`, filter `.images`, selection `.ordered`
- [ ] `@Binding var selectedImages: [UIImage]` — on picker dismiss, load selected images via `itemProvider.loadObject(ofClass: UIImage.self)`
- [ ] `@Environment(\.dismiss)` for dismissing the sheet
- [ ] Coordinator pattern for `PHPickerViewControllerDelegate`
- [ ] Present as `.sheet(isPresented:)` from `ChatView`

### 6.4 — Image Attachment in ChatView
**Dependencies:** `MessagingManager.uploadImage`, `ImagePickerView`
**Files to modify:**
- `Views/Messaging/ChatView.swift`

**Sub-tasks:**
- [ ] Add image picker button (camera/photo icon) to the text input bar
- [ ] Add `@State` for `showingImagePicker: Bool` and `pendingImages: [UIImage]`
- [ ] When images selected, show preview thumbnails above input bar (horizontal scroll)
- [ ] Send button: if images are pending, upload each via `MessagingManager.uploadImage(_:conversationId:messageId:)`, then call `sendMessage(text:conversationId:imageUrl:)` for each image (with optional caption text)
- [ ] Show upload progress indicator (simple spinner or progress bar)
- [ ] In `MessageBubbleView`, render `AsyncImage` when `message.imageUrl` is non-nil — full-width within bubble, with aspect-fit
- [ ] Handle upload errors with alert

### 6.5 — Pagination (load older messages)
**Dependencies:** `MessagingManager.fetchMessages(cursor:)`
**Files to modify:**
- `Views/Messaging/ChatView.swift`
- `Services/MessagingManager.swift` (minor: expose loading state)

**Sub-tasks:**
- [ ] Add `@Published var isLoadingMoreMessages: Bool` to `MessagingManager`
- [ ] In `ChatView`, detect scroll-to-top (or pull-to-refresh / "Load older messages" button at top)
- [ ] When triggered, call `MessagingManager.fetchMessages(conversationId:cursor:)` with current last message as cursor
- [ ] Prepend returned messages to `MessagingManager.messages` (note: listener provides real-time, fetchMessages provides historical — need to merge carefully to avoid duplicates)
- [ ] Show loading indicator at top while fetching
- [ ] Handle end of history (no more pages)

---

## Step 7: New Conversation Flow

### 7.1 — MultiContactPickerView (reusable contact picker)
**Dependencies:** `ContactManager.contacts`
**Files to create:**
- `Views/Messaging/MultiContactPickerView.swift`

**Sub-tasks:**
- [ ] Create `MultiContactPickerView` as a standalone view — accepts `@Binding var selectedUids: [String]`
- [ ] Displays `ContactManager.shared.contacts` as a list with checkmarks for selected items
- [ ] Each row: `ContactRow` with contact name (or "Unnamed" placeholder) + checkmark icon
- [ ] Tap toggles selection (add/remove from `selectedUids`)
- [ ] Search bar to filter contacts by name
- [ ] "Done" button that dismisses the sheet
- [ ] Note: This picker is **reusable** — designed for reuse in Sprint 2 (activity visibility) and Sprint 3 (event invitees)

### 7.2 — NewConversationView
**Dependencies:** `MessagingManager`, `MultiContactPickerView`, `ConversationType`
**Files to create:**
- `Views/Messaging/NewConversationView.swift`

**Sub-tasks:**
- [ ] Create `NewConversationView` with `@Environment(\.dismiss)` for cancel
- [ ] Step 1: "Start a conversation" header + button to open contact picker sheet
- [ ] After contacts selected: show selected contacts summary (names as chips/list)
- [ ] DM vs Group toggle: if 1 contact selected → default to DM; if 2+ → default to group
- [ ] Group mode: show text field for group name (required for groups)
- [ ] "Create" button: calls `MessagingManager.createDM(with:)` for single contact, or `MessagingManager.createGroup(name:participantUids:)` for multiple
- [ ] On success: dismiss sheet, navigate to new `ChatView` for the created conversation
- [ ] On error: show alert with error message

### 7.3 — Wire up entry point
**Dependencies:** `ConversationsListView` (from Step 5)
**Files to modify:**
- `Views/Messaging/ConversationsListView.swift`
- `Views/MessagesTabView.swift`

**Sub-tasks:**
- [ ] Add "+" toolbar button or "New Conversation" row at top of `ConversationsListView`
- [ ] Tap opens `NewConversationView` as a `.sheet` or via `NavigationLink`
- [ ] Ensure `MessagesTabView` navigation stack supports the full flow: list → chat → back

---

## File Summary

### New Files (9)
| File | Step | Purpose |
|------|------|---------|
| `Views/Messaging/ConversationsListView.swift` | 5 | Conversation list with unread badges, swipe actions |
| `Views/Messaging/ChatView.swift` | 6 | Message thread view with input, pagination, image attachments |
| `Views/Messaging/MessageBubbleView.swift` | 6 | Individual message bubble rendering |
| `Views/Messaging/ImagePickerView.swift` | 6 | PHPickerViewController wrapper |
| `Views/Messaging/NewConversationView.swift` | 7 | Create DM or group conversation flow |
| `Views/Messaging/MultiContactPickerView.swift` | 7 | Reusable multi-select contact picker |

### Modified Files (3)
| File | Step | Change |
|------|------|--------|
| `Views/MessagesTabView.swift` | 5 | Replace placeholder with `ConversationsListView` |
| `Services/MessagingManager.swift` | 5 | Add `toggleMute(conversationId:)` method |
| `Services/MessagingManager.swift` | 6 | Add `isLoadingMoreMessages` published property |

---

## Implementation Order

Recommended: **5 → 6 → 7**

Step 5 provides the entry point (conversation list). Step 6 builds the core chat experience. Step 7 adds the creation flow. Each step builds on the previous one, and the navigation links between them are established incrementally.

---

## Workflow Format — ALL Implementation Sessions Must Follow This

Every implementation task must follow this exact format:

1. **Plan** — Read the step's requirements and context files. Present a concrete implementation plan (specific files to create/modify, API design, key decisions) before writing any code.
2. **Present & confirm** — Wait for explicit user approval before implementing.
3. **Implement** — Create/modify files. Follow existing code conventions from the project.
4. **Verify** — Run `xcodebuild -scheme LetsDoIt -destination 'platform=iOS Simulator,name=iPhone 17' build` and confirm BUILD SUCCEEDED. Fix any errors.
5. **Document** — Create a "Phase 2 - Step X - [Name].md" implementation log in `Sprints/Sprint 1 - Messaging/` matching the format of the Phase 1 logs (`Phase 1 - Step 3 - Data Models.md` and `Phase 1 - Step 4 - MessagingManager.md`). Update this breakdown file to mark the step complete.
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
