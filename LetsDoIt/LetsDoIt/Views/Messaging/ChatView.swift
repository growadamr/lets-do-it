import SwiftUI
import PhotosUI

/// Full chat thread view with message list, text input, image attachment, scroll-to-bottom,
/// and pagination for older messages.
/// Part of Phase 2, Step 6 — Chat Thread.
struct ChatView: View {
    let conversationId: String
    let conversation: Conversation?

    @StateObject private var messagingManager = MessagingManager.shared
    @State private var messageText: String = ""
    @State private var showingImagePicker: Bool = false
    @State private var pendingImages: [UIImage] = []
    @State private var isLoadingUpload: Bool = false
    @State private var uploadError: String?

    private var isGroupConversation: Bool {
        conversation?.type == .group
    }

    /// The ID of the most recent message sent by the current user that has been read by at least one other person.
    private var lastReadSelfMessageId: String? {
        let currentUid = AuthManager.shared.userId ?? ""
        let selfMessages = messagingManager.messages.filter { $0.senderUid == currentUid }
        guard !selfMessages.isEmpty else { return nil }

        // Find the most recent self-message that has at least one reader besides self
        for message in selfMessages.reversed() {
            let otherReaders = message.readBy.filter { $0.key != currentUid }
            if !otherReaders.isEmpty {
                return message.id
            }
        }
        return nil
    }

