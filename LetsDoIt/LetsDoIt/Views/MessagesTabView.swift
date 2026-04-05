import SwiftUI

struct MessagesTabView: View {
    @Environment(DeepLinkRouter.self) private var router
    @StateObject private var messagingManager = MessagingManager.shared
    @State private var navPath = NavigationPath()

    var body: some View {
        NavigationStack(path: $navPath) {
            ConversationsListView()
                .navigationTitle("Messages")
                .navigationDestination(for: Conversation.self) { conversation in
                    ChatView(conversationId: conversation.id, conversation: conversation)
                }
                .navigationDestination(for: String.self) { conversationId in
                    // Deep link destination — look up conversation from manager
                    let conversation = messagingManager.conversations.first { $0.id == conversationId }
                    ChatView(conversationId: conversationId, conversation: conversation)
                }
        }
        .onChange(of: router.route) { _, newRoute in
            guard case .conversation(let id) = newRoute else { return }
            // Append the conversation ID to the navigation path.
            // The conversation may appear shortly via the real-time listener,
            // so we navigate immediately and ChatView handles a nil conversation.
            navPath.append(id)
            router.clear()
        }
    }
}
