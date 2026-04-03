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

    /// Start listening for matched selections with a specific contact.
    func startListening(contactUid: String) {
        guard let userId = Auth.auth().currentUser?.uid else { return }

        listener?.remove()
        knownMatchIds = []

        let selectionsRef = db.collection("users")
            .document(userId)
            .collection("selections")
            .whereField("matched", isEqualTo: true)

        listener = selectionsRef.addSnapshotListener { [weak self] snapshot, error in
            guard let self, let documents = snapshot?.documents else { return }

            for doc in documents {
                let docId = doc.documentID
                if self.knownMatchIds.contains(docId) { continue }

                let data = doc.data()

                // Filter in code to avoid Firestore composite index requirement
                guard data["userId"] as? String == userId,
                      data["targetUserId"] as? String == contactUid,
                      let itemId = data["itemId"] as? String else {
                    continue
                }

                self.knownMatchIds.insert(docId)

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
