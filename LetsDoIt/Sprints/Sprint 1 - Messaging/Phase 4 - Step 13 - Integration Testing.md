# Phase 4, Step 13: Integration Testing — Implementation Log

**Date:** 2026-04-05
**Status:** ⏳ Pending — Manual Testing Required

---

## What Was Done

### New Files Created

| File | Purpose |
|------|---------|
| `Sprints/Sprint 1 - Messaging/Phase 4 - Step 13 - Integration Testing.md` | This implementation log — structured test plan with pass/fail tracking |

### Files Modified

None.

---

## Overview

Step 13 is a **manual testing** step. No code changes are required. The deliverable is this structured test log documenting the results of end-to-end integration testing across two simulator instances, with Firestore document verification and Cloud Functions emulator validation.

---

## Test Setup Checklist

Complete before running test cases.

| # | Setup Step | Status | Notes |
|---|-----------|--------|-------|
| 1 | Two iOS simulators running (e.g., iPhone 17 + iPhone 17 Pro) | ☐ | |
| 2 | Anonymous auth signed in on both (different UIDs) | ☐ | |
| 3 | Both users have display names set (via `SetNameView`) | ☐ | |
| 4 | Firebase Emulator Suite running (`firebase emulators:start`) | ☐ | |
| 5 | Firestore Emulator UI accessible (usually `http://localhost:4000`) | ☐ | |
| 6 | Cloud Functions emulator running and visible in logs | ☐ | |

**User A UID:** `________________________`

**User B UID:** `________________________`

---

## Test Cases (14)

### Core Messaging Flow

| # | Test | Expected Result | Status | Notes |
|---|------|----------------|--------|-------|
| 1 | User A creates DM with User B | Conversation appears on both users' lists | ☐ Pass ☐ Fail | |
| 2 | User A sends text message to User B | Message appears on both screens in real-time | ☐ Pass ☐ Fail | |
| 3 | User B replies | Reply appears on User A's screen in real-time | ☐ Pass ☐ Fail | |
| 4 | User A sends image | Image uploads, appears on both screens, stored in Firestore Storage | ☐ Pass ☐ Fail | |
| 5 | User A sends message with URL | Link preview card renders on both screens | ☐ Pass ☐ Fail | |

### Unread Badges & Read Receipts

| # | Test | Expected Result | Status | Notes |
|---|------|----------------|--------|-------|
| 6 | User A opens conversation (badge clears), User B sends new message | Unread badge appears on User A's conversation list | ☐ Pass ☐ Fail | |
| 7 | User A taps conversation (opens chat) | Badge clears, messages marked as read | ☐ Pass ☐ Fail | |

### Group Conversations

| # | Test | Expected Result | Status | Notes |
|---|------|----------------|--------|-------|
| 8 | User A creates group with User B + User C (if 3rd account available) | Group appears on all participants' lists | ☐ Pass ☐ Fail ☐ N/A | |

### Mute & Delete

| # | Test | Expected Result | Status | Notes |
|---|------|----------------|--------|-------|
| 9 | User A swipes to mute a conversation | Mute icon updates, no notification (manual — verify FCM push suppressed) | ☐ Pass ☐ Fail | |
| 10 | User A deletes a conversation | Conversation removed from User A's list; User B's list unaffected | ☐ Pass ☐ Fail | |

### Pagination & Offline

| # | Test | Expected Result | Status | Notes |
|---|------|----------------|--------|-------|
| 11 | User A scrolls to top of long conversation | Older messages load via pagination (50 per page) | ☐ Pass ☐ Fail | |
| 12 | User A goes offline (Airplane Mode), sends message | Message shows "pending" state; syncs when reconnected | ☐ Pass ☐ Fail | |

### Deep Linking & Contacts

| # | Test | Expected Result | Status | Notes |
|---|------|----------------|--------|-------|
| 13 | Deep link: User A taps notification (simulated) | App opens to the correct conversation | ☐ Pass ☐ Fail | |
| 14 | User A taps "Message" on User B in Contacts | DM opens (or creates new one if first time) | ☐ Pass ☐ Fail | |

---

## Firestore Document Verification

Verify each field by inspecting documents in the Firestore Emulator UI or Firebase Console.

### `conversations/{id}`

| Field | Expected | Verified | Notes |
|-------|----------|----------|-------|
| `type` | `"dm"`, `"group"`, or `"event"` | ☐ | |
| `participants` | Array contains correct UIDs | ☐ | |
| `participantNames` | Map has UID → name entries for all participants | ☐ | |
| `lastMessage.text` | Matches most recent message (denormalized) | ☐ | |
| `lastMessage.timestamp` | Matches most recent message `createdAt` | ☐ | |
| `lastMessage.senderUid` | Matches sender UID | ☐ | |
| `lastMessage.senderName` | Matches sender display name | ☐ | |

### `conversations/{id}/messages/{id}`

