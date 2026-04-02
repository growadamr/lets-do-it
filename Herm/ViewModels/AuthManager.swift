import Foundation
import FirebaseAuth

class AuthManager: ObservableObject {
    static let shared = AuthManager()

    @Published var user: FirebaseUser?
    @Published var isLoading = false

    private init() {
        // Observe auth state changes
        Auth.auth().addStateDidChangeListener { [weak self] auth, error in
            guard let self = self else { return }

            self.isLoading = false

            if let user = auth.user {
                self.user = user
            } else {
                self.user = nil
            }
        }
    }

    func signInAnonymously() async throws {
        isLoading = true
        do {
            let result = try await Auth.auth().createAnonymousUser()
            self.user = result.user
        } catch {
            throw error
        }
    }

    func signOut() async throws {
        try await Auth.auth().signOut()
        self.user = nil
    }
}
