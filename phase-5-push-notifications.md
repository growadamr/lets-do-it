# Phase 5: In-App Match Alerts (No Push Notifications)

## Goal
Both users see an in-app alert when a match occurs. The Cloud Function from Phase 4 already detects matches and marks selections as `matched: true`. This phase adds a real-time Firestore listener on the client that detects matched selections and shows an alert with the matched activity name.

> **Note**: Push notifications (APNs/FCM) are skipped for now because they require a paid Apple Developer account ($99/year). This phase implements an in-app alternative. Push notifications can be added later when a paid account is available.

---

## Step 5.1 — Create the Match Listener Service

This service listens for selections where `matched == true` in real time. When a new match is detected, it publishes the match info so the UI can show an alert.

**File: `Services/MatchListener.swift`**

```swift
import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore

@MainActor
class MatchListener: ObservableObject {
    static let shared = MatchListener()

    @Published var latestMatch: MatchAlert?

    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?
    private var knownMatchIds: Set<String> = []

    private init() {}

    struct MatchAlert: Identifiable {
        let id: String
        let itemId: String
        let emoji: String
        let label: String
    }

    /// Start listening for matched selections in this pair.
    func startListening(pairId: String) {
        guard let userId = Auth.auth().currentUser?.uid else { return }

        listener?.remove()
        knownMatchIds = []

        let selectionsRef = db.collection("pairs").document(pairId)
            .collection("selections")
            .whereField("userId", isEqualTo: userId)
            .whereField("matched", isEqualTo: true)

        listener = selectionsRef.addSnapshotListener { [weak self] snapshot, error in
            guard let self, let documents = snapshot?.documents else { return }

            for doc in documents {
                let docId = doc.documentID
                if self.knownMatchIds.contains(docId) { continue }

                self.knownMatchIds.insert(docId)

                let data = doc.data()
                guard let itemId = data["itemId"] as? String else { continue }

                // Look up the activity label and emoji
                if let item = ActivityCatalog.items.first(where: { $0.id == itemId }) {
                    self.latestMatch = MatchAlert(
                        id: docId,
                        itemId: itemId,
                        emoji: item.emoji,
                        label: item.label
                    )
                }
            }
        }
    }

    func stopListening() {
        listener?.remove()
        knownMatchIds = []
    }

    func dismissMatch() {
        latestMatch = nil
    }
}
```

---

## Step 5.2 — Update HomeView to Show Match Alerts

Add the match listener and an alert to `HomeView.swift`. When a match is detected, an alert pops up showing the matched activity.

**In the paired state block of `HomeView.swift`**, add:

1. A property for the match listener
2. Start listening when paired
3. An `.alert` modifier that shows when a match is detected

The full updated `HomeView.swift`:

```swift
import SwiftUI

struct HomeView: View {
    @StateObject private var pairingManager = PairingManager.shared
    @StateObject private var matchListener = MatchListener.shared
    @State private var showCreateCode = false
    @State private var showJoinCode = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if pairingManager.isPaired {
                    VStack(spacing: 12) {
                        if let name = pairingManager.partnerName, !name.isEmpty {
                            Text("Connected with \(name)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }

                        ActivityListView()

                        Button("Disconnect", role: .destructive) {
                            Task { try? await pairingManager.unpair() }
                        }
                        .padding(.bottom, 16)
                    }
                } else {
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
                if let pairId = pairingManager.pairId {
                    matchListener.startListening(pairId: pairId)
                }
            }
            .onChange(of: pairingManager.pairId) { _, newPairId in
                if let pairId = newPairId {
                    matchListener.startListening(pairId: pairId)
                } else {
                    matchListener.stopListening()
                }
            }
            .alert(
                "It's a match!",
                isPresented: Binding(
                    get: { matchListener.latestMatch != nil },
                    set: { if !$0 { matchListener.dismissMatch() } }
                )
            ) {
                Button("OK") {
                    matchListener.dismissMatch()
                }
            } message: {
                if let match = matchListener.latestMatch {
                    Text("\(match.emoji) You both want: \(match.label)")
                }
            }
        }
    }
}
```

---

## Verification Checklist

- [ ] App builds and runs without crashes
- [ ] When paired, the match listener starts (check console for no errors)
- [ ] When both users select the same item, an in-app alert appears: "It's a match!"
- [ ] The alert shows the correct activity name and emoji
- [ ] Dismissing the alert works (tapping OK)
- [ ] The alert only appears for NEW matches, not previously seen ones
- [ ] Disconnecting stops the match listener

---

## Notes

- Any file using `@Published` must `import Combine` (Xcode 26 requirement).
- New files in `Herm/Herm/` are auto-synced by Xcode's synchronized root group.
- Push notifications can be added later when a paid Apple Developer account is available. The Cloud Function infrastructure (pendingNotifications, FCM sending) from Phase 4 is already in place — you'd just need to add APNs keys, an AppDelegate, and a NotificationManager.

## File Structure After Phase 5

```
Herm/
├── Herm.xcodeproj
└── Herm/
    ├── HermApp.swift
    ├── GoogleService-Info.plist
    ├── Assets.xcassets/
    ├── Models/
    │   ├── ActivityItem.swift
    │   └── ActivityCatalog.swift
    ├── Services/
    │   ├── AuthManager.swift
    │   ├── PairingManager.swift
    │   ├── SelectionManager.swift
    │   └── MatchListener.swift
    └── Views/
        ├── RootView.swift
        ├── HomeView.swift
        ├── CreateCodeView.swift
        ├── JoinCodeView.swift
        ├── ActivityListView.swift
        └── ActivityRow.swift
functions/
├── index.js
├── package.json
└── node_modules/
firebase.json
.firebaserc
```
