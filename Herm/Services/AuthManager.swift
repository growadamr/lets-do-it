import Foundation
import FirebaseAuth
import FirebaseFirestore

@MainActor
class AuthManager: ObservableObject {
    static let shared = AuthManager()

    @Published var userId: String?
    @Published var isAuthenticated = false

    private let db = Firestore.firestore()

    private init() {}

    /// Signs in anonymously. If the user already has a session, Firebase
    /// reuses it automatically — no duplicate accounts.
    func signInAnonymously() async throws {
        let result = try await Auth.auth().signIn(anonymously: true)
        let uid = result.user.uid
        self.userId = uid
        self.isAuthenticated = true

        // Create or update the user document
        let userRef = db.collection("users").document(uid)
        let snapshot = try await userRef.getDocument()

        if !snapshot.exists {
            try await userRef.setData([
                "displayName": "",
                "fcmToken": "",
                "pairedWith": NSNull(),
                "pairId": NSNull(),
                "createdAt": FieldValue.serverTimestamp()
            ])
        }
    }
}
