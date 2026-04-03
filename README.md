# Let's do it!

An iOS app that helps couples discover shared activities through a blind matching game. Both partners independently select activities they're interested in, and when their choices align, they both get notified.

## Overview

Two people connect via a short-lived invite code. Each sees the same catalog of activities — things like "Go for a walk," "Watch a movie," or "Grab coffee." They tap what sounds good to them, **without seeing what their partner picked**. When both select the same item within a 60-minute window, both receive an in-app alert: *"It's a match! You both want: Coffee."*

The design prevents either person from knowing the other's interest until a mutual match occurs, making it feel like a genuine coincidence rather than a planned suggestion.

## Key Features

| | |
|---|---|
| **Anonymous Auth** | No account required — sign in instantly with Firebase anonymous auth |
| **Invite Code Pairing** | Connect with your partner via a 6-digit code (10-minute expiry) |
| **Blind Activity Selection** | Pick activities independently — no peeking |
| **Real-Time Match Alerts** | In-app alert fires the moment a match is detected |
| **Optional Push Notifications** | FCM push sent when tokens are available; works fully without it |
| **Match History** | Browse your past matches with timestamps |
| **Automatic Cleanup** | Expired selections are purged server-side every 15 minutes |

## Tech Stack

| Layer | Technology |
|-------|-----------|
| **iOS Client** | Swift + SwiftUI (iOS 17+) |
| **Backend** | Firebase — Firestore, Cloud Functions, Cloud Messaging |
| **Authentication** | Firebase Anonymous Auth |
| **State Management** | Combine (`@Published`, `@StateObject`, `@ObservedObject`) |
| **Cloud Runtime** | Node.js 24 (Firebase Functions v2) |

## Architecture

```
┌──────────┐                        ┌──────────┐
│  User A  │                        │  User B  │
│  (iOS)   │                        │  (iOS)   │
└────┬─────┘                        └────┬─────┘
     │  writes selection                  │  writes selection
     ▼                                    ▼
┌────────────────────────────────────────────────┐
│              Firebase Firestore                │
│  pairs/{pairId}/selections/{selectionId}       │
└────────────────────┬───────────────────────────┘
                     │  onCreate trigger
                     ▼
┌────────────────────────────────────────────────┐
│          Firebase Cloud Function               │
│                                                │
│  onSelectionCreated (transaction-guarded)      │
│  1. Query partner's active selections          │
│  2. If same item → mark both matched           │
│  3. Create pending notification (1–15 min)     │
└────────┬───────────────────────┬───────────────┘
         │                       │
         ▼                       ▼
┌─────────────────┐   ┌───────────────────────┐
│  MatchListener  │   │  Scheduled Functions  │
│  (client)       │   │                       │
│                 │   │  sendPendingNotifs    │
│  Detects        │   │  cleanupExpired       │
│  matched=true   │   │  (every 15 min)       │
│  → in-app alert │   │                       │
└─────────────────┘   └───────────────────────┘
```

## Project Structure

```
├── LetsDoIt/                        # iOS application
│   ├── LetsDoIt.xcodeproj
│   └── LetsDoIt/
│       ├── LetsDoItApp.swift        # Entry point, Firebase init
│       ├── AppDelegate.swift        # FCM / remote notification delegate
│       ├── Models/
│       │   ├── ActivityItem.swift   # Activity data model
│       │   └── ActivityCatalog.swift # 16 predefined activities
│       ├── Services/
│       │   ├── AuthManager.swift    # Anonymous auth + user lifecycle
│       │   ├── PairingManager.swift # Invite code + pair management
│       │   ├── SelectionManager.swift # Activity selection + expiry
│       │   └── MatchListener.swift  # Real-time match detection
│       └── Views/
│           ├── RootView.swift       # Auth gate
│           ├── HomeView.swift       # Main screen (paired/unpaired)
│           ├── CreateCodeView.swift # Generate invite code
│           ├── JoinCodeView.swift   # Enter partner's code
│           ├── SetNameView.swift    # Display name onboarding
│           ├── ActivityListView.swift # Categorized activity list
│           ├── ActivityRow.swift    # Individual row component
│           └── MatchHistoryView.swift # Past matches
├── functions/
│   ├── index.js                     # Cloud Functions (3 functions)
│   └── package.json
├── firebase.json
├── .firebaserc
├── README.md
└── SETUP.md                         # Step-by-step setup guide
```

