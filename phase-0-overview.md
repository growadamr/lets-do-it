# Phase 0: Project Overview & Architecture

## App Name (Working Title): "Herm"

## Concept
Two users pair together. Each sees a shared list of activities/places/items (e.g., "Drinks?", "Coffee?", "Go for a walk?"). Each user independently taps items they're interested in. **Neither user knows what the other has selected.** If both users select the same item within a 60-minute window, both receive a push notification — after a random delay — telling them they should do that thing together.

## Core Rules
1. **Blind selection**: A user never sees what their partner has selected.
2. **60-minute match window**: A selection expires 60 minutes after it was made. Both selections must be active (unexpired) simultaneously for a match to occur.
3. **Random notification delay**: When a match is detected, the notification is not sent immediately. A random delay of 1–15 minutes is added so that neither user can infer *when* the other person tapped.
4. **One-time match**: Once a match fires for a given item, both selections are cleared. Users can re-select the same item later for a new match.

## Tech Stack

| Layer | Technology | Why |
|-------|-----------|-----|
| iOS Client | Swift + SwiftUI | Modern Apple-native UI framework |
| Backend | Firebase (Firestore + Cloud Functions + FCM) | Real-time sync, serverless functions, push notifications — minimal ops overhead for a simple app |
| Auth | Firebase Anonymous Auth → Apple Sign In | Quick onboarding; upgrade to real account later |
| Push Notifications | Firebase Cloud Messaging (FCM) via APNs | Industry standard for iOS push |
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
│    - userId, itemId, timestamp, active  │
└──────────────────┬──────────────────────┘
                   │  Firestore trigger (onCreate)
                   ▼
┌─────────────────────────────────────────┐
│        Firebase Cloud Function          │
│  "onSelectionCreated"                   │
│                                         │
│  1. Query: other user selected same     │
│     item within 60-min window?          │
│  2. If yes → schedule delayed notify    │
│  3. Mark both selections as matched     │
└──────────────────┬──────────────────────┘
                   │  after random delay (1-15 min)
                   ▼
┌─────────────────────────────────────────┐
│        Firebase Cloud Messaging         │
│  Push notification to both users        │
│  "You and [partner] both want: Drinks!" │
└─────────────────────────────────────────┘
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

## Phase 1: Completed ✅

**Completed:** Xcode project setup, Firebase integration, and anonymous auth

### Files:
- `Herm/Herm/HermApp.swift` — App entry point, calls `FirebaseApp.configure()`
- `Herm/Herm/Services/AuthManager.swift` — Singleton handling anonymous sign-in + Firestore user doc creation
- `Herm/Herm/Views/RootView.swift` — Root view with loading/error/home states
- `Herm/Herm/Views/HomeView.swift` — Placeholder home screen showing User ID
- `Herm/Herm/GoogleService-Info.plist` — Firebase config

### Implementation Details:
1. **Firebase Configuration:** `FirebaseApp.configure()` in `HermApp.init()`
2. **Auth Flow:** Anonymous auth via `Auth.auth().signInAnonymously()`, user doc created in `users` collection on first sign-in
3. **Xcode Project:** Uses `PBXFileSystemSynchronizedRootGroup` (Xcode 26) — files in `Herm/Herm/` are auto-synced, no need to manually add files to the project
4. **Bundle ID:** `com.test.Herm`
5. **Firebase Project:** `herm-app` (Analytics enabled)

### Lessons Learned:
- Xcode 26 auto-generates `Info.plist` — do NOT include a manual `Info.plist` file or it will cause duplicate output build errors
- Files using `@Published` require `import Combine` in Xcode 26 (strict member import visibility)
- The correct Firebase anonymous auth API is `Auth.auth().signInAnonymously()` (not `signIn(anonymously: true)`)
- Xcode 26 uses synchronized root groups — only one copy of each file should exist; duplicate files across folders cause "invalid redeclaration" errors

---

## Phase Breakdown

| Phase | Focus | Deliverable | Status |
|-------|-------|-------------|--------|
| 1 | Xcode project setup, Firebase integration, auth | App launches, user is authenticated | ✅ Completed |
| 2 | Pairing system (invite codes) | Two users can connect | 🔜 Next |
| 3 | Activity list UI + selection logic | Users can tap items, selections stored in Firestore | Pending |
| 4 | Match detection (Cloud Function) | Backend detects when both users pick the same item | Pending |
| 5 | In-app match alerts | Both users see an alert when a match occurs (push notifications deferred — requires paid Apple Developer account) | Pending |
| 6 | Polish, edge cases, and testing | Production-ready app | Pending |
