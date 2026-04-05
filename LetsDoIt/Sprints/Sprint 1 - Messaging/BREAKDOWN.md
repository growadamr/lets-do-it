# Sprint 1: Messaging — Implementation Breakdown

**Estimated duration:** 3–4 weeks  
**Complexity:** HIGH  
**Key risk:** Full messaging subsystem + TabView migration

---

## Phase 1: Structural Migration & Foundation (Week 1)

### ✅ 1. TabView Migration — COMPLETE
- [x] Convert `HomeView` root to TabView with 3 tabs: Activity, Messages, Contacts
- [x] Ensure existing navigation flows still work within the Activity tab
- [x] Test all existing functionality still works post-migration

**Files changed:**
- `Views/HomeView.swift` — replaced single NavigationStack with TabView
- `Views/ActivityTabView.swift` — **new** — Activity tab with landing + contact-selected views
- `Views/ContactsTabView.swift` — **new** — thin wrapper for Contacts tab
- `Views/MessagesTabView.swift` — **new** — placeholder empty state
- `Views/ContactsListView.swift` — added own NavigationStack, added `onSelect` callback
- `Views/ContactsListView.swift` `ContactRow` — calls `onSelect` on tap

**Build status:** ✅ BUILD SUCCEEDED (iPhone 17 simulator)

---

### 2. Firebase Setup
- [x] Add `FirebaseStorage` SPM dependency to Xcode project
- [x] Update Firestore security rules for new collections (`conversations`, `messages`, `conversationMemberships`)
- [x] Set up Firebase Storage bucket and rules (`chat_images/{conversationId}/{messageId}/{filename}`)
- [x] Deployed via Firebase CLI — Firestore rules + Storage rules live

---

### 3. Data Models — COMPLETE
- [x] Create `Models/Conversation.swift` — Conversation struct (type, participants, metadata, lastMessage, participantNames)
- [x] Create `Models/Message.swift` — Message struct (senderUid, senderName, text, imageUrl, linkPreview, readBy, createdAt)
- [x] Create `Models/ConversationMembership.swift` — membership model (lastReadAt, muted, joinedAt)

---

### 4. MessagingManager Service — COMPLETE
- [x] Create `Services/MessagingManager.swift`
- [x] Conversation CRUD operations (create DM, create group, fetch list, delete)
- [x] Message CRUD with subcollection handling (send, fetch, delete)
- [x] Image upload to Firebase Storage (JPEG 0.7, max 1024px)
- [x] Firestore real-time listeners for conversations + messages
- [x] Cursor-based pagination (50 messages/page)

**Files created:**
- `Services/MessagingManager.swift` — conversation CRUD, message CRUD, image upload/resize, real-time listeners, cursor pagination, membership management

**Build status:** ✅ BUILD SUCCEEDED (iPhone 17 simulator)

---

## Phase 2: Core Messaging UI (Week 2)

### 5. Conversation List
- [ ] `Views/Messaging/ConversationsListView.swift` — sorted by recency, unread badges
- [ ] Pull from `conversationMemberships` + denormalized `lastMessage`
- [ ] Swipe actions (delete, mute)
- [ ] Empty state

### 6. Chat Thread
- [ ] `Views/Messaging/ChatView.swift` — message input, scroll-to-bottom, pagination
- [ ] `Views/Messaging/MessageBubbleView.swift` — renders text/image/link preview, left/right alignment
- [ ] `Views/Messaging/ImagePickerView.swift` — PHPickerViewController wrapper for image attachment
- [ ] Image attachment button in chat input

### 7. New Conversation Flow
- [ ] `Views/Messaging/NewConversationView.swift` — pick contacts, choose DM or group, set group name
- [ ] Reusable contact multi-select picker (reused in Sprints 2 & 3)

---

## Phase 3: Rich Messages (Week 3)

### 8. Link Previews
- [ ] `Utilities/LinkPreviewGenerator.swift` — LPMetadataProvider wrapper
- [ ] `Views/Messaging/LinkPreviewView.swift` — Open Graph card renderer
- [ ] Auto-detect URLs in message text, generate + store preview in message doc

### 9. Read Receipts & Unread Tracking
- [ ] Mark messages as read when viewing conversation
- [ ] Update `lastReadAt` in membership doc
- [ ] Unread badge calculation in conversation list

### 10. Cloud Functions (Deploy)
- [ ] `onMessageCreated` — denormalize `lastMessage`, send FCM push
- [ ] `onConversationCreated` — create `conversationMemberships` for each participant
- [ ] Test with Firebase Emulator Suite

---

## Phase 4: Integration & Polish (Week 4)

### 11. Deep Linking & Notifications
- [ ] Update `AppDelegate.swift` — deep-link notification taps to specific conversation
- [ ] Build generic deep-link router (Sprint 3 will extend for events)
- [ ] Add "Message" button to `ContactsListView.swift`

### 12. Edge Cases & UX
- [ ] Handle offline state, loading states, error states
- [ ] Image compression pipeline
- [ ] Empty states for no conversations
- [ ] Swipe actions on conversation list (delete, mute)

### 13. Testing
- [ ] Test with two simulator accounts (anonymous auth)
- [ ] Verify Firestore docs created/updated via Firebase Console
- [ ] Test Cloud Functions via emulator
- [ ] Test real-time message sync across both accounts
- [ ] Verify unread badges, pagination, image uploads

---

## Deliverables Checklist

- [ ] TabView root with 3 tabs
- [ ] 10 new Swift files (models, services, views, utilities)
- [ ] 2 Cloud Functions deployed
- [ ] FirebaseStorage integrated
- [ ] DMs + group chats functional
- [ ] Image attachments working
- [ ] Link previews rendering
- [ ] Unread badges + read receipts
- [ ] Push notifications wired (works once APNs configured)
- [ ] Deep-link router
- [ ] "Message" button on contacts
