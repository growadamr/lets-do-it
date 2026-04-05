import SwiftUI
import PhotosUI

/// Full chat thread view with message list, text input, image attachment, scroll-to-bottom,
/// and pagination for older messages.
/// Part of Phase 2, Step 6 — Chat Thread.
struct ChatView: View {
    let conversationId: String
    let conversation: Conversation?

    @StateObject private var messagingManager = MessagingManager.shared
    @StateObject private var contactManager = ContactManager.shared
    @Environment(NetworkMonitor.self) private var networkMonitor
    @Environment(\.dismiss) private var dismiss

    @State private var messageText: String = ""
    @State private var showingImagePicker: Bool = false
    @State private var pendingImages: [UIImage] = []

    // Upload / send state
    @State private var isSendingMessage: Bool = false
    @State private var sendError: String?
    @State private var failedSendText: String?       // for retry
    @State private var failedSendImages: [UIImage]?  // for retry
    @State private var uploadError: String?

    // Membership error — user was removed from conversation
    @State private var membershipError: String?

    // Locally queued messages that failed to send while offline
    struct PendingLocalMessage: Identifiable {
        let id = UUID()
        let text: String
        let createdAt: Date
    }
    @State private var pendingLocalMessages: [PendingLocalMessage] = []
    @State private var autoRetryScheduled: Bool = false

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
            // Offline banner
            if !networkMonitor.isConnected {
                offlineBanner
            }

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
            if messagingManager.isUploadingImage {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Uploading…")
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
            // Ensure lastReadAt is current when leaving the conversation,
            // so the conversation list doesn't show it as unread.
            markAsRead()
        }
        // Auto-retry pending messages when reconnecting
        .onChange(of: networkMonitor.isConnected) { _, isConnected in
            guard isConnected, !pendingLocalMessages.isEmpty else { return }
            retryPendingMessages()
        }
        .sheet(isPresented: $showingImagePicker) {
            ImagePickerView(selectedImages: $pendingImages, maxSelectionCount: 5)
        }
        // Upload error alert (for non-send-related upload issues)
        .alert("Upload Error", isPresented: .constant(uploadError != nil)) {
            Button("OK") { uploadError = nil }
        } message: {
            Text(uploadError ?? "")
        }
        // Send error alert with retry / send as text options
        .alert("Send Failed", isPresented: .constant(sendError != nil)) {
            // "Send as Text Only" — only when images failed but text is available
            if let imgs = failedSendImages, !imgs.isEmpty,
               let txt = failedSendText, !txt.isEmpty {
                Button("Send as Text Only") {
                    sendAsTextOnly()
                }
            }
            Button("Retry") { retrySend() }
            Button("Cancel", role: .cancel) { sendError = nil }
        } message: {
            Text(sendError ?? "")
        }
        // Membership error — conversation no longer accessible
        .alert("Conversation Unavailable", isPresented: .constant(membershipError != nil)) {
            Button("OK") {
                membershipError = nil
                dismiss()
            }
        } message: {
            Text(membershipError ?? "")
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
                // Remove pending messages that have been synced from server
                syncPendingMessages()
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
                        isGroupConversation: isGroupConversation,
                        resolvedSenderName: isFromCurrentUser(message)
                            ? nil
                            : resolvedSenderName(for: message)
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

            // Locally queued pending messages (sent while offline)
            if !pendingLocalMessages.isEmpty {
                ForEach(pendingLocalMessages) { pending in
                    let dummyMessage = Message(
                        id: pending.id.uuidString,
                        senderUid: AuthManager.shared.userId ?? "",
                        senderName: "",
                        text: pending.text,
                        createdAt: pending.createdAt,
                        imageUrl: nil,
                        linkPreview: nil,
                        readBy: [:]
                    )
                    MessageBubbleView(
                        message: dummyMessage,
                        isFromCurrentUser: true,
                        isGroupConversation: isGroupConversation,
                        isPending: true
                    )
                    .id(pending.id)
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

    private var isUploading: Bool {
        messagingManager.isUploadingImage || isSendingMessage
    }

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
            .disabled(isUploading)

            // Text field
            TextField("Message", text: $messageText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)
                .onSubmit {
                    sendMessage()
                }
                .disabled(isUploading)

            // Send button
            Button {
                sendMessage()
            } label: {
                if isSendingMessage {
                    ProgressView()
                        .scaleEffect(0.9)
                } else {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
            }
            .disabled(!canSend || isUploading)
            .foregroundColor((canSend && !isUploading) ? .blue : .gray)
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

    /// Resolve a sender's display name — contacts first, then participant names cache.
    private func resolvedSenderName(for message: Message) -> String {
        // 1. User-set contact name
        if let contact = contactManager.contacts.first(where: { $0.uid == message.senderUid }),
           !contact.displayName.isEmpty {
            return contact.displayName
        }
        // 2. Participant names cache from conversation doc
        if let name = conversation?.participantNames[message.senderUid],
           !name.isEmpty {
            return name
        }
        // 3. Last resort
        return "Unknown"
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        guard let lastMessage = messagingManager.messages.last else { return }
        proxy.scrollTo(lastMessage.id, anchor: .bottom)
    }

    private func sendMessage() {
        guard canSend, !isUploading else { return }
        isSendingMessage = true
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
                isSendingMessage = false
            } catch MessagingError.notAMember {
                isSendingMessage = false
                membershipError = "You're no longer a member of this conversation."
            } catch {
                isSendingMessage = false
                // If offline, queue locally; otherwise show retry alert
                if !networkMonitor.isConnected && !textToSend.isEmpty {
                    pendingLocalMessages.append(PendingLocalMessage(
                        text: textToSend,
                        createdAt: Date()
                    ))
                } else {
                    failedSendText = textToSend.isEmpty ? nil : textToSend
                    failedSendImages = imagesToSend.isEmpty ? nil : imagesToSend
                    sendError = error.localizedDescription
                }
            }
        }
    }

    /// Re-attempt sending with the previously failed text/images.
    private func retrySend() {
        sendError = nil
        let text = failedSendText ?? ""
        let images = failedSendImages ?? []
        failedSendText = nil
        failedSendImages = nil

        guard !text.isEmpty || !images.isEmpty else { return }

        isSendingMessage = true

        Task {
            do {
                if images.isEmpty {
                    let messageId = UUID().uuidString
                    try await messagingManager.sendMessage(
                        text: text,
                        conversationId: conversationId,
                        messageId: messageId
                    )
                } else {
                    for image in images {
                        let messageId = UUID().uuidString
                        let url = try await messagingManager.uploadImage(
                            image,
                            conversationId: conversationId,
                            messageId: messageId
                        )
                        try await messagingManager.sendMessage(
                            text: text,
                            conversationId: conversationId,
                            imageUrl: url
                        )
                    }
                }
                isSendingMessage = false
            } catch MessagingError.notAMember {
                isSendingMessage = false
                membershipError = "You're no longer a member of this conversation."
            } catch {
                isSendingMessage = false
                sendError = error.localizedDescription
            }
        }
    }

    /// Send the text portion of a failed message without the images.
    private func sendAsTextOnly() {
        guard let text = failedSendText, !text.isEmpty else {
            uploadError = nil
            return
        }
        let failedImages = failedSendImages
        failedSendText = nil
        failedSendImages = nil
        uploadError = nil

        isSendingMessage = true

        Task {
            do {
                let messageId = UUID().uuidString
                try await messagingManager.sendMessage(
                    text: text,
                    conversationId: conversationId,
                    messageId: messageId
                )
                isSendingMessage = false
            } catch MessagingError.notAMember {
                isSendingMessage = false
                membershipError = "You're no longer a member of this conversation."
            } catch {
                isSendingMessage = false
                // If text-only send also fails, fall back to general send error flow
                failedSendText = text
                failedSendImages = failedImages
                sendError = error.localizedDescription
            }
        }
    }

    /// Re-send all locally queued messages after reconnecting.
    private func retryPendingMessages() {
        guard !pendingLocalMessages.isEmpty else { return }
        let toSend = pendingLocalMessages
        pendingLocalMessages.removeAll()

        Task {
            for pending in toSend {
                do {
                    let messageId = UUID().uuidString
                    try await messagingManager.sendMessage(
                        text: pending.text,
                        conversationId: conversationId,
                        messageId: messageId
                    )
                } catch {
                    // If retry fails, put it back in the queue
                    pendingLocalMessages.append(pending)
                    break
                }
            }
        }
    }

    /// Remove pending messages whose text has been synced from the server.
    private func syncPendingMessages() {
        guard !pendingLocalMessages.isEmpty else { return }
        let syncedTexts = Set(messagingManager.messages.map { $0.text })
        pendingLocalMessages.removeAll { pending in
            syncedTexts.contains(pending.text)
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
