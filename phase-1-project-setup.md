# Phase 1: Xcode Project Setup, Firebase Integration & Auth ✅ COMPLETED

## Goal
A running iOS app that launches, authenticates the user via Firebase Anonymous Auth, and stores the user document in Firestore.

> **Status:** Completed on 2026-04-02. App builds, runs on device, signs in anonymously, and creates user doc in Firestore.

---

## Step 1.1 — Create the Xcode Project

1. Open Xcode → **File → New → Project**.
2. Choose **App** under the iOS tab.
3. Settings:
   - Product Name: `Herm`
   - Team: your Apple Developer team
   - Organization Identifier: e.g., `com.yourname`
   - Interface: **SwiftUI**
   - Language: **Swift**
   - Storage: **None**
   - Uncheck "Include Tests" for now (we'll add in Phase 6)
4. Save into `/Users/adamgrow/hermGameTest/`.
5. Verify the project builds and runs on the iOS Simulator (choose iPhone 15 or similar).

---

## Step 1.2 — Create a Firebase Project

1. Go to [Firebase Console](https://console.firebase.google.com/).
2. Click **Add Project** → name it `herm-app` (or similar).
3. Disable Google Analytics (not needed for MVP).
4. Once created, click **Add app → iOS**.
5. Enter your **Bundle ID** (must match Xcode, e.g., `com.yourname.Herm`).
6. Download the `GoogleService-Info.plist` file.
7. Drag `GoogleService-Info.plist` into the Xcode project root (check "Copy items if needed", add to the `Herm` target).

---

## Step 1.3 — Add Firebase SDK via Swift Package Manager

1. In Xcode → **File → Add Package Dependencies**.
2. Enter URL: `https://github.com/firebase/firebase-ios-sdk`
3. Set dependency rule to **Up to Next Major Version** (use latest 11.x).
4. Select these libraries to add to your target:
   - `FirebaseAuth`
   - `FirebaseFirestore`
   - `FirebaseMessaging` (needed in Phase 5, but add now to avoid re-resolving later)
5. Click **Add Package** and wait for resolution.

---

## Step 1.4 — Configure Firebase on App Launch

Create or edit the app entry point file.

**File: `HermApp.swift`**

```swift
import SwiftUI
import FirebaseCore

@main
struct HermApp: App {
    init() {
        FirebaseApp.configure()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
```

---

## Step 1.5 — Create the Auth Manager

This singleton handles anonymous sign-in and exposes the current user.

**File: `AuthManager.swift`** (create in a new group called `Services`)

```swift
import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore

@MainActor
class AuthManager: ObservableObject {
    static let shared = AuthManager()

    @Published var userId: String?
    @Published var isAuthenticated = false

    private let db = Firestore.firestore()

    private init() {}

    /// Signs in anonymously. If the user already has a session, Firebase
    /// reuses it automatically — no duplicate accounts.
    func signInAnonymously() async throws {
        let result = try await Auth.auth().signInAnonymously()
        let uid = result.user.uid
        self.userId = uid
        self.isAuthenticated = true

        // Create or update the user document
        let userRef = db.collection("users").document(uid)
        let snapshot = try await userRef.getDocument()

        if !snapshot.exists {
            try await userRef.setData([
                "displayName": "",
                "fcmToken": "",
                "pairedWith": NSNull(),
                "pairId": NSNull(),
                "createdAt": FieldValue.serverTimestamp()
            ])
        }
    }
}
```

---

## Step 1.6 — Create the Root View with Auth State

**File: `RootView.swift`** (create in a new group called `Views`)

```swift
import SwiftUI

struct RootView: View {
    @StateObject private var authManager = AuthManager.shared
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Signing in...")
            } else if let error = errorMessage {
                VStack(spacing: 16) {
                    Text("Something went wrong")
                        .font(.headline)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Button("Retry") {
                        Task { await authenticate() }
                    }
                }
            } else {
                HomeView()
            }
        }
        .task {
            await authenticate()
        }
    }

    private func authenticate() async {
        isLoading = true
        errorMessage = nil
        do {
            try await authManager.signInAnonymously()
            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }
}
```

---

## Step 1.7 — Create a Placeholder Home View

**File: `HomeView.swift`** (in `Views` group)

```swift
import SwiftUI

struct HomeView: View {
    @ObservedObject private var authManager = AuthManager.shared

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("Welcome to Herm")
                    .font(.largeTitle.bold())

                if let uid = authManager.userId {
                    Text("User ID: \(uid)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Text("You are not paired with anyone yet.")
                    .foregroundColor(.secondary)

                // Pairing buttons will go here in Phase 2
            }
            .navigationTitle("Herm")
        }
    }
}
```

---

## Step 1.8 — Enable Anonymous Auth in Firebase Console

1. In Firebase Console → **Authentication → Sign-in method**.
2. Enable **Anonymous**.
3. Click **Save**.

---

## Step 1.9 — Set Firestore Security Rules (Development)

In Firebase Console → **Firestore Database → Rules**, set temporary dev rules:

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // DEVELOPMENT ONLY — lock down before production
    match /{document=**} {
      allow read, write: if request.auth != null;
    }
  }
}
```

> **Important**: These rules allow any authenticated user to read/write anything. We will tighten these in Phase 6.

---

## Verification Checklist

- [x] App builds and runs on simulator without crashes
- [x] On first launch, the app shows "Signing in..." briefly, then the Home screen
- [x] Firebase Console → Authentication shows a new anonymous user
- [x] Firebase Console → Firestore → `users` collection shows a document with the user's UID
- [ ] Killing and relaunching the app reuses the same anonymous user (no new UID created)

---

## Important Notes for Xcode 26

- **No manual Info.plist** — Xcode auto-generates it. Including one causes "Multiple commands produce Info.plist" build errors.
- **`import Combine` required** — Any file using `@Published` must explicitly `import Combine` due to strict member import visibility in Xcode 26/Swift 6.
- **Synchronized root groups** — The project uses `PBXFileSystemSynchronizedRootGroup`, meaning files placed in `Herm/Herm/` are automatically included in the project. No need to manually add files via Xcode.

## File Structure After Phase 1

```
Herm/
├── Herm.xcodeproj
└── Herm/
    ├── HermApp.swift
    ├── GoogleService-Info.plist
    ├── Assets.xcassets/
    ├── Services/
    │   └── AuthManager.swift
    └── Views/
        ├── RootView.swift
        └── HomeView.swift
```
