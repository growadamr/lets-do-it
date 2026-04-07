import SwiftUI

struct ContactsListView: View {
    @ObservedObject private var contactManager = ContactManager.shared
    @State private var activeSheet: ContactsSheet?
    @State private var showingDeleteAlert = false
    @State private var contactToDelete: String?
    @State private var messagingContactId: String?
    @State private var messageError: String?
    var onSelect: (() -> Void)?

    enum ContactsSheet: Identifiable {
        case addContact
        case createCode
        case nameContact(ContactManager.Contact)
        var id: String {
            switch self {
            case .addContact: return "addContact"
            case .createCode: return "createCode"
            case .nameContact(let c): return "name-\(c.uid)"
            }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if contactManager.contacts.isEmpty {
                    emptyState
                } else {
                    contactsList
                }
            }
            .navigationTitle("Contacts")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        activeSheet = .addContact
                    } label: {
                        Image(systemName: "person.badge.plus")
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
                case .addContact:
                    AddContactSheet()
                        .presentationDetents([.medium])
                case .createCode:
                    CreateCodeView()
                        .presentationDetents([.medium])
                case .nameContact(let contact):
                    SetContactNameSheet(contact: contact)
                        .presentationDetents([.medium])
                }
            }
            .alert(
                "Remove Contact",
                isPresented: $showingDeleteAlert,
                presenting: contactToDelete
            ) { contactUid in
                Button("Remove", role: .destructive) {
                    Task {
                        do {
                            try await contactManager.removeContact(contactUid: contactUid)
                        } catch {
                            print("Failed to remove contact: \(error)")
                        }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: { contactUid in
                if let contact = contactManager.contacts.first(where: { $0.uid == contactUid }) {
                    Text("Are you sure you want to remove \(contact.displayName)?")
                }
            }
            .alert(
                "Message Error",
                isPresented: .constant(messageError != nil)
            ) {
                Button("OK") { messageError = nil }
            } message: {
                Text(messageError ?? "")
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 24) {
            Image(systemName: "person.2.slash")
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            Text("No contacts yet")
                .font(.title2.bold())

            Text("Add someone to start matching activities!")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 12) {
                Button {
                    activeSheet = .addContact
                } label: {
                    Label("Add a Contact", systemImage: "person.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button {
                    activeSheet = .createCode
                } label: {
                    Label("Share Your Code", systemImage: "qrcode")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            .padding(.horizontal, 40)
        }
        .padding()
    }

    // MARK: - Contacts List

    private var contactsList: some View {
        List {
            Section("Your Contacts") {
                ForEach(contactManager.contacts) { contact in
                    ContactRow(
                        contact: contact,
                        onSelect: onSelect,
                        isMessaging: messagingContactId == contact.uid,
                        onMessage: { startMessage(contact: contact) }
                    )
                    .swipeActions(edge: .trailing) {
                        Button("Remove", role: .destructive) {
                            contactToDelete = contact.uid
                            showingDeleteAlert = true
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Message Action

    private func startMessage(contact: ContactManager.Contact) {
        guard !contact.uid.isEmpty else { return }
        Task {
            messagingContactId = contact.uid
            do {
                let conversation = try await MessagingManager.shared.createDM(with: contact.uid)
                NotificationCenter.default.post(
                    name: .openConversation,
                    object: nil,
                    userInfo: ["id": conversation.id]
                )
            } catch {
                messageError = error.localizedDescription
            }
            messagingContactId = nil
        }
    }
}

// MARK: - Contact Row

struct ContactRow: View {
    let contact: ContactManager.Contact
    var onSelect: (() -> Void)?
    let isMessaging: Bool
    let onMessage: () -> Void
    @ObservedObject private var contactManager = ContactManager.shared

    var body: some View {
        let needsName = contact.displayName.trimmingCharacters(in: .whitespaces).isEmpty

        HStack(spacing: 12) {
            Button {
                if needsName {
                    contactManager.pendingContactForNaming = contact
                } else {
                    contactManager.selectedContact = contact
                    onSelect?()
                }
            } label: {
                HStack(spacing: 12) {
                    Circle()
                        .fill(contactManager.selectedContact?.uid == contact.uid ? Color.green : Color.gray)
                        .frame(width: 10, height: 10)

                    VStack(alignment: .leading, spacing: 4) {
                        if needsName {
                            Text("Tap to set name")
                                .font(.body)
                                .foregroundColor(.secondary)
                        } else {
                            Text(contact.displayName)
                                .font(.body)
                                .foregroundColor(.primary)
                        }

                        if contactManager.selectedContact?.uid == contact.uid {
                            Text("Selected")
                                .font(.caption)
                                .foregroundColor(.green)
                        } else if !needsName {
                            Text("Tap to select")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()

                    if contactManager.selectedContact?.uid == contact.uid {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    }
                }
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)

            // Message button
            Button {
                onMessage()
            } label: {
                if isMessaging {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "message.fill")
                        .font(.body)
                        .foregroundColor(.accentColor)
                }
            }
            .buttonStyle(.plain)
            .disabled(isMessaging || contact.uid.isEmpty)
        }
    }
}

// MARK: - Add Contact Sheet

struct AddContactSheet: View {
    @State private var code = ""
    @State private var isAdding = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var contactManager = ContactManager.shared

    var body: some View {
        VStack(spacing: 32) {
            Text("Enter their code")
                .font(.headline)

            TextField("000000", text: $code)
                .font(.system(size: 36, weight: .bold, design: .monospaced))
                .kerning(6)
                .multilineTextAlignment(.center)
                .keyboardType(.numberPad)
                .frame(maxWidth: 240)

            Button("Add Contact") {
                Task { await addContact() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(code.count != 6 || isAdding)

            if isAdding {
                ProgressView()
            }

            if let error = errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
            }

            Spacer()
        }
        .padding()
    }

    private func addContact() async {
        isAdding = true
        errorMessage = nil
        do {
            try await contactManager.joinWithCode(code)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isAdding = false
    }
}
