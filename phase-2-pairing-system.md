# Phase 2: Pairing System (Invite Codes)

## Goal
Two users can connect via a 6-digit invite code. After pairing, both users see the shared activity list (built in Phase 3). A user can only be in one pair at a time.

---

## Step 2.1 — Add a Pairing Manager Service

**File: `Services/PairingManager.swift`**

```swift
import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore

@MainActor
class PairingManager: ObservableObject {
    static let shared = PairingManager()

    @Published var pairId: String?
    @Published var partnerName: String?
    @Published var isPaired = false

    private let db = Firestore.firestore()
    private var pairListener: ListenerRegistration?

    private init() {}

    // MARK: - Generate Invite Code

    /// Creates a 6-digit code stored in Firestore. Expires in 10 minutes.
    func generateInviteCode() async throws -> String {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw PairingError.notAuthenticated
        }

        // Delete any existing codes from this user first
        let existing = try await db.collection("inviteCodes")
            .whereField("createdBy", isEqualTo: userId)
            .whereField("used", isEqualTo: false)
            .getDocuments()

        for doc in existing.documents {
            try await doc.reference.delete()
        }

        // Generate a random 6-digit code
        let code = String(format: "%06d", Int.random(in: 0...999999))

        let expiresAt = Date().addingTimeInterval(10 * 60) // 10 minutes

        try await db.collection("inviteCodes").document(code).setData([
            "createdBy": userId,
            "createdAt": FieldValue.serverTimestamp(),
            "expiresAt": Timestamp(date: expiresAt),
            "used": false
        ])

        return code
    }

    // MARK: - Join With Invite Code

    /// Looks up the code, validates it, creates the pair, and updates both users.
    func joinWithCode(_ code: String) async throws {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            throw PairingError.notAuthenticated
        }

        let codeRef = db.collection("inviteCodes").document(code)
        let codeDoc = try await codeRef.getDocument()

        guard let data = codeDoc.data(),
              let createdBy = data["createdBy"] as? String,
              let expiresAt = data["expiresAt"] as? Timestamp,
              let used = data["used"] as? Bool else {
            throw PairingError.invalidCode
        }

        // Validate
        guard !used else { throw PairingError.codeAlreadyUsed }
        guard expiresAt.dateValue() > Date() else { throw PairingError.codeExpired }
        guard createdBy != currentUserId else { throw PairingError.cannotPairWithSelf }

        // Check neither user is already paired
        let currentUserDoc = try await db.collection("users").document(currentUserId).getDocument()
        if let currentData = currentUserDoc.data(),
           let existingPairId = currentData["pairId"] as? String, !existingPairId.isEmpty {
            throw PairingError.alreadyPaired
        }

        let otherUserDoc = try await db.collection("users").document(createdBy).getDocument()
        if let otherData = otherUserDoc.data(),
           let existingPairId = otherData["pairId"] as? String, !existingPairId.isEmpty {
            throw PairingError.otherUserAlreadyPaired
        }

        // Create the pair document
        let pairRef = db.collection("pairs").document()
        let pairId = pairRef.documentID

        // Use a batch write for atomicity
        let batch = db.batch()

        // 1. Create pair
        batch.setData([
            "userA": createdBy,
            "userB": currentUserId,
            "createdAt": FieldValue.serverTimestamp(),
            "active": true
        ], forDocument: pairRef)

        // 2. Update user A (the one who created the code)
        batch.updateData([
            "pairedWith": currentUserId,
            "pairId": pairId
        ], forDocument: db.collection("users").document(createdBy))

        // 3. Update user B (the one joining)
        batch.updateData([
            "pairedWith": createdBy,
            "pairId": pairId
        ], forDocument: db.collection("users").document(currentUserId))

        // 4. Mark code as used
        batch.updateData(["used": true], forDocument: codeRef)

        try await batch.commit()

        self.pairId = pairId
        self.isPaired = true
    }

    // MARK: - Listen for Pair Status

    /// Call on app launch to check if user is already paired and listen for changes.
    func listenForPairStatus() {
        guard let userId = Auth.auth().currentUser?.uid else { return }

        pairListener?.remove()
        pairListener = db.collection("users").document(userId)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self, let data = snapshot?.data() else { return }

                if let pairId = data["pairId"] as? String, !pairId.isEmpty {
                    self.pairId = pairId
                    self.isPaired = true

                    // Fetch partner name
                    if let partnerId = data["pairedWith"] as? String {
                        Task {
                            let partnerDoc = try? await self.db.collection("users")
                                .document(partnerId).getDocument()
                            if let name = partnerDoc?.data()?["displayName"] as? String,
                               !name.isEmpty {
                                await MainActor.run { self.partnerName = name }
                            }
                        }
                    }
                } else {
                    self.pairId = nil
                    self.isPaired = false
                    self.partnerName = nil
                }
            }
    }

    // MARK: - Unpair

    /// Dissolves the current pair. Both users return to unpaired state.
    func unpair() async throws {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw PairingError.notAuthenticated
        }

        let userDoc = try await db.collection("users").document(userId).getDocument()
        guard let data = userDoc.data(),
              let pairId = data["pairId"] as? String,
              let partnerId = data["pairedWith"] as? String else {
            throw PairingError.notPaired
        }

        let batch = db.batch()

        // Deactivate the pair
        batch.updateData(["active": false],
                         forDocument: db.collection("pairs").document(pairId))

        // Clear both users
        batch.updateData(["pairedWith": NSNull(), "pairId": NSNull()],
                         forDocument: db.collection("users").document(userId))
        batch.updateData(["pairedWith": NSNull(), "pairId": NSNull()],
                         forDocument: db.collection("users").document(partnerId))

        try await batch.commit()

        self.pairId = nil
        self.isPaired = false
        self.partnerName = nil
    }

    // MARK: - Cleanup

    func stopListening() {
        pairListener?.remove()
    }
}

// MARK: - Error Types

enum PairingError: LocalizedError {
    case notAuthenticated
    case invalidCode
    case codeAlreadyUsed
    case codeExpired
    case cannotPairWithSelf
    case alreadyPaired
    case otherUserAlreadyPaired
    case notPaired

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "You must be signed in."
        case .invalidCode: return "That code doesn't exist."
        case .codeAlreadyUsed: return "That code has already been used."
        case .codeExpired: return "That code has expired."
        case .cannotPairWithSelf: return "You can't pair with yourself."
        case .alreadyPaired: return "You're already paired with someone."
        case .otherUserAlreadyPaired: return "That person is already paired."
        case .notPaired: return "You're not currently paired with anyone."
        }
    }
}
```

