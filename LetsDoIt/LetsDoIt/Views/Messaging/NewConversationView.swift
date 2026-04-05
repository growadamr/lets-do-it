import SwiftUI

/// Create a new DM or group conversation flow.
/// Presents a contact picker, lets the user choose DM vs group, and calls
/// `MessagingManager.createDM` or `MessagingManager.createGroup`.
/// Part of Phase 2, Step 7 — New Conversation Flow.
struct NewConversationView: View {
    /// Called with the created conversation on success.
    let onComplete: (Conversation) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var messagingManager = MessagingManager.shared
    @StateObject private var contactManager = ContactManager.shared

    @State private var selectedUids: [String] = []
    @State private var showingContactPicker: Bool = false
    @State private var conversationType: ConversationPickerType = .dm
    @State private var groupName: String = ""
    @State private var createError: String?
    @State private var isCreating: Bool = false

    private enum ConversationPickerType: String, CaseIterable {
        case dm = "Direct Message"
        case group = "Group"
    }

    private var canCreate: Bool {
        guard !isCreating else { return false }
        guard !selectedUids.isEmpty else { return false }

        if conversationType == .group {
            return !groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return true
    }

    /// Resolved contact names for the selected UIDs.
    private var selectedContacts: [ContactManager.Contact] {
        contactManager.contacts.filter { selectedUids.contains($0.uid) }
    }

    var body: some View {
        NavigationStack {
            Form {
                // Contact selection section
                Section {
                    Button {
                        showingContactPicker = true
                    } label: {
                        HStack {
                            Image(systemName: "person.badge.plus")
                                .foregroundColor(.accentColor)
                            Text(selectedUids.isEmpty ? "Select Contacts" : "Change Contacts")
                                .foregroundColor(.accentColor)
                        }
                    }

                    if !selectedContacts.isEmpty {
                        ForEach(selectedContacts, id: \.uid) { contact in
                            HStack {
                                Image(systemName: "person.circle.fill")
                                    .foregroundColor(.secondary)
                                Text(contact.displayName.isEmpty ? "Unnamed Contact" : contact.displayName)
                                    .font(.body)
                            }
                        }
                    }
                } header: {
                    Text("Participants")
                } footer: {
                    if selectedUids.isEmpty {
                        Text("Choose at least one contact to start a conversation.")
                    }
                }

                // Conversation type picker
                Section {
                    Picker("Type", selection: $conversationType) {
                        ForEach(ConversationPickerType.allCases, id: \.self) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Conversation Type")
                } footer: {
                    Text(conversationType == .dm
                         ? "A private conversation between you and one contact."
                         : "A group chat with multiple participants.")
                }

                // Group name (only for groups)
                if conversationType == .group {
                    Section {
                        TextField("Group Name", text: $groupName)
                            .textInputAutocapitalization(.words)
                    } header: {
                        Text("Group Details")
                    } footer: {
                        Text("Give your group a name so everyone knows what it's for.")
                    }
                }

                // Create button
                Section {
                    Button {
                        createConversation()
                    } label: {
                        HStack {
                            Spacer()
                            if isCreating {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "bubble.left.and.bubble.right")
                            }
                            Text("Create")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                    .disabled(!canCreate)
                }
            }
            .navigationTitle("New Conversation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingContactPicker) {
                MultiContactPickerView(selectedUids: $selectedUids)
            }
            .alert("Error", isPresented: .constant(createError != nil)) {
                Button("OK") { createError = nil }
            } message: {
                Text(createError ?? "")
            }
            .onAppear {
                // Auto-select conversation type based on contact count
                updateConversationType()
            }
            .onChange(of: selectedUids.count) { _, _ in
                updateConversationType()
            }
        }
    }

    private func updateConversationType() {
        if selectedUids.count <= 1 {
            conversationType = .dm
        } else {
            conversationType = .group
        }
    }

    private func createConversation() {
        isCreating = true

        Task {
            do {
                let conversation: Conversation
                switch conversationType {
                case .dm:
                    guard let participantUid = selectedUids.first else {
                        createError = "Select at least one contact."
                        isCreating = false
                        return
                    }
                    conversation = try await messagingManager.createDM(with: participantUid)
                case .group:
                    let name = groupName.trimmingCharacters(in: .whitespacesAndNewlines)
                    conversation = try await messagingManager.createGroup(
                        name: name,
                        participantUids: selectedUids
                    )
                }

                // Dismiss and return the conversation to the parent
                dismiss()
                onComplete(conversation)
            } catch {
                createError = error.localizedDescription
            }
            isCreating = false
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        NewConversationView { conversation in
            print("Created: \(conversation.id)")
        }
    }
}
