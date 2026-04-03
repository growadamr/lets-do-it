# Let's do it! - Couples Activity Matching App

An iOS app that helps couples discover shared activities through a simple, playful matching game. Two partners connect via invite codes, then tap activities they're interested in. When both partners select the same activity, they both receive an in-app alert (and push notification if FCM tokens are available) to do it together.

---

## Features

- **Anonymous Authentication** — Users sign in anonymously via Firebase, preserving privacy
- **Display Name** — Users set a name on first launch for friendlier match alerts
- **Invite Code Pairing** — 6-digit codes to connect with your partner (10-minute expiry)
- **Activity Selection** — Categorized list of activities (walks, movies, coffee, etc.)
- **Smart Matching** — Cloud Functions detect when both partners select the same item
- **In-App Match Alerts** — Real-time SwiftUI alert when a match is detected
- **Push Notifications (Optional)** — FCM push sent if tokens exist; graceful fallback to in-app only
- **Match History** — Browse your recent matched activities
- **Real-time Sync** — Selections sync automatically between devices

---

## Project Structure

```
hermGameTest/
├── LetsDoIt/                        # Xcode project
│   ├── LetsDoIt.xcodeproj
│   └── LetsDoIt/
│       ├── LetsDoItApp.swift        # App entry point with Firebase initialization
│       ├── AppDelegate.swift        # FCM token handling
│       ├── GoogleService-Info.plist # Firebase config (download from Firebase Console)
│       ├── Assets.xcassets/
│       ├── Models/                  # Data models
│       │   ├── ActivityItem.swift
│       │   └── ActivityCatalog.swift
│       ├── Services/                # Business logic
│       │   ├── AuthManager.swift
│       │   ├── PairingManager.swift
│       │   ├── SelectionManager.swift
│       │   └── MatchListener.swift
│       └── Views/                   # SwiftUI screens
│           ├── RootView.swift
│           ├── HomeView.swift
│           ├── CreateCodeView.swift
│           ├── JoinCodeView.swift
│           ├── SetNameView.swift
│           ├── ActivityListView.swift
│           ├── ActivityRow.swift
│           └── MatchHistoryView.swift

functions/
├── index.js                         # Firebase Cloud Functions
├── package.json
└── node_modules/
```

---

## Architecture

### Client (iOS)
- **SwiftUI** — Modern declarative UI framework
- **Firebase SDK** — Authentication, Firestore, Cloud Messaging
- **Combine** — Reactive data flow with `@Published` properties

### Server (Cloud Functions)
- **Node.js/JavaScript** — Server-side logic
- **Firestore Triggers** — `onSelectionCreated` detects new selections with transaction guard
- **Scheduled Functions** — `sendPendingNotifications` (every 1 min), `cleanupExpiredSelections` (every 15 min)
- **FCM Integration** — Sends push notifications if FCM tokens exist; graceful no-op otherwise

### Data Model

```
users/{userId}
  - displayName: String
  - fcmToken: String
  - pairedWith: String? (nullable)
  - pairId: String? (nullable)
  - createdAt: Timestamp

pairs/{pairId}
  - userA: String
  - userB: String
  - createdAt: Timestamp
  - active: Boolean

inviteCodes/{code}
  - createdBy: String
  - createdAt: Timestamp
  - expiresAt: Timestamp
  - used: Boolean

pairs/{pairId}/selections/{selectionId}
  - userId: String
  - itemId: String
  - createdAt: Timestamp
  - expiresAt: Timestamp (60 min from creation)
  - matched: Boolean

pendingNotifications/{notificationId}
  - pairId: String
  - itemId: String
  - userAId: String
  - userBId: String
  - sendAt: Timestamp
  - sent: Boolean
```

---

## Activity Catalog

### Activities
- 🚶 Go for a walk?
- 💪 Work out?
- 🎬 Watch a movie?
- 🍳 Cook together?
- 🎮 Play a game?
- 🚗 Go for a drive?

### Places
- 🍽️ Go out to eat?
- ☕ Hit a café?
- 🌳 Go to the park?
- 🏖️ Go to the beach?
- 🛒 Go shopping?

### General
- 🍻 Drinks?
- ☕ Coffee?
- 🍿 Snack?
- 💬 Just talk?
- 😴 Nap time?

---

## How It Works

1. **User A** creates an invite code (6-digit, 10-minute expiry)
2. **User B** enters the code on their device
3. Both users set display names and are now paired
4. Each user taps activities they're interested in (checkmark appears)
5. When **both** users select the same activity within 60 minutes of the first selection:
   - Cloud Function detects the match (inside a transaction to prevent races)
   - Both selections marked `matched: true`
   - A pending notification is created with random 1–15 minute delay
   - Both users receive an **in-app alert** immediately when `matched` is detected
   - Push notifications are also sent if FCM tokens are available
   - After a match fires, users can re-select the same item for a new match

---

## How Pairing Works

```
User A                          Firebase                         User B
  │                               │                               │
  ├─── Create Invite Code ──────►│                               │
  │    (6-digit, 10min)          │                               │
  │                               │                               │
  │◄── Code: 123456 ────────────│                               │
  │                               │                               │
  │                               │◄── Enter Code: 123456 ────────┤
  │                               │    (User B joins)             │
  │                               │                               │
  │◄── Pair Created ◄────────────┼────────── Pair Created ────────┤
  │    (real-time listener)      │    (real-time listener)        │
  │                               │                               │
  │  "Connected with [name]"     │                               │
  │                               │                               │
```