| Field | Expected | Verified | Notes |
|-------|----------|----------|-------|
| `senderUid` | Matches sender | ☐ | |
| `senderName` | Matches sender display name at time of send | ☐ | |
| `text` | Matches message body | ☐ | |
| `createdAt` | Server timestamp (not client time) | ☐ | |
| `imageUrl` | Present if image was attached, absent/null otherwise | ☐ | |
| `linkPreview` | Present if message contained a URL, absent/null otherwise | ☐ | |
| `readBy` | Map populated with UID → Timestamp after read | ☐ | |

### `users/{uid}/conversationMemberships/{conversationId}`

| Field | Expected | Verified | Notes |
|-------|----------|----------|-------|
| `lastReadAt` | Updated when user opens conversation | ☐ | |
| `muted` | Toggles correctly (true/false) | ☐ | |
| `joinedAt` | Server timestamp, set at conversation creation | ☐ | |

### `users/{uid}`

| Field | Expected | Verified | Notes |
|-------|----------|----------|-------|
| `fcmToken` | Present after login (Step 11.4) | ☐ | |
| `displayName` | Present and matches app display name | ☐ | |

---

## Cloud Functions Emulator Test

| # | Test | Expected Result | Status | Notes |
|---|------|----------------|--------|-------|
| CF1 | Start emulator: `firebase emulators:start` | All functions load without errors | ☐ Pass ☐ Fail | |
| CF2 | Create a test conversation via Emulator UI → verify `onConversationCreated` fires | Membership docs created for all participants | ☐ Pass ☐ Fail | |
| CF3 | Create a test message via Emulator UI → verify `onMessageCreated` fires | `lastMessage` denormalized on conversation doc | ☐ Pass ☐ Fail | |
| CF4 | Check function logs for FCM push attempt | Logs show send attempt (even without real tokens) | ☐ Pass ☐ Fail | |
| CF5 | Idempotency: re-create the same conversation doc | No duplicate memberships, no errors | ☐ Pass ☐ Fail | |

---

## Bugs Found During Testing

| # | Bug Description | Severity | Status | Notes |
|---|----------------|----------|--------|-------|
| B1 | Conversation list permanently empty — composite index missing for `participants` + `lastMessage.timestamp` query | High | Fixed | Removed server-side `.order(by:)` from query; switched to client-side sort. Added `firestore.indexes.json` and deployed composite index as production solution |
| B2 | Conversations with no messages appear in list, showing "Unknown" and empty content | Medium | Fixed | Added `activeConversations` filter — only shows conversations where `lastMessage != nil`. Conversations now appear only after first message is sent |
| B3 | `isLoadingConversations` stuck on loading spinner forever when first snapshot is empty | Medium | Fixed | `isLoadingConversations` now observes raw `messagingManager.conversations` (unfiltered) via `onChange`, not `activeConversations` (filtered). Loading turns off even when result is empty |
| B4 | `isLoadingConversations` flips to `false` before data arrives, briefly showing empty state | Low | Fixed | Moved from synchronous `onAppear` reset to `onChange(of: messagingManager.conversations)` reactive reset |
| B5 | Conversation list shows "Unknown" for DM names — `fetchDisplayName` only checks `users/{uid}/displayName` (empty for anonymous auth), not ContactManager | Medium | Fixed | `ConversationsListView` resolves DM names from `ContactManager.contacts` first, then `participantNames` cache, then "Unknown" |
| B6 | `lastMessage` never denormalized — Cloud Functions `onMessageCreated` and `onConversationCreated` not deployed | High | Fixed | Upgraded Node.js runtime from 18→22, deployed both functions. Also deployed composite index for conversations query |
| B7 | `lastMessage.senderName` shows "Unknown" in conversation list — baked into message by sender, who has no display name | Medium | Fixed | `ConversationRow.lastMessageSnippet` resolves sender name from viewer's own contacts and participant names cache, not from the message doc |
| B8 | Message bubbles show "Unknown" above messages — same root cause as B7, applied in `ChatView` thread | Medium | Fixed | `ChatView` resolves sender names via `resolvedSenderName(for:)` helper using contacts → participantNames → "Unknown" chain. `MessageBubbleView` accepts optional `resolvedSenderName` parameter |
| B9 | Unread badges persist after viewing chat — `markAsRead()` only called on `onAppear`, not when navigating away after sending messages | Medium | Fixed | Added `markAsRead()` call in `ChatView.onDisappear` to catch up `membership.lastReadAt` after any messages sent during the session |
| B10 | `SetNameView` prompt may not show on first launch — `onAppear` fires before `authenticate()` completes | Low | Fixed | Moved `showSetName` check inside `authenticate()` after auth and user doc load complete |
| B11 | `SetContactNameSheet` doesn't pre-fill with contact's self-set name | Low | Fixed | Added `.task` that fetches `users/{uid}/displayName` and pre-fills text field. Shows contextual hint: "This person goes by 'Alice'. You can change it below." |
| B12 | Conversation listener decode errors silently swallowed — `try?` hides failures | Low | Fixed | Changed to `do/catch` with logged error messages for debugging |
| B13 | Duplicate `navigationDestination(for: Conversation.self)` in `ConversationsListView` (also provided by `MessagesTabView`) | Low | Fixed | Removed redundant modifier from `ConversationsListView` |

