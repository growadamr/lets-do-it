# Phase 3: Activity List UI & Selection Logic

## Goal
When paired, users see a list of activities/items they can tap. Tapping an item writes a selection to Firestore with a 60-minute expiry. Users can see their own active selections (highlighted) but never see their partner's selections.

---

## Step 3.1 — Define the Activity Data Model

**File: `Models/ActivityItem.swift`** (create a new `Models` group)

```swift
import Foundation

struct ActivityItem: Identifiable, Hashable {
    let id: String          // unique key, e.g., "drinks"
    let emoji: String
    let label: String
    let category: ActivityCategory
}

enum ActivityCategory: String, CaseIterable {
    case activities = "Activities"
    case places = "Places"
    case general = "General"
}
```

---

## Step 3.2 — Create the Default Activity List

**File: `Models/ActivityCatalog.swift`**

```swift
import Foundation

struct ActivityCatalog {
    static let items: [ActivityItem] = [
        // Activities
        ActivityItem(id: "walk", emoji: "🚶", label: "Go for a walk?", category: .activities),
        ActivityItem(id: "workout", emoji: "💪", label: "Work out?", category: .activities),
        ActivityItem(id: "movie", emoji: "🎬", label: "Watch a movie?", category: .activities),
        ActivityItem(id: "cook", emoji: "🍳", label: "Cook together?", category: .activities),
        ActivityItem(id: "game", emoji: "🎮", label: "Play a game?", category: .activities),
        ActivityItem(id: "drive", emoji: "🚗", label: "Go for a drive?", category: .activities),

        // Places
        ActivityItem(id: "restaurant", emoji: "🍽️", label: "Go out to eat?", category: .places),
        ActivityItem(id: "cafe", emoji: "☕", label: "Hit a café?", category: .places),
        ActivityItem(id: "park", emoji: "🌳", label: "Go to the park?", category: .places),
        ActivityItem(id: "beach", emoji: "🏖️", label: "Go to the beach?", category: .places),
        ActivityItem(id: "store", emoji: "🛒", label: "Go shopping?", category: .places),

        // General
        ActivityItem(id: "drinks", emoji: "🍻", label: "Drinks?", category: .general),
        ActivityItem(id: "coffee", emoji: "☕", label: "Coffee?", category: .general),
        ActivityItem(id: "snack", emoji: "🍿", label: "Snack?", category: .general),
        ActivityItem(id: "chat", emoji: "💬", label: "Just talk?", category: .general),
        ActivityItem(id: "nap", emoji: "😴", label: "Nap time?", category: .general),
    ]

    /// Grouped by category for sectioned list display
    static var grouped: [(category: ActivityCategory, items: [ActivityItem])] {
        ActivityCategory.allCases.map { category in
            (category: category, items: items.filter { $0.category == category })
        }
    }
}
```

---

## Step 3.3 — Create the Selection Manager

This service handles writing selections to Firestore and tracking the current user's active selections.

**File: `Services/SelectionManager.swift`**

```swift
import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore

@MainActor
class SelectionManager: ObservableObject {
    static let shared = SelectionManager()

    /// Set of itemIds the current user has actively selected (not yet expired)
    @Published var activeSelections: Set<String> = []

    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?

    private init() {}

    // MARK: - Toggle Selection

    /// Called when a user taps an activity item.
    /// If not currently selected → create a new selection (60-min expiry).
    /// If currently selected → deselect (delete the selection doc).
    func toggleSelection(itemId: String) async throws {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        guard let pairId = PairingManager.shared.pairId else { return }

        let selectionsRef = db.collection("pairs").document(pairId)
            .collection("selections")

        if activeSelections.contains(itemId) {
            // Deselect: find and delete the active selection
            let query = selectionsRef
                .whereField("userId", isEqualTo: userId)
                .whereField("itemId", isEqualTo: itemId)
                .whereField("matched", isEqualTo: false)

            let snapshot = try await query.getDocuments()
            for doc in snapshot.documents {
                try await doc.reference.delete()
            }
            activeSelections.remove(itemId)
        } else {
            // Select: create a new selection with 60-min expiry
            let now = Date()
            let expiresAt = now.addingTimeInterval(60 * 60) // 60 minutes

            try await selectionsRef.addDocument(data: [
                "userId": userId,
                "itemId": itemId,
                "createdAt": Timestamp(date: now),
                "expiresAt": Timestamp(date: expiresAt),
                "matched": false
            ])
            activeSelections.insert(itemId)
        }
    }

    // MARK: - Listen for Own Active Selections

    /// Listens to the current user's selections in real time.
    /// Automatically removes expired ones from the UI.
    func startListening(pairId: String) {
        guard let userId = Auth.auth().currentUser?.uid else { return }

        listener?.remove()

        let selectionsRef = db.collection("pairs").document(pairId)
            .collection("selections")
            .whereField("userId", isEqualTo: userId)
            .whereField("matched", isEqualTo: false)

        listener = selectionsRef.addSnapshotListener { [weak self] snapshot, error in
            guard let self, let documents = snapshot?.documents else { return }

            let now = Date()
            var active = Set<String>()

            for doc in documents {
                let data = doc.data()
                guard let itemId = data["itemId"] as? String,
                      let expiresAt = data["expiresAt"] as? Timestamp else {
                    continue
                }

                if expiresAt.dateValue() > now {
                    active.insert(itemId)
                } else {
                    // Expired — clean it up
                    Task {
                        try? await doc.reference.delete()
                    }
                }
            }

            self.activeSelections = active
        }
    }

    func stopListening() {
        listener?.remove()
        activeSelections = []
    }
}
```

