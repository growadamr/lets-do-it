import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore
import FirebaseMessaging

@MainActor
class AuthManager: ObservableObject {
    static let shared = AuthManager()

    @Published var userId: String?
    @Published var displayName: String = ""
    @Published var isAuthenticated = false

    private let db = Firestore.firestore()

    private init() {}

    /// Signs in anonymously. If the user already has a session, Firebase
    /// reuses it automatically — no duplicate accounts.
    func signInAnonymously() async throws {
        let result = try await Auth.auth().signInAnonymously()
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
                "createdAt": FieldValue.serverTimestamp()
            ])
        } else {
            // Load existing display name
            if let data = snapshot.data(),
               let name = data["displayName"] as? String {
                self.displayName = name
            }
        }

        // Save current FCM token if available
        if let token = Messaging.messaging().fcmToken {
            try await userRef.updateData(["fcmToken": token])
        }

        // Start listening for contacts
        ContactManager.shared.startListening()
    }

    /// Update the user's display name in Firestore.
    func updateDisplayName(_ name: String) async throws {
        guard let uid = userId else { return }
        try await db.collection("users").document(uid).updateData(["displayName": name])
        self.displayName = name
    }

    /// Save FCM token to user document.
    func saveFcmToken(_ token: String) async {
        guard let uid = userId else { return }
        do {
            try await db.collection("users").document(uid).updateData(["fcmToken": token])
        } catch {
            print("Unable to save FCM token: \(error)")
        }
    }
}
