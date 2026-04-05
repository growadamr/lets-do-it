import SwiftUI

/// Reusable multi-select contact picker with search, checkmarks, and done button.
/// Designed for reuse across messaging (Sprint 1), activity visibility (Sprint 2),
/// and event invitees (Sprint 3).
/// Part of Phase 2, Step 7 — New Conversation Flow.
struct MultiContactPickerView: View {
    /// Output binding — selected contact UIDs are added/removed as the user taps rows.
    @Binding var selectedUids: [String]

    @Environment(\.dismiss) private var dismiss
    @StateObject private var contactManager = ContactManager.shared

    @State private var searchText: String = ""

    /// Filtered contacts based on search text.
    private var filteredContacts: [ContactManager.Contact] {
        guard !searchText.isEmpty else {
            return contactManager.contacts
        }
        let query = searchText.lowercased()
        return contactManager.contacts.filter {
            $0.displayName.lowercased().contains(query)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if filteredContacts.isEmpty {
                    ContentUnavailableView(
                        searchText.isEmpty ? "No Contacts" : "No Matches",
                        systemImage: "person.crop.circle.badge.exclamationmark",
                        description: Text(searchText.isEmpty ? "Your contacts will appear here." : "No contacts match \"\(searchText)\".")
                    )
                    .listRowSeparator(.hidden)
                } else {
                    ForEach(filteredContacts) { contact in
                        ContactPickerRow(
                            contact: contact,
                            isSelected: selectedUids.contains(contact.uid)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            toggleSelection(contact.uid)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .searchable(text: $searchText, prompt: "Search contacts")
            .navigationTitle("Select Contacts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .bold()
                }

                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func toggleSelection(_ uid: String) {
        if let index = selectedUids.firstIndex(of: uid) {
            selectedUids.remove(at: index)
        } else {
            selectedUids.append(uid)
        }
    }
}

// MARK: - Contact Picker Row

struct ContactPickerRow: View {
    let contact: ContactManager.Contact
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color.accentColor.opacity(0.2))
                .frame(width: 40, height: 40)
                .overlay {
                    Image(systemName: "person.fill")
                        .font(.title3)
                        .foregroundColor(.accentColor)
                }

            Text(contact.displayName.isEmpty ? "Unnamed Contact" : contact.displayName)
                .font(.body)

            Spacer()

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundColor(.accentColor)
            } else {
                Image(systemName: "circle")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Preview

#Preview {
    struct PreviewWrapper: View {
        @State private var uids: [String] = []

        var body: some View {
            MultiContactPickerView(selectedUids: $uids)
        }
    }
    return PreviewWrapper()
}
