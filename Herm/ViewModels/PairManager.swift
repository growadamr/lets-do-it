import Foundation
import FirebaseFirestore

class PairManager: ObservableObject {
    static let shared = PairManager()

    @Published var currentPair: Pair?
    @Published var inviteCode: String?

    private let db = Firestore.firestore()

    private init() {}

    func createPair(for userId: String) async throws -> Pair {
        let pairId = UUID().uuidString
        let pairData: [String: Any] = [
            "userA": userId,
            "userB": "",  // Empty until paired
            "createdAt": FieldValue.serverTimestamp(),
            "active": true
        ]

        let pairRef = db.collection("pairs").document(pairId)
        try await pairRef.setData(pairData)

        let pair = Pair(id: pairId, userA: userId, userB: "", createdAt: nil, active: true)
        self.currentPair = pair

        return pair
    }

    func updatePair(with partnerId: String, pairId: String) async throws {
        let pairRef = db.collection("pairs").document(pairId)
        let updateData: [String: Any] = [
            "userB": partnerId,
            "active": true
        ]

        try await pairRef.updateData(updateData)

        // Fetch updated pair
        let doc = try await pairRef.getDocument()
        if let data = doc.data() {
            self.currentPair = Pair(
                id: data["id"] as? String ?? pairId,
                userA: data["userA"] as? String ?? "",
                userB: data["userB"] as? String ?? "",
                createdAt: data["createdAt"] as? Timestamp,
                active: data["active"] as? Bool ?? false
            )
        }
    }

    func generateInviteCode() async throws -> String {
        let code = UUID().uuidString.prefix(6).uppercased()

        let docRef = db.collection("inviteCodes").document(code)
        let data: [String: Any] = [
            "code": code,
            "createdBy": currentPair?.userA ?? "",
            "createdAt": FieldValue.serverTimestamp(),
            "expiresAt": FieldValue.serverTimestamp().secondsSince1970 + 600, // 10 minutes
            "used": false,
            "pairId": currentPair?.id ?? ""
        ]

        try await docRef.setData(data)
        self.inviteCode = code

        return code
    }

    func validateInviteCode(_ code: String) async throws -> InviteCodeData? {
        let doc = try await db.collection("inviteCodes").document(code).getDocument()

        guard let data = doc.data(), !data["used"] as? Bool ?? true else {
            return nil
        }

        let now = Date()
        let expiresAt = data["expiresAt"] as? Timestamp ?? Timestamp(date: now)

        guard now.compare(expiresAt.toDate()) == .orderedAscending else {
            return nil
        }

        return InviteCodeData(
            code: code,
            createdBy: data["createdBy"] as? String ?? "",
            createdAt: data["createdAt"] as? Timestamp,
            expiresAt: data["expiresAt"] as? Timestamp,
            used: data["used"] as? Bool ?? false,
            pairId: data["pairId"] as? String ?? ""
        )
    }

    func useInviteCode(_ code: String, for userId: String) async throws {
        let docRef = db.collection("inviteCodes").document(code)
        try await docRef.updateData([
            "used": true,
            "usedBy": userId,
            "usedAt": FieldValue.serverTimestamp()
        ])
    }
}

struct Pair {
    let id: String
    let userA: String
    let userB: String
    let createdAt: Timestamp?
    let active: Bool
}

struct InviteCodeData {
    let code: String
    let createdBy: String
    let createdAt: Timestamp?
    let expiresAt: Timestamp?
    let used: Bool
    let pairId: String
}
