import SwiftUI

struct HomeView: View {
    @ObservedObject private var authManager = AuthManager.shared

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("Welcome to Herm")
                    .font(.largeTitle.bold())

                if let uid = authManager.userId {
                    Text("User ID: \(uid)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Text("You are not paired with anyone yet.")
                    .foregroundColor(.secondary)

                // Pairing buttons will go here in Phase 2
            }
            .navigationTitle("Herm")
        }
    }
}
