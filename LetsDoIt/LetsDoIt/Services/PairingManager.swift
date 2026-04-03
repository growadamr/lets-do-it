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
