import SwiftUI

/// Detail view for a single match. Shows the matched activity and contact,
/// with a button to message the matched contact.
struct MatchDetailView: View {
    let match: Match

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var contactManager = ContactManager.shared
    @State private var isStartingDM = false
    @State private var dmError: String?

    private var contactName: String {
        if let contact = contactManager.contacts.first(where: { $0.uid == match.contactUid }),
           !contact.displayName.isEmpty {
            return contact.displayName
        }
        return "Someone"
    }

    private var suggestedMessage: String {
        "Want to \(match.label.lowercased())? \(match.emoji)"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Match") {
                    HStack(spacing: 16) {
                        Text(match.emoji)
                            .font(.system(size: 40))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(match.label)
                                .font(.title3.bold())
                            Text(match.date, style: .relative)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 8)
                }

                Section("With") {
                    HStack(spacing: 12) {
                        Circle()
                            .fill(Color.accentColor.opacity(0.2))
                            .frame(width: 40, height: 40)
                            .overlay {
                                Image(systemName: "person.fill")
                                    .font(.title3)
                                    .foregroundColor(.accentColor)
                            }
                        Text(contactName)
                            .font(.body)
                    }
                }

                Section {
                    Button {
                        startConversation()
                    } label: {
                        HStack {
                            Spacer()
                            if isStartingDM {
                                ProgressView()
                            } else {
                                Label("Message \(contactName)", systemImage: "paperplane")
                                    .fontWeight(.semibold)
                            }
                            Spacer()
                        }
                        .foregroundColor(.accentColor)
                    }
                    .disabled(isStartingDM)
                }

                if let dmError {
                    Section {
                        Label(dmError, systemImage: "exclamationmark.triangle")
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Match")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .bold()
                }
            }
        }
    }

    private func startConversation() {
        isStartingDM = true
        dmError = nil

        Task {
            do {
                let conversation = try await MessagingManager.shared.createDM(with: match.contactUid)
                // Store the prefilled message before navigating
                ChatPrefillStore.shared.set(suggestedMessage, for: conversation.id)
                await MainActor.run {
                    isStartingDM = false
                    dismiss()

                    // Switch to Messages tab and open the conversation
                    NotificationCenter.default.post(
                        name: .openConversationWithMessage,
                        object: nil,
                        userInfo: ["id": conversation.id]
                    )
                }
            } catch {
                await MainActor.run {
                    isStartingDM = false
                    dmError = error.localizedDescription
                }
            }
        }
    }
}

#Preview {
    MatchDetailView(
        match: Match(
            id: "preview_1",
            itemId: "cook",
            contactUid: "preview_uid",
            emoji: "🍳",
            label: "Cook Together",
            date: Date().addingTimeInterval(-300)
        )
    )
}
