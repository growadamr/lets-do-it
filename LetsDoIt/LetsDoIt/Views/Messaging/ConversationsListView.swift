import SwiftUI

/// Conversation list view with unread badges, swipe actions (delete/mute), and empty state.
/// Part of Phase 2, Step 5.
struct ConversationsListView: View {
    @StateObject private var messagingManager = MessagingManager.shared
    @State private var showingDeleteAlert = false
    @State private var conversationToDelete: String?
    @State private var deleteError: String?
    @State private var muteError: String?

    private var showingErrorAlert: Bool {
        deleteError != nil || muteError != nil
    }

    private var errorMessage: String? {
        deleteError ?? muteError
    }

    var body: some View {
        Group {
            if messagingManager.conversations.isEmpty {
                emptyState
            } else {
                conversationList
            }
        }
        .onAppear {
            messagingManager.startListeningConversations()
            messagingManager.startListeningMemberships()
        }
        .onDisappear {
            messagingManager.stopListeningConversations()
            messagingManager.stopListeningMemberships()
        }
        .alert("Delete Conversation", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let conversationId = conversationToDelete {
                    Task {
                        await deleteConversation(conversationId)
                    }
                }
            }
        } message: {
            Text("This will permanently delete this conversation and all messages.")
        }
        .alert("Error", isPresented: .constant(showingErrorAlert)) {
            Button("OK") {
                deleteError = nil
                muteError = nil
            }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Conversation List

    private var conversationList: some View {
        List {
            ForEach(messagingManager.conversations) { conversation in
                NavigationLink(value: conversation) {
                    ConversationRow(
                        conversation: conversation,
                        isUnread: isUnread(conversation),
                        isMuted: isMuted(conversation)
                    )
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    // Mute button
                    Button {
                        Task {
                            await toggleMute(conversation.id)
                        }
                    } label: {
                        Label(
                            isMuted(conversation) ? "Unmute" : "Mute",
                            systemImage: isMuted(conversation) ? "speaker.slash.fill" : "speaker.fill"
                        )
                    }
                    .tint(isMuted(conversation) ? .blue : .orange)

                    // Delete button
                    Button(role: .destructive) {
                        conversationToDelete = conversation.id
                        showingDeleteAlert = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationDestination(for: Conversation.self) { conversation in
            ChatView(conversationId: conversation.id, conversation: conversation)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "message")
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            Text("No conversations yet")
                .font(.title2.bold())

            Text("Start a conversation with your contacts")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    // MARK: - Helpers

    private func isUnread(_ conversation: Conversation) -> Bool {
        guard let lastMsgTime = conversation.lastMessage?.timestamp else {
            return false
        }
        let membership = messagingManager.memberships[conversation.id]
        guard let lastReadAt = membership?.lastReadAt else {
            return true  // Never read
        }
        return lastMsgTime > lastReadAt
    }

    private func isMuted(_ conversation: Conversation) -> Bool {
        messagingManager.memberships[conversation.id]?.muted ?? false
    }

    private func toggleMute(_ conversationId: String) async {
        do {
            try await messagingManager.toggleMute(conversationId: conversationId)
        } catch {
            muteError = error.localizedDescription
        }
    }

    private func deleteConversation(_ conversationId: String) async {
        do {
            try await messagingManager.deleteConversation(conversationId)
        } catch {
            deleteError = error.localizedDescription
        }
        conversationToDelete = nil
    }

    // MARK: - Conversation Row Title

    private func title(for conversation: Conversation) -> String {
        switch conversation.type {
        case .group:
            return conversation.metadata?.name ?? "Unnamed Group"
        case .dm:
            let uid = AuthManager.shared.userId ?? ""
            let otherName = conversation.participantNames.first { $0.key != uid }?.value
            return otherName ?? "Unknown"
        case .event:
            return "Event Chat"
        }
    }
}

// MARK: - ConversationRow

struct ConversationRow: View {
    let conversation: Conversation
    let isUnread: Bool
    let isMuted: Bool

    var body: some View {
        HStack(spacing: 12) {
            // Avatar / icon
            Circle()
                .fill(Color.accentColor.opacity(0.2))
                .frame(width: 44, height: 44)
                .overlay {
                    Image(systemName: conversation.type == .group ? "person.3.fill" : "person.fill")
                        .font(.title3)
                        .foregroundColor(.accentColor)
                }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title)
                        .font(isUnread ? .headline : .body.bold())
                        .lineLimit(1)

                    if isMuted {
                        Image(systemName: "speaker.slash.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    if let timestamp = conversation.lastMessage?.timestamp {
                        Text(timestamp, style: .time)
                            .font(.caption)
                            .foregroundColor(isUnread ? .primary : .secondary)
                    }
                }

                if let lastMsg = conversation.lastMessage {
                    HStack(spacing: 4) {
                        if isUnread {
                            Circle()
                                .fill(Color.accentColor)
                                .frame(width: 8, height: 8)
                        }

                        Text(lastMessageSnippet(lastMsg))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var title: String {
        switch conversation.type {
        case .group:
            return conversation.metadata?.name ?? "Unnamed Group"
        case .dm:
            let uid = AuthManager.shared.userId ?? ""
            return conversation.participantNames.first { $0.key != uid }?.value ?? "Unknown"
        case .event:
            return "Event Chat"
        }
    }

    private func lastMessageSnippet(_ lastMsg: LastMessage) -> String {
        let senderPrefix = lastMsg.senderName.isEmpty ? "" : "\(lastMsg.senderName): "
        let text = lastMsg.text.isEmpty ? (lastMsg.senderUid == AuthManager.shared.userId ? "Sent an image" : "Sent an image") : lastMsg.text
        return senderPrefix + text
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        ConversationsListView()
            .navigationTitle("Messages")
    }
}