---

## Step 3.4 — Create the Activity List View

**File: `Views/ActivityListView.swift`**

```swift
import SwiftUI

struct ActivityListView: View {
    @StateObject private var selectionManager = SelectionManager.shared
    @ObservedObject private var pairingManager = PairingManager.shared
    @State private var tappedItemId: String?

    var body: some View {
        List {
            ForEach(ActivityCatalog.grouped, id: \.category) { group in
                Section(group.category.rawValue) {
                    ForEach(group.items) { item in
                        ActivityRow(
                            item: item,
                            isSelected: selectionManager.activeSelections.contains(item.id),
                            onTap: {
                                Task { await selectItem(item) }
                            }
                        )
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .onAppear {
            if let pairId = pairingManager.pairId {
                selectionManager.startListening(pairId: pairId)
            }
        }
        .onDisappear {
            selectionManager.stopListening()
        }
    }

    private func selectItem(_ item: ActivityItem) async {
        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()

        do {
            try await selectionManager.toggleSelection(itemId: item.id)
        } catch {
            print("Selection error: \(error)")
        }
    }
}
```

---

## Step 3.5 — Create the Activity Row Component

**File: `Views/ActivityRow.swift`**

```swift
import SwiftUI

struct ActivityRow: View {
    let item: ActivityItem
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                Text(item.emoji)
                    .font(.title2)

                Text(item.label)
                    .font(.body)
                    .foregroundColor(.primary)

                Spacer()

                // Show a subtle indicator if the user has selected this item.
                // No indicator for partner's selections — those are invisible.
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.title3)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle()) // make entire row tappable
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }
}
```

---

## Step 3.6 — Update HomeView to Show the Activity List

In `Views/HomeView.swift`, replace the paired-state placeholder section:

**Find this block** in the `if pairingManager.isPaired` branch:
```swift
Text("Activity list coming in Phase 3...")
    .foregroundColor(.secondary)
    .padding(.top, 20)

Spacer()
```

**Replace with:**
```swift
ActivityListView()
```

The full paired-state section should now look like:

```swift
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
}
```

---

## Step 3.7 — Expiry Timer (Client-Side UX Enhancement)

To avoid stale checkmarks, add a timer that periodically re-evaluates expired selections on the client side. The Firestore listener already handles this, but a local timer ensures the UI updates even if no Firestore events fire.

**Add to `ActivityListView`:**

```swift
// Inside ActivityListView struct, add:
@State private var timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

// Add this modifier to the List:
.onReceive(timer) { _ in
    // The Firestore listener handles cleanup, but this forces a UI refresh
    // by re-checking expiry times. The listener's snapshot callback
    // already filters expired docs, so this just ensures timely UI updates.
    if let pairId = pairingManager.pairId {
        selectionManager.startListening(pairId: pairId)
    }
}
```

---

## Verification Checklist

- [ ] When paired, the user sees a categorized list of activities
- [ ] Tapping an item shows a green checkmark and creates a doc in `pairs/{pairId}/selections`
- [ ] Tapping a selected item removes the checkmark and deletes the Firestore doc
- [ ] The selection doc has correct `expiresAt` (60 minutes after `createdAt`)
- [ ] User A's selections are NOT visible on User B's device (and vice versa)
- [ ] After 60 minutes, the checkmark disappears (test by temporarily setting expiry to 1 minute)
- [ ] Haptic feedback fires on each tap

---

## Notes

- All new `.swift` files go in `Herm/Herm/` (under the appropriate subfolder). Xcode's synchronized root group picks them up automatically.
- Any file using `@Published` must `import Combine` (Xcode 26 requirement).

## File Structure After Phase 3

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
    │   └── SelectionManager.swift
    └── Views/
        ├── RootView.swift
        ├── HomeView.swift
        ├── CreateCodeView.swift
        ├── JoinCodeView.swift
        ├── SetNameView.swift
        ├── ActivityListView.swift
        └── ActivityRow.swift
```
