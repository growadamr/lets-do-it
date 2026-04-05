import SwiftUI

/// Renders a single message bubble with left/right alignment, optional image, text,
/// sender name (for groups), and timestamp.
/// Part of Phase 2, Step 6 — Chat Thread.
struct MessageBubbleView: View {
    let message: Message
    let isFromCurrentUser: Bool
    let isGroupConversation: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isFromCurrentUser {
                Spacer(minLength: 20)
                bubble
            } else {
                bubble
                Spacer(minLength: 20)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
    }

    // MARK: - Bubble Content

    private var bubble: some View {
        VStack(alignment: isFromCurrentUser ? .trailing : .leading, spacing: 4) {
            // Sender name (groups only, non-self messages)
            if isGroupConversation && !isFromCurrentUser {
                Text(message.senderName)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.leading, isFromCurrentUser ? 0 : 8)
                    .padding(.trailing, isFromCurrentUser ? 8 : 0)
            }

            VStack(alignment: .leading, spacing: 4) {
                // Optional image
                if let imageUrl = message.imageUrl, !imageUrl.isEmpty {
                    AsyncImage(url: URL(string: imageUrl)) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: 220)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        case .failure:
                            Image(systemName: "photo.badge.exclamationmark")
                                .font(.title2)
                                .foregroundColor(.secondary)
                                .frame(width: 220, height: 150)
                        case .empty:
                            ProgressView()
                                .frame(width: 220, height: 150)
                        @unknown default:
                            ProgressView()
                                .frame(width: 220, height: 150)
                        }
                    }
                }

                // Text
                if !message.text.isEmpty {
                    Text(message.text)
                        .font(.body)
                        .foregroundColor(isFromCurrentUser ? .white : .primary)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isFromCurrentUser ? Color.blue : Color(.systemGray5))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            // Timestamp
            if let createdAt = message.createdAt {
                Text(createdAt, style: .time)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.leading, isFromCurrentUser ? 0 : 8)
                    .padding(.trailing, isFromCurrentUser ? 8 : 0)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 16) {
        MessageBubbleView(
            message: Message(
                id: "1",
                senderUid: "other",
                senderName: "Alice",
                text: "Hey, how's it going?",
                createdAt: Date(),
                imageUrl: nil,
                linkPreview: nil,
                readBy: [:]
            ),
            isFromCurrentUser: false,
            isGroupConversation: true
        )

        MessageBubbleView(
            message: Message(
                id: "2",
                senderUid: "me",
                senderName: "Me",
                text: "Great! Just working on the project.",
                createdAt: Date().addingTimeInterval(-60),
                imageUrl: nil,
                linkPreview: nil,
                readBy: [:]
            ),
            isFromCurrentUser: true,
            isGroupConversation: true
        )

        MessageBubbleView(
            message: Message(
                id: "3",
                senderUid: "dm",
                senderName: "Bob",
                text: "See you tomorrow!",
                createdAt: Date().addingTimeInterval(-120),
                imageUrl: nil,
                linkPreview: nil,
                readBy: [:]
            ),
            isFromCurrentUser: false,
            isGroupConversation: false
        )
    }
    .padding()
}
