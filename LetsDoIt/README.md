# Let's Do It — Project Docs

## Overview
A SwiftUI iOS app for two people to discover shared activities. Both users tap the same activity within a 60-minute window and get notified of the match.

## Tech Stack
| Layer | Technology |
|---|---|
| UI | SwiftUI (NavigationStack) |
| Language | Swift 5, iOS 26.2 |
| Backend | Firebase (Auth, Firestore, Cloud Functions, FCM) |
| Dependency Management | SPM (Firebase v12.11.0) |

## Firestore Structure

### `users/{userId}`
- `displayName` — user's chosen name
- `fcmToken` — push notification token
- `createdAt` — server timestamp

### `users/{userId}/contacts/{contactUid}`
- `uid` — Firebase Auth UID of the contact
- `displayName` — name this user gave the contact (empty until set)
- `addedAt` — server timestamp

### `users/{userId}/selections/{selectionId}`
- `userId` — who made the selection
- `targetUserId` — which contact they selected with
- `itemId` — activity ID (e.g. "walk", "drinks")
- `createdAt` — when selected
- `expiresAt` — 60 minutes from creation
- `matched` — boolean, set to true by Cloud Function

### `inviteCodes/{code}`
- `createdBy` — UID of code creator
- `createdAt`, `expiresAt` (24hr expiry), `used`

### `pendingNotifications/{docId}`
- `userId`, `targetUserId`, `itemId`
- `sendAt` — when to notify (random 1-10 min delay)
- `sent` — boolean
- `createdAt`

## Cloud Functions (`functions/index.js`)

### `checkForMatches` — every 5 minutes
Scans all active unmatched selections across all users. Finds pairs where both users selected the same item targeting each other within the 60-minute window. Marks both as `matched: true` and creates a pending notification.

### `sendPendingNotifications` — every 1 minute
Processes `pendingNotifications` where `sendAt <= now` and `sent == false`. Attempts FCM push to both users, then marks as sent.

### `onContactAdded` — on document creation
Creates the reverse contact entry automatically (bidirectional contacts).

### `cleanupExpiredSelections` — every 15 minutes
Deletes expired unmatched selections, matched selections older than 24 hours, and all processed/stale pending notifications.

## How Matching Works
1. User A selects a contact → picks activities
2. User B (the contact) independently selects User A → picks activities
3. Every 5 minutes, `checkForMatches` scans for overlaps
4. If both selected the same activity targeting each other within 60 minutes → match
5. Push notification sent with 1-10 minute random delay

## Push Notifications — Not Yet Working
Push notifications are fully wired in Cloud Functions (FCM) and the app captures FCM tokens. However, **APNs requires a paid Apple Developer account** ($99/year). Until then, push notifications will not reach devices. The infrastructure is ready — once the paid account is added, notifications will start working immediately with no code changes needed.

## Key Files
| File | Purpose |
|---|---|
| `Services/ContactManager.swift` | Contacts CRUD, per-contact selections |
| `Services/MatchListener.swift` | Legacy real-time listener (inactive) |
| `Services/AuthManager.swift` | Anonymous auth, user doc creation |
| `Views/HomeView.swift` | Main screen, contact selection gate |
| `Views/ContactsListView.swift` | Contact list, add via code |
| `Views/SetContactNameSheet.swift` | Name entry for new contacts |
| `Views/ActivityListView.swift` | Activity tap-to-select |
| `Views/MatchHistoryView.swift` | Historical matches per contact |
