import SwiftUI

// MARK: - Single Contact Picker View

/// Simple single-select contact picker with search.
/// Used by CreateScheduleView and EditScheduleView for contact selection.
struct SingleContactPickerView: View {
    @Binding var selectedUid: String?

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
                        SingleContactRow(
                            contact: contact,
                            isSelected: selectedUid == contact.uid
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedUid = contact.uid
                            dismiss()
                        }
                    }
                }
            }
            .listStyle(.plain)
            .searchable(text: $searchText, prompt: "Search contacts")
            .navigationTitle("Select Contact")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Single Contact Row

struct SingleContactRow: View {
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
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Preview

#Preview {
    struct PreviewWrapper: View {
        @State private var uid: String?

        var body: some View {
            VStack {
                Text(uid ?? "No contact selected")
                    .padding()

                Button("Open Picker") {}
            }
            .sheet(isPresented: .constant(true)) {
                SingleContactPickerView(selectedUid: $uid)
            }
        }
    }
    return PreviewWrapper()
}
