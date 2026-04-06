import SwiftUI

struct ActivityTabView: View {
    @ObservedObject private var contactManager = ContactManager.shared
    @State private var showCreateCode = false
    @State private var showJoinCode = false
    @State private var showingContacts = false
    @State private var showingSettings = false

    var body: some View {
        NavigationStack {
            if let contact = contactManager.selectedContact, !showingContacts {
                // Contact is selected — show activity selection
                contactSelectedView(contact: contact)
            } else {
                // No contact selected or showing contacts — show landing page
                landingView
            }
        }
    }

    // MARK: - Landing View

    private var landingView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "person.2.circle")
                .font(.system(size: 80))
                .foregroundColor(.accentColor)

            Text("Let's do it!")
                .font(.largeTitle.bold())

            Text("Select a contact to get started")
                .foregroundColor(.secondary)

            Button("View Contacts") {
                showingContacts = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 40)

            Spacer()
        }
        .padding()
        .navigationTitle("Let's do it!")
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
        .fullScreenCover(isPresented: $showingContacts) {
            ContactsListView(onSelect: {
                showingContacts = false
            })
            .presentationDetents([.large])
        }
        .sheet(isPresented: $showCreateCode) {
            CreateCodeView()
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $showJoinCode) {
            JoinCodeView()
                .presentationDetents([.medium])
        }
        .sheet(item: $contactManager.pendingContactForNaming) { contact in
            SetContactNameSheet(contact: contact)
                .presentationDetents([.medium])
        }
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