## Getting Started

See **[SETUP.md](SETUP.md)** for the complete step-by-step guide.

**Quick summary:**

1. Clone the repo and open `LetsDoIt/LetsDoIt.xcodeproj`
2. Add Firebase SDK via SPM: `https://github.com/firebase/firebase-ios-sdk`
3. Register your bundle ID in Firebase Console and download `GoogleService-Info.plist`
4. Enable Anonymous Auth and Cloud Messaging
5. Deploy functions: `firebase deploy --only functions`
6. Build and run (Cmd+R)

## Firestore Data Model

<details>
<summary><strong>users/{userId}</strong></summary>

| Field | Type | Description |
|---|---|---|
| `displayName` | String | User-chosen name |
| `fcmToken` | String | Firebase Cloud Messaging token |
| `pairedWith` | String? | Partner's userId |
| `pairId` | String? | Reference to the pair document |
| `createdAt` | Timestamp | Account creation time |
</details>

<details>
<summary><strong>pairs/{pairId}</strong></summary>

| Field | Type | Description |
|---|---|---|
| `userA` | String | First user's userId |
| `userB` | String | Second user's userId |
| `createdAt` | Timestamp | Pair creation time |
| `active` | Boolean | Whether the pair is still active |
</details>

<details>
<summary><strong>pairs/{pairId}/selections/{selectionId}</strong></summary>

| Field | Type | Description |
|---|---|---|
| `userId` | String | Who made the selection |
| `itemId` | String | Activity ID (e.g., "coffee") |
| `createdAt` | Timestamp | Selection time |
| `expiresAt` | Timestamp | 60 minutes after creation |
| `matched` | Boolean | True when a match fires |
</details>

<details>
<summary><strong>inviteCodes/{code}</strong></summary>

| Field | Type | Description |
|---|---|---|
| `createdBy` | String | Creator's userId |
| `createdAt` | Timestamp | Code creation time |
| `expiresAt` | Timestamp | 10 minutes after creation |
| `used` | Boolean | True after someone joins |
</details>

<details>
<summary><strong>pendingNotifications/{notifId}</strong></summary>

| Field | Type | Description |
|---|---|---|
| `pairId` | String | The pair reference |
| `itemId` | String | The matched activity ID |
| `userAId` | String | First user's userId |
| `userBId` | String | Second user's userId |
| `sendAt` | Timestamp | Scheduled delivery time (1–15 min delay) |
| `sent` | Boolean | True after the function delivers |
</details>

## Cloud Functions

| Function | Trigger | Description |
|---|---|---|
| `onSelectionCreated` | Firestore onCreate | Detects matches using a transaction to prevent race conditions. Marks both selections as matched and creates a pending notification. |
| `sendPendingNotifications` | Schedule (every 1 min) | Delivers queued match notifications via FCM. Graceful no-op if no tokens exist. |
| `cleanupExpiredSelections` | Schedule (every 15 min) | Deletes expired, unmatched selections across all active pairs. |

## Design Decisions

**No APNs dependency** — The app uses in-app alerts as the primary match notification mechanism via `MatchListener`, a real-time Firestore listener. FCM push is sent as a secondary channel when tokens are available, but the app is fully functional without it. This removes the requirement for a paid Apple Developer account.

**Transaction-guarded matching** — The `onSelectionCreated` function runs inside a Firestore transaction to prevent duplicate matches when both users select the same item at nearly the same instant.

**Random notification delay** — A 1–15 minute random delay is applied to each match notification so neither user can infer *when* their partner tapped, preserving the illusion of a genuine coincidence.

**60-minute expiry** — Selections expire one hour after creation, enforced both client-side (UI checkmark removal) and server-side (scheduled cleanup function).

## License

Personal use.
