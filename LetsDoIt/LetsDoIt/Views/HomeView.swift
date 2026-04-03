import SwiftUI

struct HomeView: View {
    @StateObject private var contactManager = ContactManager.shared
    @State private var showCreateCode = false
    @State private var showJoinCode = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "person.2.circle")
                    .font(.system(size: 80))
                    .foregroundColor(.accentColor)

                Text("Let's do it!")
                    .font(.largeTitle.bold())

                Text("Select a contact to get started")
                    .foregroundColor(.secondary)

                NavigationLink("View Contacts") {
                    ContactsListView()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal, 40)

                Spacer()
            }
            .padding()
            .navigationTitle("Let's do it!")
            .sheet(item: $contactManager.selectedContact) { contact in
                ActivitySelectionSheet(contact: contact)
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
            .onAppear {
                contactManager.startListening()
            }
        }
    }
}

// MARK: - Activity Selection Sheet

struct ActivitySelectionSheet: View {
    let contact: ContactManager.Contact
    @Environment(\.dismiss) private var dismiss
    @StateObject private var contactManager = ContactManager.shared

    var body: some View {
        NavigationStack {
            ActivityListView()
                .navigationTitle("Matching with \(contact.displayName)")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") {
                            dismiss()
                        }
                        .fontWeight(.semibold)
                    }
                }
        }
    }
}
