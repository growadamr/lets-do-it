import SwiftUI
import Combine

struct RootView: View {
    @StateObject private var authManager = AuthManager.shared
    @ObservedObject private var contactManager = ContactManager.shared
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showSetName = false

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Signing in...")
            } else if let error = errorMessage {
                VStack(spacing: 16) {
                    Text("Something went wrong")
                        .font(.headline)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Button("Retry") {
                        Task { await authenticate() }
                    }
                }
            } else {
                HomeView()
                    .sheet(isPresented: $showSetName) {
                        SetNameView(isPresented: $showSetName)
                            .presentationDetents([.medium])
                    }
            }
        }
        .task {
            await authenticate()
        }
        .onAppear {
            // Show name entry if first time
            if authManager.isAuthenticated && authManager.displayName.isEmpty {
                showSetName = true
            }
        }
        .onDisappear {
            // Clean up listener when app goes to background
            contactManager.stopListening()
        }
    }

    private func authenticate() async {
        isLoading = true
        errorMessage = nil
        do {
            try await authManager.signInAnonymously()
            // Start listening once authenticated
            contactManager.startListening()
            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }
}
