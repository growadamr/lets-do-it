import SwiftUI

struct ActivityTabView: View {
    @ObservedObject private var contactManager = ContactManager.shared
    @StateObject private var activityManager = ActivityManager.shared
    @State private var activeSheet: ActivitySheet?

    enum ActivitySheet: Identifiable {
        case schedules(contactUid: String)
        case settings(contactUid: String)
        case nameContact(ContactManager.Contact)
        var id: String {
            switch self {
            case .schedules(let uid): return "schedules-\(uid)"
            case .settings(let uid): return "settings-\(uid)"
            case .nameContact(let c): return "name-\(c.uid)"
            }
        }
    }

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
            activityManager.startListeningContactPreferences()
        }
        .onDisappear {
            activityManager.stopListeningPreferences()
            activityManager.stopListeningCustomActivities()
            activityManager.stopListeningContactPreferences()
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
                    activeSheet = .schedules(contactUid: contact.uid)
                } label: {
                    Image(systemName: "calendar.badge.clock")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    activeSheet = .settings(contactUid: contact.uid)
                } label: {
                    Image(systemName: "gearshape")
                }
            }
        }
        .onChange(of: contactManager.pendingContactForNaming) { newContact in
            if let contact = newContact {
                activeSheet = .nameContact(contact)
                contactManager.pendingContactForNaming = nil
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .schedules(let uid):
                NavigationStack {
                    ScheduledActivitiesListView(filterContactUid: uid)
                }
                .presentationDetents([.medium, .large])
            case .settings(let uid):
                ActivitySettingsView(contactUid: uid)
                    .presentationDetents([.medium, .large])
            case .nameContact(let contact):
                SetContactNameSheet(contact: contact)
                    .presentationDetents([.medium])
            }
        }
    }
}
