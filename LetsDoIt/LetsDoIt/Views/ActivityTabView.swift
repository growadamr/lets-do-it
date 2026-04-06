import SwiftUI

struct ActivityTabView: View {
    @ObservedObject private var contactManager = ContactManager.shared
    @StateObject private var activityManager = ActivityManager.shared
    @State private var showingSettings = false

    var body: some View {
        NavigationStack {
            if let contact = contactManager.selectedContact {
                // Contact is selected — show activity selection
                contactSelectedView(contact: contact)
            } else {
                // No contact selected — show landing page with matches or empty state
                landingView
            }
        }
        .task {
            // Start listeners for the lifetime of the Activity tab.
            // This ensures custom activities and preferences are always
            // loaded, regardless of which sub-view is presented.
            activityManager.startListeningPreferences()
            activityManager.startListeningCustomActivities()
        }
        .onDisappear {
            activityManager.stopListeningPreferences()
            activityManager.stopListeningCustomActivities()
        }
    }

    // MARK: - Landing View

    private var landingView: some View {
        MatchesLandingView()
    }

    // MARK: - Contact Selected View

    private func contactSelectedView(contact: ContactManager.Contact) -> some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "person.circle.fill")
                .font(.system(size: 70))
                .foregroundColor(.accentColor)

            Text("Matching with")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Text(contact.displayName)
                .font(.title2.bold())

            ActivityListView()
                .frame(maxHeight: .infinity)

            Button("Change Contact") {
                contactManager.selectedContact = nil
            }
            .buttonStyle(.bordered)

            Spacer()
        }
        .padding()
        .navigationTitle(contact.displayName)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
            }
        }
        .sheet(isPresented: $showingSettings) {
            ActivitySettingsView()
                .presentationDetents([.medium, .large])
        }
        .sheet(item: $contactManager.pendingContactForNaming) { contact in
            SetContactNameSheet(contact: contact)
                .presentationDetents([.medium])
        }
    }
}
