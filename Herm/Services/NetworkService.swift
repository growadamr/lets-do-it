import Foundation
import FirebaseFirestore

class NetworkService {
    static let shared = NetworkService()

    private let db = Firestore.firestore()

    private init() {}

    // Create a selection
    func createSelection(_ selection: Selection) async throws {
        let docRef = db.collection("pairs")
            .document(selection.pairId)
            .collection("selections")
            .document(UUID().uuidString)

        let data: [String: Any] = [
            "userId": selection.userId,
            "itemId": selection.itemId,
            "createdAt": FieldValue.serverTimestamp(),
            "expiresAt": FieldValue.serverTimestamp().secondsSince1970 + 3600, // 60 minutes
            "matched": false
        ]

        try await docRef.setData(data)
    }

    // Get active selections for a pair
    func getActiveSelections(for pairId: String) async throws -> [Selection] {
        let doc = try await db.collection("pairs").document(pairId).getDocument()
        guard let data = doc.data(), data["active"] as? Bool == true else {
            return []
        }

        let selectionsRef = db.collection("pairs")
            .document(pairId)
            .collection("selections")

        let query = try await selectionsRef
            .whereField("matched", isLessThan: true)
            .getDocuments()

        return query.documents.compactMap { doc in
            guard let data = doc.data() else { return nil }
            return Selection(
                id: doc.documentID,
                userId: data["userId"] as? String ?? "",
                itemId: data["itemId"] as? String ?? "",
                createdAt: data["createdAt"] as? Timestamp,
                expiresAt: data["expiresAt"] as? Timestamp,
                matched: data["matched"] as? Bool ?? false
            )
        }
    }

    // Check for match
    func checkForMatch(for pairId: String, userId: String, itemId: String) async throws -> MatchResult? {
        // Get other user's selection
        let selections = try await getActiveSelections(for: pairId)

        guard let otherSelection = selections.first(where: { $0.userId != userId && $0.itemId == itemId }) else {
            return nil
        }

        // Check if other selection is still active (within 60 min window)
        guard let expiresAt = otherSelection.expiresAt,
              Date().compare(expiresAt.toDate()) == .orderedAscending else {
            return nil
        }

        // Create pending notification
        let pendingNotifId = UUID().uuidString
        let sendDelay = TimeInterval.random(in: 600...900) // 10-15 minutes
        let sendAt = Date().addingTimeInterval(sendDelay)

        let notifData: [String: Any] = [
            "pendingNotificationsId": pendingNotifId,
            "pairId": pairId,
            "itemId": itemId,
            "userAId": userId,
            "userBId": otherSelection.userId,
            "sendAt": FieldValue.serverTimestamp().secondsSince1970 + Int64(sendDelay),
            "sent": false
        ]

        try await db.collection("pendingNotifications").document(pendingNotifId).setData(notifData)

        // Mark both selections as matched
        let selectionRefs = [
            db.collection("pairs").document(pairId).collection("selections").document(otherSelection.id),
            // Would get user's own selection ref here
        ]

        for ref in selectionRefs {
            try await ref.updateData(["matched": true])
        }

        return MatchResult(
            pairId: pairId,
            itemId: itemId,
            userAId: userId,
            userBId: otherSelection.userId,
            sendAt: sendAt
        )
    }
}

struct Selection {
    let id: String
    let userId: String
    let itemId: String
    let createdAt: Timestamp?
    let expiresAt: Timestamp?
    let matched: Bool
}

struct MatchResult {
    let pairId: String
    let itemId: String
    let userAId: String
    let userBId: String
    let sendAt: Date
}
