import SwiftUI

/// Conversation list view with unread badges, swipe actions (delete/mute), and empty state.
/// Part of Phase 2, Step 5.
struct ConversationsListView: View {
    @StateObject private var messagingManager = MessagingManager.shared
    @StateObject private var contactManager = ContactManager.shared
    @Environment(NetworkMonitor.self) private var networkMonitor
    @State private var showingDeleteAlert = false
    @State private var conversationToDelete: String?
    @State private var deleteError: String?
    @State private var muteError: String?

    // New conversation flow (Phase 2, Step 7)
    @State private var showingNewConversation: Bool = false
    @State private var createdConversation: Conversation?
    @State private var navigateToNewConversation: Bool = false

    // Loading state — differentiate "initial load" from "loaded but empty"
    @State private var isLoadingConversations: Bool = true

    // Filtered conversations (only those with at least one message)
    private var activeConversations: [Conversation] {
        messagingManager.conversations.filter { $0.lastMessage != nil }
    }

    private var showingErrorAlert: Bool {
        deleteError != nil || muteError != nil
    }

    private var errorMessage: String? {
        deleteError ?? muteError
    }

    var body: some View {
        Group {
            if isLoadingConversations && activeConversations.isEmpty {
                loadingState
            } else if activeConversations.isEmpty {
                emptyState
            } else {
                conversationList
            }
        }
        // Offline banner
        .overlay(alignment: .top) {
            if !networkMonitor.isConnected {
                offlineBanner
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingNewConversation = true
                } label: {
                    Image(systemName: "square.and.pencil")
                }
            }
        }
        .sheet(isPresented: $showingNewConversation) {
            NewConversationView { conversation in
                createdConversation = conversation
                navigateToNewConversation = true
            }
        }
        .navigationDestination(isPresented: $navigateToNewConversation) {
            if let conversation = createdConversation {
                ChatView(conversationId: conversation.id, conversation: conversation)
            }
        }
        .onAppear {
            messagingManager.startListeningConversations()
            messagingManager.startListeningMemberships()
        }
        .onChange(of: messagingManager.conversations) { _, _ in
            // Reset loading flag once the listener delivers its first snapshot,
            // even if the filtered result is empty (no conversations with messages yet).
            isLoadingConversations = false
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

    // MARK: - Offline Banner

    private var offlineBanner: some View {
        HStack {
            Image(systemName: "wifi.slash")
                .font(.caption)
            Text("You're offline. Messages will sync when you reconnect.")
                .font(.caption)
            Spacer()
        }
        .foregroundColor(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.orange)
        .transition(.move(edge: .top).combined(with: .opacity))
        .animation(.easeInOut(duration: 0.3), value: networkMonitor.isConnected)
    }

    // MARK: - Loading State

    private var loadingState: some View {
        VStack(spacing: 16) {
            ProgressView("Loading conversations…")
                .font(.body)
        }
        .padding()
    }

    // MARK: - Conversation List

    private var conversationList: some View {
        List {
            ForEach(activeConversations) { conversation in
                NavigationLink(value: conversation) {
                    ConversationRow(
                        conversation: conversation,
                        isUnread: isUnread(conversation),
                        isMuted: isMuted(conversation),
                        contacts: contactManager.contacts
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
}

// MARK: - ConversationRow

struct ConversationRow: View {
    let conversation: Conversation
    let isUnread: Bool
    let isMuted: Bool
    let contacts: [ContactManager.Contact]

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

                        Text(lastMessageSnippet(lastMsg, in: conversation))
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
            let myUid = AuthManager.shared.userId ?? ""
            let otherUid = conversation.participants.first { $0 != myUid }
            // 1. User-set contact name (from ContactManager)
            if let uid = otherUid,
               let contact = contacts.first(where: { $0.uid == uid }),
               !contact.displayName.isEmpty {
                return contact.displayName
            }
            // 2. Participant names cache from conversation doc
            if let uid = otherUid,
               let name = conversation.participantNames[uid],
               !name.isEmpty {
                return name
            }
            return "Unknown"
        case .event:
            return "Event Chat"
        }
    }

    private func senderName(for senderUid: String, in conversation: Conversation) -> String {
        // 1. User-set contact name (from ContactManager)
        if let contact = contacts.first(where: { $0.uid == senderUid }),
           !contact.displayName.isEmpty {
            return contact.displayName
        }
        // 2. Participant names cache from conversation doc
        if let name = conversation.participantNames[senderUid],
           !name.isEmpty {
            return name
        }
        // 3. Last resort — show nothing instead of "Unknown"
        return ""
    }

    private func lastMessageSnippet(_ lastMsg: LastMessage, in conversation: Conversation) -> String {
        let sender = senderName(for: lastMsg.senderUid, in: conversation)
        let senderPrefix = sender.isEmpty ? "" : "\(sender): "
        let text = lastMsg.text.isEmpty ? "📷 Photo" : lastMsg.text
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