---

## Step 2.2 — Create the Invite Code Screen (Code Creator)

**File: `Views/CreateCodeView.swift`**

```swift
import SwiftUI

struct CreateCodeView: View {
    @State private var code: String?
    @State private var isGenerating = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 32) {
            Text("Share this code with your person")
                .font(.headline)

            if isGenerating {
                ProgressView()
            } else if let code {
                // Display code with large, spaced-out digits
                Text(code)
                    .font(.system(size: 48, weight: .bold, design: .monospaced))
                    .kerning(8)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)

                Text("Expires in 10 minutes")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Button("Copy Code") {
                    UIPasteboard.general.string = code
                }
                .buttonStyle(.bordered)
            }

            if let error = errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
            }
        }
        .padding()
        .task {
            await generateCode()
        }
    }

    private func generateCode() async {
        isGenerating = true
        errorMessage = nil
        do {
            code = try await PairingManager.shared.generateInviteCode()
        } catch {
            errorMessage = error.localizedDescription
        }
        isGenerating = false
    }
}
```

---

## Step 2.3 — Create the Join Code Screen (Code Joiner)

**File: `Views/JoinCodeView.swift`**

```swift
import SwiftUI

struct JoinCodeView: View {
    @State private var code = ""
    @State private var isJoining = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 32) {
            Text("Enter your partner's code")
                .font(.headline)

            TextField("000000", text: $code)
                .font(.system(size: 36, weight: .bold, design: .monospaced))
                .kerning(6)
                .multilineTextAlignment(.center)
                .keyboardType(.numberPad)
                .frame(maxWidth: 240)

            Button("Connect") {
                Task { await joinWithCode() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(code.count != 6 || isJoining)

            if isJoining {
                ProgressView()
            }

            if let error = errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
            }
        }
        .padding()
    }

    private func joinWithCode() async {
        isJoining = true
        errorMessage = nil
        do {
            try await PairingManager.shared.joinWithCode(code)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isJoining = false
    }
}
```