---

## Files Changed During Testing

### New Files

| File | Purpose |
|------|---------|
| `firebase/firestore.indexes.json` | Composite index: `participants` (ARRAY_CONTAINS) + `lastMessage.timestamp` (DESCENDING) |

### Modified Files

| File | Bugs Fixed | Change |
|------|-----------|--------|
| `firebase/firebase.json` | B1 | Added `"indexes"` reference to `firestore.indexes.json` |
| `firebase/functions/package.json` | B6 | Upgraded Node.js runtime from 18 → 22 |
| `Services/MessagingManager.swift` | B1, B12 | Removed `.order(by:)` from conversation query; changed `try?` to `do/catch` with logging; `fetchDisplayName` checks ContactManager first |
| `Views/Messaging/ConversationsListView.swift` | B2, B3, B4, B5, B7, B13 | `@StateObject ContactManager`; `activeConversations` filter; `onChange` reactive loading reset; contact-name resolution in `ConversationRow` title and snippet; removed dead code and duplicate `navigationDestination` |
| `Views/Messaging/ChatView.swift` | B8, B9 | `@StateObject ContactManager`; `resolvedSenderName(for:)` helper; `markAsRead()` on `onDisappear` |
| `Views/Messaging/MessageBubbleView.swift` | B8 | Added `resolvedSenderName` parameter (optional, falls back to `message.senderName`) |
| `Views/SetContactNameSheet.swift` | B11 | `.task` to fetch contact's self-set name and pre-fill; added `FirebaseFirestore` import |
| `Views/RootView.swift` | B10 | Moved `showSetName` check from `onAppear` to after `authenticate()` completes |

---

## Test Results Summary

| Category | Total | Pass | Fail | Skipped |
|----------|-------|------|------|---------|
| Core Messaging (1–5) | 5 | | | |
| Unread Badges (6–7) | 2 | | | |
| Group Conversations (8) | 1 | | | |
| Mute & Delete (9–10) | 2 | | | |
| Pagination & Offline (11–12) | 2 | | | |
| Deep Linking & Contacts (13–14) | 2 | | | |
| Firestore Verification | 17 fields | | | |
| Cloud Functions (CF1–CF5) | 5 | | | |
| **Total** | **36** | | | |

---

## Architecture Decisions

1. **Manual testing over automated UI tests** — The iOS simulator and Firebase Emulator provide a reliable environment for manual E2E testing. Automated UI tests (XCTest UI) would add maintenance overhead for a one-time integration verification pass. If regressions are found in future sprints, targeted automated tests should be added for the specific failure paths.

2. **Two-simulator approach for real-time sync** — Running two simulators simultaneously is the most accurate way to verify Firestore real-time listeners, since each simulator has an independent connection to the emulator and receives independent snapshot events.

3. **Firestore Emulator UI for document verification** — Using the Emulator UI (`http://localhost:4000`) provides a visual way to inspect document structure, field types, and subcollections. This is preferred over programmatic verification because it catches data type mismatches (e.g., `Timestamp` vs `Date`, `NSNull` vs missing fields) that code-level assertions might miss.

4. **Cloud Functions tested via Emulator UI writes** — Creating test documents directly in the Emulator UI triggers the same Cloud Functions as the app would, allowing verification of function triggers, logic, and logs without needing the app as an intermediary.

---

## How to Run These Tests

### Prerequisites

1. **Start Firebase Emulators:**
   ```bash
   cd /Users/adamgrow/hermGameTest/LetsDoIt
   firebase emulators:start
   ```

2. **Build and run the app on two simulators:**
   ```bash
   xcodebuild -scheme LetsDoIt -destination 'platform=iOS Simulator,name=iPhone 17' build run
   xcodebuild -scheme LetsDoIt -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build run
   ```

3. **Ensure app connects to emulators** — Verify `FirebaseApp.configure()` and any emulator configuration (usually in `AppDelegate` or `LetsDoItApp`) points to the local emulator host (`localhost`).

### Test Execution Order

Run tests in the order listed (1 through 14), as some tests build on state from previous ones:
- Test 1 creates the DM conversation needed for tests 2–7
- Test 8 requires a third user (optional)
- Tests 9–10 require an existing conversation
- Test 11 requires a conversation with enough messages to paginate (send ~55+ messages first)
- Test 12 requires network toggle capability in the simulator (Device → Airplane Mode)

---

## Build Verification

N/A — No code changes in this step. This is a manual testing document.
