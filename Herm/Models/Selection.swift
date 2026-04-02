import Foundation
import FirebaseFirestore

struct Selection: Identifiable {
    let id: String
    let userId: String
    let itemId: String
    let createdAt: Timestamp?
    let expiresAt: Timestamp?
    let matched: Bool

    var isActive: Bool {
        guard let expiresAt = expiresAt else { return false }
        return Date().compare(expiresAt.toDate()) == .orderedAscending
    }
}