---

## Step 2.4 — Update HomeView to Show Pairing State

**Replace `Views/HomeView.swift`** with:

```swift
import SwiftUI

struct HomeView: View {
    @StateObject private var pairingManager = PairingManager.shared
    @State private var showCreateCode = false
    @State private var showJoinCode = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if pairingManager.isPaired {
                    // Paired state — activity list goes here in Phase 3
                    VStack(spacing: 12) {
                        Image(systemName: "link.circle.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.green)

                        Text("You're connected!")
                            .font(.title2.bold())

                        if let name = pairingManager.partnerName, !name.isEmpty {
                            Text("Paired with \(name)")
                                .foregroundColor(.secondary)
                        }

                        Text("Activity list coming in Phase 3...")
                            .foregroundColor(.secondary)
                            .padding(.top, 20)

                        Spacer()

                        Button("Disconnect", role: .destructive) {
                            Task { try? await pairingManager.unpair() }
                        }
                        .padding(.bottom, 40)
                    }
                } else {
                    // Unpaired state — show pairing options
                    Spacer()

                    Image(systemName: "person.2.circle")
                        .font(.system(size: 80))
                        .foregroundColor(.accentColor)

                    Text("Herm")
                        .font(.largeTitle.bold())

                    Text("Connect with someone to get started")
                        .foregroundColor(.secondary)

                    VStack(spacing: 12) {
                        Button {
                            showCreateCode = true
                        } label: {
                            Label("Create Invite Code", systemImage: "plus.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)

                        Button {
                            showJoinCode = true
                        } label: {
                            Label("Enter a Code", systemImage: "keyboard")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    }
                    .padding(.horizontal, 40)

                    Spacer()
                }
            }
            .padding()
            .navigationTitle("Herm")
            .sheet(isPresented: $showCreateCode) {
                CreateCodeView()
                    .presentationDetents([.medium])
            }
            .sheet(isPresented: $showJoinCode) {
                JoinCodeView()
                    .presentationDetents([.medium])
            }
            .onAppear {
                pairingManager.listenForPairStatus()
            }
        }
    }
}
```

---

## Step 2.5 — Add Display Name Entry (Optional but Recommended)

To make notifications friendlier ("You and Alex both want Drinks!"), let users set a name.

**File: `Views/SetNameView.swift`**

```swift
import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct SetNameView: View {
    @State private var name = ""
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 24) {
            Text("What should we call you?")
                .font(.headline)

            TextField("Your name", text: $name)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 240)

            Button("Save") {
                Task {
                    guard let uid = Auth.auth().currentUser?.uid else { return }
                    try? await Firestore.firestore()
                        .collection("users").document(uid)
                        .updateData(["displayName": name])
                    isPresented = false
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding()
    }
}
```

Add this as a sheet in `RootView` — show it once after first sign-in if `displayName` is empty.

---

## Verification Checklist

- [ ] User A taps "Create Invite Code" → sees a 6-digit code
- [ ] The code appears in Firestore under `inviteCodes` collection
- [ ] User B (on a different simulator/device) taps "Enter a Code" → types the code → taps "Connect"
- [ ] Both users now see "You're connected!" on their screens
- [ ] Firestore shows a new doc in `pairs` with both user IDs
- [ ] Both user docs in `users` now have `pairId` and `pairedWith` set
- [ ] The invite code document now has `used: true`
- [ ] Tapping "Disconnect" on either side clears both users' pair state
- [ ] Entering an expired, used, or nonexistent code shows an appropriate error

---

## Notes

- All new `.swift` files go in `Herm/Herm/` (under the appropriate subfolder). Xcode's synchronized root group picks them up automatically — no need to add them via Xcode.
- Any file using `@Published` must `import Combine` (Xcode 26 requirement).

## File Structure After Phase 2

```
Herm/
├── Herm.xcodeproj
└── Herm/
    ├── HermApp.swift
    ├── GoogleService-Info.plist
    ├── Assets.xcassets/
    ├── Services/
    │   ├── AuthManager.swift
    │   └── PairingManager.swift
    └── Views/
        ├── RootView.swift
        ├── HomeView.swift
        ├── CreateCodeView.swift
        ├── JoinCodeView.swift
        └── SetNameView.swift
```
