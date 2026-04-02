import SwiftUI
import FirebaseAuth

struct AuthView: View {
    @StateObject private var authManager = AuthManager.shared
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 30) {
                Image(systemName: "sparkles")
                    .font(.system(size: 80))
                    .foregroundColor(.blue)

                Text("Welcome to Herm")
                    .font(.title)
                    .fontWeight(.bold)

                Text("Connect with a friend to find shared activities")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Button(action: signInAnonymously) {
                    if isLoading {
                        ProgressView()
                    } else {
                        HStack {
                            Image(systemName: "arrow.right.circle.fill")
                            Text("Continue with Apple")
                                .font(.headline)
                        }
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                }
                .disabled(isLoading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemBackground))
            .onAppear {
                signInAnonymously()
            }
        }
    }

    private func signInAnonymously() {
        Task {
            isLoading = true
            do {
                try await authManager.signInAnonymously()
            } catch {
                print("Auth error: \(error)")
            }
            isLoading = false
        }
    }
}

#Preview {
    AuthView()
}