    var body: some View {
        VStack(spacing: 0) {
            // Pagination loading indicator
            if messagingManager.isLoadingMoreMessages {
                ProgressView("Loading older messages…")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 8)
            }

            // Message list
            messageScrollView

            // Divider
            Divider()

            // Image upload progress
            if isLoadingUpload {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Uploading image…")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
                .padding(.vertical, 4)
            }

            // Pending image thumbnails
            if !pendingImages.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(pendingImages.enumerated()), id: \.offset) { index, image in
                            thumbnailView(for: image, index: index)
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical, 4)
            }

            // Input bar
            inputBar
        }
        .navigationTitle(conversation.flatMap { conversationTitle(for: $0) } ?? "Chat")
        .onAppear {
            messagingManager.startListeningMessages(conversationId: conversationId)
            markAsRead()
        }
        .onDisappear {
            messagingManager.stopListeningMessages()
        }
        .sheet(isPresented: $showingImagePicker) {
            ImagePickerView(selectedImages: $pendingImages, maxSelectionCount: 5)
        }
        .alert("Upload Error", isPresented: .constant(uploadError != nil)) {
            Button("OK") { uploadError = nil }
        } message: {
            Text(uploadError ?? "")
        }
    }

    // MARK: - Message Scroll View

    @State private var paginationCooldown: Date = .distantPast
    @State private var needsScrollToBottom = false

    private var messageScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                messageListContent(proxy: proxy)
            }
            .onTapGesture {
                hideKeyboard()
            }
            .onChange(of: messagingManager.messages.count) { _, _ in
                withAnimation(.easeOut(duration: 0.2)) {
                    scrollToBottom(proxy: proxy)
                }
            }
        }
    }

    private func messageListContent(proxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Color.clear
                .frame(height: 1)
                .id("topSentinel")
                .onAppear {
                    handleTopSentinelReached(proxy: proxy)
                }

            ForEach(messagingManager.messages) { message in
                VStack(alignment: .trailing, spacing: 0) {
                    MessageBubbleView(
                        message: message,
                        isFromCurrentUser: isFromCurrentUser(message),
                        isGroupConversation: isGroupConversation
                    )
                    .id(message.id)

                    // "Seen by" indicator — only on the most recent read self-message
                    if isFromCurrentUser(message),
                       message.id == lastReadSelfMessageId,
                       let conversation {
                        ReadReceiptsView(
                            readBy: message.readBy,
                            participantNames: conversation.participantNames,
                            currentUid: AuthManager.shared.userId ?? ""
                        )
                    }
                }
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.2)) {
                scrollToBottom(proxy: proxy)
            }
        }
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: 8) {
            // Image picker button
            Button {
                showingImagePicker = true
            } label: {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.title3)
                    .foregroundColor(.accentColor)
            }
            .disabled(isLoadingUpload)

            // Text field
            TextField("Message", text: $messageText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)
                .onSubmit {
                    sendMessage()
                }

            // Send button
            Button {
                sendMessage()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundColor(canSend ? .blue : .gray)
            }
            .disabled(!canSend)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private func thumbnailView(for image: UIImage, index: Int) -> some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .frame(width: 60, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                Button {
                    pendingImages.remove(at: index)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.white)
                        .background(Color.black.opacity(0.5))
                        .clipShape(Circle())
                }
                .offset(x: -4, y: -4)
            }
    }

    // MARK: - Helpers

    private var canSend: Bool {
        let trimmed = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty || !pendingImages.isEmpty
    }

    private func isFromCurrentUser(_ message: Message) -> Bool {
        message.senderUid == (AuthManager.shared.userId ?? "")
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        guard let lastMessage = messagingManager.messages.last else { return }
        proxy.scrollTo(lastMessage.id, anchor: .bottom)
    }

    private func sendMessage() {
        guard canSend, !isLoadingUpload else { return }
        isLoadingUpload = true
        let textToSend = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        let imagesToSend = pendingImages
        messageText = ""
        pendingImages = []

        Task {
            do {
                if imagesToSend.isEmpty {
                    // Generate a stable message ID so we can attach a preview after the fact
                    let messageId = UUID().uuidString

                    // Send the message immediately (non-blocking for link preview)
                    try await messagingManager.sendMessage(
                        text: textToSend,
                        conversationId: conversationId,
                        messageId: messageId
                    )

                    // Attempt link preview in the background — update the message doc if successful
                    if let urlString = LinkPreviewGenerator.extractFirstURL(from: textToSend) {
                        Task.detached {
                            if let preview = await LinkPreviewGenerator.generatePreview(url: urlString) {
                                try? await MessagingManager.shared.attachLinkPreview(
                                    preview,
                                    toMessage: messageId,
                                    inConversation: self.conversationId
                                )
                            }
                        }
                    }
                } else {
                    for image in imagesToSend {
                        let messageId = UUID().uuidString
                        let url = try await messagingManager.uploadImage(
                            image,
                            conversationId: conversationId,
                            messageId: messageId
                        )
                        try await messagingManager.sendMessage(
                            text: textToSend,
                            conversationId: conversationId,
                            imageUrl: url
                        )
                    }
                }
            } catch {
                uploadError = error.localizedDescription
            }
            isLoadingUpload = false
        }
    }

    private func markAsRead() {
        Task {
            do {
                try await messagingManager.markMessagesRead(conversationId: conversationId)
            } catch {
                // Silently ignore — not critical
            }
        }
    }

    // MARK: - Pagination

    private func handleTopSentinelReached(proxy: ScrollViewProxy) {
        let now = Date()
        guard now.timeIntervalSince(paginationCooldown) > 2 else { return }
        guard !messagingManager.isLoadingMoreMessages else { return }
        guard let oldestMessage = messagingManager.messages.first else { return }

        paginationCooldown = now

        Task {
            messagingManager.isLoadingMoreMessages = true
            defer { messagingManager.isLoadingMoreMessages = false }

            do {
                let (fetched, _) = try await messagingManager.fetchMessages(
                    conversationId: conversationId,
                    cursor: oldestMessage
                )

                guard !fetched.isEmpty else { return }

                // Prepend older messages, deduplicating by ID
                let existingIds = Set(messagingManager.messages.map { $0.id })
                let newMessages = fetched.filter { !existingIds.contains($0.id) }
                var merged = newMessages
                merged.append(contentsOf: messagingManager.messages)

                messagingManager.messages = merged.sorted {
                    ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast)
                }
            } catch {
                // Silently ignore pagination errors
            }
        }
    }

    // MARK: - Conversation Title

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

// MARK: - Keyboard Dismissal

extension View {
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                         to: nil, from: nil, for: nil)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        ChatView(
            conversationId: "preview-conv-1",
            conversation: Conversation(
                id: "preview-conv-1",
                type: .dm,
                participants: ["me", "other"],
                createdBy: "me",
                createdAt: Date(),
                lastMessage: nil,
                metadata: nil,
                participantNames: ["me": "Me", "other": "Alice"]
            )
        )
    }
}
