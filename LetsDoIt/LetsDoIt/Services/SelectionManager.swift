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