---

## How Match Detection Works

```
1. User A taps "Coffee"
   → Firestore: selection doc created (userId=A, itemId="coffee", matched=false)
   → Cloud Function fires: checks if User B has active "coffee" selection
   → User B has NOT selected "coffee" → no match → function exits

2. (20 minutes later) User B taps "Coffee"
   → Firestore: selection doc created (userId=B, itemId="coffee", matched=false)
   → Cloud Function fires: checks if User A has active "coffee" selection
   → User A's selection is still active (within 60-min window) → MATCH!
   → Both selections marked matched=true (inside transaction)
   → pendingNotification created with sendAt = now + random(1-15min)

3. MatchListener (client-side) detects matched=true → shows in-app alert

4. (random delay later) Scheduled function runs
   → Finds the pending notification where sendAt <= now
   → Sends push to both users (if FCM tokens exist)
   → Marks notification as sent
```

---

## Development Status

### Completed Phases

| Phase | Status | Description |
|-------|--------|-------------|
| Phase 1 | ✅ | Xcode project setup, Firebase integration, anonymous auth |
| Phase 2 | ✅ | Pairing system with invite codes + display name |
| Phase 3 | ✅ | Activity list UI and selection logic |
| Phase 4 | ✅ | Cloud Functions for match detection (with transaction guard) |
| Phase 5 | ✅ | In-app match alerts via Firestore listener |
| Phase 6 | ✅ | Race condition fix, cleanup function, match history, polish |

---

## Setup Instructions

### Prerequisites
- Xcode 16+
- iOS 17+ simulator/device
- Firebase account
- Firebase project: `herm-app-7555c`

### 1. Open Xcode Project
- Open `LetsDoIt.xcodeproj` in Xcode
- Set your **Team** and **Bundle ID** in the target settings
- Set **Bundle ID** to: `com.letsdoit.app`
- Add Firebase SDK via SPM: `https://github.com/firebase/firebase-ios-sdk`
  - Libraries: `FirebaseAuth`, `FirebaseFirestore`, `FirebaseMessaging`

### 2. Firebase Configuration
- Download `GoogleService-Info.plist` from Firebase Console for bundle ID `com.letsdoit.app`
- Place it in `LetsDoIt/LetsDoIt/`
- Enable **Anonymous Auth** in Firebase Console → Authentication
- Enable **Cloud Messaging** in Firebase Console (for FCM)

### 3. Set Up Cloud Functions
```bash
cd /Users/adamgrow/hermGameTest
npm install -g firebase-tools
firebase login
firebase deploy --only functions
```

### 4. Create Firestore Composite Index
The match detection query requires a composite index. After deploying functions, trigger a match and check the Firebase Functions logs — Firestore will provide a direct link to create the index.

Or create manually in Firebase Console → Firestore → Indexes → Composite:

| Collection Path | Fields | Order |
|----------------|--------|-------|
| `pairs/{pairId}/selections` | `userId` Asc, `itemId` Asc, `matched` Asc, `expiresAt` Asc | — |

### 5. Set Firestore Security Rules (Production)
See `phase-6-polish-and-testing.md` Step 6.1 for the production rules.

---

## Technical Notes

### Xcode Compatibility
- No manual `Info.plist` — Xcode auto-generates it
- All files using `@Published` must include `import Combine`
- Project uses `PBXFileSystemSynchronizedRootGroup` for auto-sync

### Push Notifications
- FCM push notifications are sent if the user's FCM token exists
- If no token is available, the function logs the match to console only
- In-app alerts (via `MatchListener`) always fire regardless of push notification status
- This means the app works without Apple Push Notification support

### Important Files
- `LetsDoItApp.swift` — App entry with Firebase initialization
- `AuthManager.swift` — Handles anonymous sign-in and user docs
- `PairingManager.swift` — Invite code generation and pairing logic
- `SelectionManager.swift` — Activity selection and expiry handling
- `MatchListener.swift` — Real-time match detection and in-app alerts
- `functions/index.js` — Cloud Functions for match detection with transaction guard

---

## Security Considerations

### Current State (Development)
- Firestore rules should allow any authenticated user to read/write
- Invite codes expire after 10 minutes
- Users can only be paired once

### Production Hardening (Phase 6)
- Restrict Firestore rules to pair-specific access (see phase-6 plan)
- Implement rate limiting on invite code generation
- Consider adding biometric auth

---

## Troubleshooting

### Build Errors
- **Missing `import Combine`**: Any file using `@Published` needs this import
- **Info.plist conflicts**: Don't create one manually — Xcode handles it
- **Firestore index errors**: Click the link in the error to create the index

### Runtime Errors
- **No match detected**: Verify both users are in the same pair, selections are unexpired
- **Pairing fails**: Verify both users are anonymous and not already paired
- **Selections not syncing**: Check Firestore listener is active in `SelectionManager`
- **No push notifications**: Check FCM token is saved in user document; check Cloud Messaging is enabled

---

## License

This project is for educational and personal use.

---

## Credits

Built with:
- SwiftUI for the UI
- Firebase for backend services
- Cloud Functions for serverless logic
