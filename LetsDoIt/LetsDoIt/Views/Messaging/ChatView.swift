import SwiftUI

/// Placeholder for Phase 2, Step 6 — Chat Thread.
/// Will be fully implemented with message list, text input, and image attachments.
struct ChatView: View {
    let conversationId: String
    let conversation: Conversation?

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "message.fill")
                .font(.system(size: 50))
                .foregroundColor(.secondary)

            Text("Chat")
                .font(.title2.bold())

            Text("Conversation: \(conversationId)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .navigationTitle(conversation.flatMap { conversationTitle(for: $0) } ?? "Chat")
    }

    private func conversationTitle(for conversation: Conversation) -> String {
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
