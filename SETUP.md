# Setup Guide — "Let's do it!"

## What Was Done ✅

All 6 phases of the app are fully implemented. Here's the complete file inventory:

```
LetsDoIt/LetsDoIt/
├── LetsDoItApp.swift              # App entry point
├── AppDelegate.swift              # FCM delegate (push is optional)
├── Models/
│   ├── ActivityItem.swift         # Activity data model
│   └── ActivityCatalog.swift      # 16 activities across 3 categories
├── Services/
│   ├── AuthManager.swift          # Anonymous auth + user doc
│   ├── PairingManager.swift       # Invite codes + pairing
│   ├── SelectionManager.swift     # Activity selection + expiry
│   └── MatchListener.swift        # In-app match alerts
└── Views/
    ├── RootView.swift             # Auth gate
    ├── HomeView.swift             # Main screen (paired/unpaired)
    ├── CreateCodeView.swift       # Generate invite code
    ├── JoinCodeView.swift         # Enter invite code
    ├── SetNameView.swift          # Display name entry
    ├── ActivityListView.swift     # Categorized activity list
    ├── ActivityRow.swift          # Individual activity row
    └── MatchHistoryView.swift     # Past matches list

functions/
└── index.js                       # 3 Cloud Functions (match detection, scheduled push, cleanup)
```

## What You Need To Do

### Step 1 — Create Xcode Project

1. Open Xcode → **File → New → Project**
2. Choose **App** (iOS, SwiftUI)
3. Settings:
   - **Product Name**: `LetsDoIt`
   - **Team**: Select your team (or "None" for now)
   - **Organization Identifier**: `com.letsdoit`
   - **Bundle ID** will become: `com.letsdoit.app` (verify in target settings)
   - **Interface**: SwiftUI
   - **Language**: Swift
   - **Storage**: None
   - **Uncheck** "Include Tests"
4. **Save** into: `/Users/adamgrow/hermGameTest/` (this will create the `LetsDoIt.xcodeproj` inside the existing `LetsDoIt/` folder)
5. When Xcode opens, verify the file navigator shows the `LetsDoIt/` folder with all the Swift files listed above.

### Step 2 — Add Firebase SDK via Swift Package Manager

1. In Xcode → **File → Add Package Dependencies**
2. Enter URL: `https://github.com/firebase/firebase-ios-sdk`
3. Set dependency rule to **Up to Next Major Version** (latest)
4. Select these libraries:
   - `FirebaseAuth`
   - `FirebaseFirestore`
   - `FirebaseMessaging`
5. Click **Add Package** and wait for resolution.

### Step 3 — Register iOS App in Firebase Console

1. Go to [Firebase Console](https://console.firebase.google.com/) → project **herm-app-7555c**
2. Click **Add app → iOS**
3. Enter Bundle ID: **`com.letsdoit.app`**
4. Download the `GoogleService-Info.plist` file
5. Drag `GoogleService-Info.plist` into Xcode → `LetsDoIt/LetsDoIt/` folder (check "Copy items if needed", add to `LetsDoIt` target)

### Step 4 — Enable Firebase Services

In Firebase Console for project `herm-app-7555c`:

1. **Authentication → Sign-in method → Enable Anonymous** → Save
2. **Firestore Database → Create database** (if not already created)
   - Start in **test mode** (we'll lock it down later)
3. **Cloud Messaging → Enable** (for FCM push support)

### Step 5 — Set Firestore Security Rules (Development)

In Firebase Console → **Firestore Database → Rules**:

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /{document=**} {
      allow read, write: if request.auth != null;
    }
  }
}
```

> **Important**: These are dev-only rules. Lock them down before production (see phase-6-polish-and-testing.md Step 6.1).

### Step 6 — Deploy Cloud Functions

```bash
cd /Users/adamgrow/hermGameTest
firebase login
firebase deploy --only functions
```

Verify in Firebase Console → **Functions** that these appear:
- `onSelectionCreated` (Firestore trigger)
- `sendPendingNotifications` (Scheduled, every 1 min)
- `cleanupExpiredSelections` (Scheduled, every 15 min)

### Step 7 — Create Firestore Composite Index

The match detection query needs a composite index. After deploying functions:

1. Trigger a match (select the same activity on two devices)
2. Check Firebase Console → **Functions → Logs** for an error with a direct link to create the index
3. **Click the link** to create it automatically

Or create manually in **Firestore → Indexes → Composite**:
- Collection: `pairs/{pairId}/selections`
- Fields: `userId` (Ascending), `itemId` (Ascending), `matched` (Ascending), `expiresAt` (Ascending)

### Step 8 — Build and Run

1. In Xcode, select a simulator (iPhone 15 or similar)
2. **Cmd+R** to build and run
3. You should see: "Signing in..." → then the "Let's do it!" home screen with pairing options

### Step 9 — Test the Full Flow

You'll need **two devices or simulators**:

1. **Device A**: Tap "Create Invite Code" → copy the 6-digit code
2. **Device B**: Set a display name → tap "Enter a Code" → paste the code → Connect
3. Both should see "Connected with [name]" and the activity list
4. Tap some activities on each device — checkmarks appear
5. When both select the same item → both see "It's a match!" alert
6. Check Firestore: both selections should have `matched: true`, and a `pendingNotifications` doc should exist

---

## Quick Reference

| Item | Value |
|------|-------|
| **App Name** | Let's do it! |
| **Bundle ID** | `com.letsdoit.app` |
| **Firebase Project** | `herm-app-7555c` |
| **Xcode Project Path** | `/Users/adamgrow/hermGameTest/LetsDoIt/LetsDoIt.xcodeproj` |
| **Source Files Path** | `/Users/adamgrow/hermGameTest/LetsDoIt/LetsDoIt/` |
| **Functions Path** | `/Users/adamgrow/hermGameTest/functions/index.js` |

## Known Deviations from Original Plan

- **No Apple Push Notifications** — The app uses in-app alerts via `MatchListener`. FCM push is sent if tokens exist but the app works fully without it.
- **App renamed** from "Herm" to "Let's do it!"
- **Bundle ID**: `com.letsdoit.app` (was `com.test.Herm`)
