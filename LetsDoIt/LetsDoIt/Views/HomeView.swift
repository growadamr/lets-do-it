import SwiftUI

struct HomeView: View {
    @StateObject private var contactManager = ContactManager.shared
    @State private var showCreateCode = false
    @State private var showJoinCode = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if contactManager.selectedContact != nil {
                    VStack(spacing: 12) {
                        if let contact = contactManager.selectedContact {
                            HStack {
                                Text("Matching with \(contact.displayName)")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)

                                Button {
                                    contactManager.selectedContact = nil
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.secondary)
                                }
                            }
                        }

                        ActivityListView()

                        NavigationLink("Match History") {
                            if let contact = contactManager.selectedContact {
                                MatchHistoryView(contactUid: contact.uid)
                            }
                        }
                        .padding(.top, 8)

                        Button("Clear Selection", role: .destructive) {
                            contactManager.selectedContact = nil
                        }
                        .padding(.bottom, 16)
                    }
                } else {
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
            }
            .padding()
            .navigationTitle("Let's do it!")
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
