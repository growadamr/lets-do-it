import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore

/// Singleton service that fetches all matches for the current user across all contacts.
/// Provides a real-time listener so the UI updates instantly when new matches are confirmed.
@MainActor
class MatchManager: ObservableObject {
    static let shared = MatchManager()

    /// All matches, sorted by date descending (most recent first).
    @Published var matches: [Match] = []

    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?

    private init() {}

    private var currentUid: String? {
        Auth.auth().currentUser?.uid
    }

    // MARK: - Real-time Listener

    /// Start listening for matches. Call once when the Activity tab is opened.
    func startListening() {
        guard let uid = currentUid else { return }

        listener?.remove()

        let ref = db.collection("users")
            .document(uid)
            .collection("selections")
            .whereField("matched", isEqualTo: true)

        listener = ref.addSnapshotListener { [weak self] snapshot, error in
            guard let self, let documents = snapshot?.documents else {
                if let error { print("[MatchManager] Listener error: \(error)") }
                return
            }

            Task { await self.processDocuments(documents) }
        }
    }

    /// Stop listening and clear the published matches.
    func stopListening() {
        listener?.remove()
        listener = nil
        matches = []
    }

    // MARK: - Processing

    private func processDocuments(_ documents: [QueryDocumentSnapshot]) async {
        guard let uid = currentUid else { return }

        let sixHoursAgo = Date().addingTimeInterval(-6 * 60 * 60)

        // Group by contact (targetUserId) to get the latest match per contact
        var contactMatches: [String: [Match]] = [:]

        for doc in documents {
            let data = doc.data()
            guard let targetUserId = data["targetUserId"] as? String,
                  let itemId = data["itemId"] as? String,
                  let createdAt = data["createdAt"] as? Timestamp else {
                continue
            }

            // Prune: only show matches from the past 6 hours
            if createdAt.dateValue() < sixHoursAgo { continue }

            let details = await ActivityManager.shared.resolveActivityDetails(
                itemId: itemId,
                contactUid: targetUserId
            )

            let match = Match(
                id: doc.documentID,
                itemId: itemId,
                contactUid: targetUserId,
                emoji: details.emoji,
                label: details.label,
                date: createdAt.dateValue()
            )

            if contactMatches[targetUserId] == nil {
                contactMatches[targetUserId] = []
            }
            contactMatches[targetUserId]?.append(match)
        }

        // For each contact, keep only the latest match (dedup by itemId + approximate timestamp)
        var allMatches: [Match] = []
        for (_, matchList) in contactMatches {
            let sorted = matchList.sorted { $0.date > $1.date }
            var seen = Set<String>()
            for m in sorted {
                let key = "\(m.itemId)_\(Int(m.date.timeIntervalSince1970))"
                if !seen.contains(key) {
                    seen.insert(key)
                    allMatches.append(m)
                }
            }
        }

        // Sort all matches by date descending
        matches = allMatches.sorted { $0.date > $1.date }
    }

    /// Resolve a contact's display name from ContactManager.
    func contactDisplayName(for uid: String) -> String {
        if let contact = ContactManager.shared.contacts.first(where: { $0.uid == uid }),
           !contact.displayName.isEmpty {
            return contact.displayName
        }
        return "Someone"
    }
}

// MARK: - Match Model

struct Match: Identifiable, Equatable {
    let id: String
    let itemId: String
    let contactUid: String
    let emoji: String
    let label: String
    let date: Date

    static func == (lhs: Match, rhs: Match) -> Bool {
        lhs.id == rhs.id
    }
}
