# Phase 0: Project Overview & Architecture

## App Name: "Let's do it!"

## Concept
Two users pair together. Each sees a shared list of activities/places/items (e.g., "Drinks?", "Coffee?", "Go for a walk?"). Each user independently taps items they're interested in. **Neither user knows what the other has selected.** If both users select the same item within a 60-minute window, both receive an in-app alert — after a random delay — telling them they should do that thing together.

## Core Rules
1. **Blind selection**: A user never sees what their partner has selected.
2. **60-minute match window**: A selection expires 60 minutes after it was made. Both selections must be active (unexpired) simultaneously for a match to occur.
3. **Random notification delay**: When a match is detected, the notification is not sent immediately. A random delay of 1–15 minutes is added so that neither user can infer *when* the other person tapped.
4. **One-time match**: Once a match fires for a given item, both selections are cleared. Users can re-select the same item later for a new match.

## Tech Stack

| Layer | Technology | Why |
|-------|-----------|-----|
| iOS Client | Swift + SwiftUI | Modern Apple-native UI framework |
| Backend | Firebase (Firestore + Cloud Functions + FCM) | Real-time sync, serverless functions, push notifications — minimal ops overhead |
| Auth | Firebase Anonymous Auth → Display Name | Quick onboarding; friendly match alerts |
| Notifications | In-app alerts (primary) + FCM push (optional) | Works without paid Apple Developer account |
| Pairing | 6-digit invite code (short-lived) | Simple UX for connecting two users |

## Architecture Diagram (Logical)

```
┌──────────────┐         ┌──────────────┐
│   User A     │         │   User B     │
│  (iOS App)   │         │  (iOS App)   │
└──────┬───────┘         └──────┬───────┘
       │  writes selection       │  writes selection
       ▼                         ▼
┌─────────────────────────────────────────┐
│           Firebase Firestore            │
│                                         │
│  /pairs/{pairId}/selections/{selId}     │
│    - userId, itemId, timestamp, matched │
└──────────────────┬──────────────────────┘
                   │  Firestore trigger (onCreate)
                   ▼
┌─────────────────────────────────────────┐
│        Firebase Cloud Function          │
│  "onSelectionCreated"                   │
│                                         │
│  1. Query: other user selected same     │
│     item within 60-min window?          │
│  2. If yes → mark both matched          │
│     (transaction for race safety)       │
│  3. Create pending notification with    │
│     random delay (1-15 min)             │
└──────────────────┬──────────────────────┘
                   │
        ┌──────────┴──────────┐
        ▼                     ▼
┌─────────────────┐  ┌─────────────────────┐
│ MatchListener   │  │ Scheduled Function  │
│ (client-side)   │  │ (every 1 min)       │
│                 │  │                     │
│ Detects         │  │ Sends FCM push      │
│ matched=true    │  │ if tokens exist     │
│ → in-app alert  │  │                     │
└─────────────────┘  └─────────────────────┘
```

## Data Model (Firestore)

### Collection: `users`
```
/users/{userId}
{
  displayName: string,
  fcmToken: string,
  pairedWith: string | null,      // other userId
  pairId: string | null,          // reference to /pairs doc
  createdAt: timestamp
}
```

### Collection: `pairs`
```
/pairs/{pairId}
{
  userA: string,                  // userId
  userB: string,                  // userId
  createdAt: timestamp,
  active: boolean
}
```

### Subcollection: `pairs/{pairId}/selections`
```
/pairs/{pairId}/selections/{selectionId}
{
  userId: string,
  itemId: string,                 // e.g., "drinks", "coffee"
  createdAt: timestamp,
  expiresAt: timestamp,           // createdAt + 60 min
  matched: boolean                // set to true when match fires
}
```

### Collection: `inviteCodes`
```
/inviteCodes/{code}
{
  createdBy: string,              // userId
  createdAt: timestamp,
  expiresAt: timestamp,           // short-lived, e.g., 10 min
  used: boolean
}
```

### Collection: `pendingNotifications`
```
/pendingNotifications/{notifId}
{
  pairId: string,
  itemId: string,
  userAId: string,
  userBId: string,
  sendAt: timestamp,              // createdAt + random(1-15 min)
  sent: boolean
}
```

## Phase Breakdown

| Phase | Focus | Deliverable | Status |
|-------|-------|-------------|--------|
| 1 | Xcode project setup, Firebase integration, auth | App launches, user is authenticated | ✅ Completed |
| 2 | Pairing system (invite codes) + display name | Two users can connect | ✅ Completed |
| 3 | Activity list UI + selection logic | Users can tap items, selections stored in Firestore | ✅ Completed |
| 4 | Match detection (Cloud Function) | Backend detects when both users pick the same item | ✅ Completed |
| 5 | In-app match alerts | Both users see an in-app alert when a match occurs | ✅ Completed |
| 6 | Polish, race condition fix, match history, cleanup | Production-ready app | ✅ Completed |

## Deviation from Original Plan
- **No Apple Push Notifications (APNs)** — Skipped because the developer account doesn't support APNs. Instead, the app uses in-app alerts via `MatchListener` (Firestore real-time listener). FCM push is still sent if tokens are available, but the app works fully without it.
- **App renamed** from "Herm" to "Let's do it!"
