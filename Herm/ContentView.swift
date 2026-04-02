import SwiftUI

struct ContentView: View {
    @StateObject private var authManager = AuthManager.shared
    @StateObject private var pairManager = PairManager.shared
    @State private var showInviteView = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let pair = pairManager.currentPair {
                    ActivityListView(pairId: pair.id)
                } else {
                    EmptyStateView {
                        NavigationLink("Find a Partner") {
                            InviteCodeView()
                        }
                    }
                }
            }
            .navigationTitle("Herm")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Invite") {
                        showInviteView = true
                    }
                }
            }
            .sheet(isPresented: $showInviteView) {
                InviteCodeView()
            }
        }
    }
}

struct ActivityListView: View {
    let pairId: String

    var body: some View {
        // TODO: Implement activity list view
        Text("Activity List - \(pairId)")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct EmptyStateView: View {
    let action: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.crop.circle")
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            Text("Find a partner to play")
                .font(.title2)
                .fontWeight(.medium)

            Text("Use an invite code to connect with someone")
                .font(.body)
                .foregroundColor(.secondary)

            Button(action: action) {
                Text("Create Invite Code")
                    .font(.headline)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}

#Preview {
    ContentView()
}
