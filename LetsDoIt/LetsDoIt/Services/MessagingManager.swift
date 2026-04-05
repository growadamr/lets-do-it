import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import UIKit

@MainActor
class MessagingManager: ObservableObject {
    static let shared = MessagingManager()

    /// All conversations the current user is a member of, sorted by lastMessage.timestamp descending
    @Published var conversations: [Conversation] = []

    /// Messages for the currently viewed conversation
    @Published var messages: [Message] = []

    /// Memberships for the current user's conversations (used for unread badges and mute state)
    @Published var memberships: [String: ConversationMembership] = [:]  // conversationId → membership

    /// Loading state for pagination (fetching older messages)
    @Published var isLoadingMoreMessages: Bool = false

    /// Whether an image upload is currently in progress.
    @Published var isUploadingImage: Bool = false

    private let db = Firestore.firestore()
    private var conversationListener: ListenerRegistration?
    private var membershipListener: ListenerRegistration?
    private var messagesListener: ListenerRegistration?

    private let messagesPageSize = 50

    private init() {}

    // MARK: - Current User Helper

    private var currentUid: String? {
        Auth.auth().currentUser?.uid
    }

    private func requireUid() throws -> String {
        guard let uid = currentUid else {
            throw MessagingError.notAuthenticated
        }
        return uid
    }

    // MARK: - Conversation CRUD

    /// Create a 1-on-1 DM. Checks for existing DM between the two users first.
    func createDM(with participantUid: String) async throws -> Conversation {
        let uid = try requireUid()
        guard uid != participantUid else { throw MessagingError.cannotMessageSelf }

        // Check for existing DM
        let existing = try await db.collection("conversations")
            .whereField("type", isEqualTo: "dm")
            .getDocuments()

        for doc in existing.documents {
            let data = doc.data()
            if let participants = data["participants"] as? [String],
               participants.contains(uid),
               participants.contains(participantUid) {
                // Existing DM found — return it
                return try decodeConversation(doc: doc, data: data)
            }
        }

        // Build participant names cache
        var participantNames: [String: String] = [:]
        participantNames[uid] = try await fetchDisplayName(uid: uid)
        participantNames[participantUid] = try await fetchDisplayName(uid: participantUid)

        // Create new DM conversation
        let ref = db.collection("conversations").document()
        let conversationId = ref.documentID
        let data: [String: Any] = [
            "type": ConversationType.dm.rawValue,
            "participants": [uid, participantUid],
            "createdBy": uid,
            "createdAt": FieldValue.serverTimestamp(),
            "participantNames": participantNames
        ]

        try await ref.setData(data)
        try await createMemberships(conversationId: conversationId, participantUids: [uid, participantUid])

        return Conversation(
            id: conversationId,
            type: .dm,
            participants: [uid, participantUid],
            createdBy: uid,
            createdAt: nil,
            lastMessage: nil,
            metadata: nil,
            participantNames: participantNames
        )
    }

    /// Create a group conversation with the given name and participants.
    func createGroup(name: String, participantUids: [String]) async throws -> Conversation {
        let uid = try requireUid()
        guard participantUids.count >= 1 else { throw MessagingError.tooFewParticipants }
        guard !participantUids.contains(uid) else { throw MessagingError.creatorAlreadyIncluded }

        let allParticipants = participantUids + [uid]

        // Build participant names cache
        var participantNames: [String: String] = [:]
        for pUid in allParticipants {
            participantNames[pUid] = try await fetchDisplayName(uid: pUid)
        }

        let ref = db.collection("conversations").document()
        let conversationId = ref.documentID

        let data: [String: Any] = [
            "type": ConversationType.group.rawValue,
            "participants": allParticipants,
            "createdBy": uid,
            "createdAt": FieldValue.serverTimestamp(),
            "metadata": ["name": name],
            "participantNames": participantNames
        ]

        try await ref.setData(data)
        try await createMemberships(conversationId: conversationId, participantUids: allParticipants)

        return Conversation(
            id: conversationId,
            type: .group,
            participants: allParticipants,
            createdBy: uid,
            createdAt: nil,
            lastMessage: nil,
            metadata: ConversationMetadata(name: name, eventId: nil),
            participantNames: participantNames
        )
    }

    /// Delete a conversation and all associated data (messages + memberships).
    func deleteConversation(_ conversationId: String) async throws {
        let uid = try requireUid()

        // Verify membership
        try await verifyMembership(conversationId: conversationId, uid: uid)

        // Delete all messages in subcollection
        let messagesSnapshot = try await db.collection("conversations")
            .document(conversationId)
            .collection("messages")
            .getDocuments()

        let batch = db.batch()
        for doc in messagesSnapshot.documents {
            batch.deleteDocument(doc.reference)
        }

        // Delete memberships for all participants
        let conversationsDoc = db.collection("conversations").document(conversationId)
        let convSnapshot = try? await conversationsDoc.getDocument()
        if let data = convSnapshot?.data(),
           let participants = data["participants"] as? [String] {
            for pUid in participants {
                let membershipRef = db.collection("users")
                    .document(pUid)
                    .collection("conversationMemberships")
                    .document(conversationId)
                batch.deleteDocument(membershipRef)
            }
        }

        // Delete conversation doc
        batch.deleteDocument(conversationsDoc)

        try await batch.commit()
    }

    /// Update a group conversation's name.
    func updateConversationName(_ name: String, conversationId: String) async throws {
        let uid = try requireUid()
        try await verifyMembership(conversationId: conversationId, uid: uid)

        try await db.collection("conversations").document(conversationId)
            .updateData(["metadata.name": name])
    }

    // MARK: - Real-Time Conversation Listener

    /// Start listening to conversations the current user is a member of.
    /// Sorted by lastMessage.timestamp descending.
    func startListeningConversations() {
        guard let uid = currentUid else { return }

        conversationListener?.remove()

        let query = db.collection("conversations")
            .whereField("participants", arrayContains: uid)
            .order(by: "lastMessage.timestamp", descending: true)

        conversationListener = query.addSnapshotListener { [weak self] snapshot, error in
            guard let self, let documents = snapshot?.documents else {
                if let error { print("Conversation listener error: \(error)") }
                return
            }

            var convos: [Conversation] = []
            for doc in documents {
                let data = doc.data()
                if let convo = try? self.decodeConversation(doc: doc, data: data) {
                    convos.append(convo)
                }
            }

            // Client-side sort fallback for conversations with no lastMessage
            convos.sort {
                let t1 = $0.lastMessage?.timestamp ?? $0.createdAt ?? Date.distantPast
                let t2 = $1.lastMessage?.timestamp ?? $1.createdAt ?? Date.distantPast
                return t1 > t2
            }

            self.conversations = convos
        }
    }

    func stopListeningConversations() {
        conversationListener?.remove()
        conversationListener = nil
        conversations = []
    }

    // MARK: - Membership Listener & Mute

    /// Start listening to the current user's conversation memberships.
    /// Used for unread badge computation and mute state.
    func startListeningMemberships() {
        guard let uid = currentUid else { return }

        membershipListener?.remove()

        let query = db.collection("users")
            .document(uid)
            .collection("conversationMemberships")

        membershipListener = query.addSnapshotListener { [weak self] snapshot, error in
            guard let self, let documents = snapshot?.documents else {
                if let error { print("Membership listener error: \(error)") }
                return
            }

            var dict: [String: ConversationMembership] = [:]
            for doc in documents {
                let data = doc.data()
                let membership = ConversationMembership(
                    conversationId: data["conversationId"] as? String ?? doc.documentID,
                    lastReadAt: (data["lastReadAt"] as? Timestamp)?.dateValue(),
                    muted: data["muted"] as? Bool ?? false,
                    joinedAt: (data["joinedAt"] as? Timestamp)?.dateValue()
                )
                dict[membership.conversationId] = membership
            }

            self.memberships = dict
        }
    }

    func stopListeningMemberships() {
        membershipListener?.remove()
        membershipListener = nil
        memberships = [:]
    }

    /// Toggle the mute state for a conversation.
    func toggleMute(conversationId: String) async throws {
        let uid = try requireUid()

        guard let currentMembership = memberships[conversationId] else {
            throw MessagingError.conversationNotFound
        }

        let membershipRef = db.collection("users")
            .document(uid)
            .collection("conversationMemberships")
            .document(conversationId)

        try await membershipRef.updateData(["muted": !currentMembership.muted])
    }

    // MARK: - Message CRUD

    /// Send a message to a conversation. Optionally include an image URL (from uploadImage),
    /// a link preview (from LinkPreviewGenerator), and/or a pre-generated message ID
    /// (for non-blocking preview attachment).
    func sendMessage(text: String, conversationId: String, imageUrl: String? = nil, linkPreview: LinkPreview? = nil, messageId: String? = nil) async throws {
        let uid = try requireUid()
        try await verifyMembership(conversationId: conversationId, uid: uid)

        let senderName = try await fetchDisplayName(uid: uid)
        let ref = db.collection("conversations")
            .document(conversationId)
            .collection("messages")
            .document(messageId ?? UUID().uuidString)

        var data: [String: Any] = [
            "senderUid": uid,
            "senderName": senderName,
            "text": text,
            "createdAt": FieldValue.serverTimestamp(),
            "readBy": [uid: FieldValue.serverTimestamp()]
        ]

        if let imageUrl {
            data["imageUrl"] = imageUrl
        }

        if let linkPreview {
            var lpData: [String: Any] = ["url": linkPreview.url]
            if let title = linkPreview.title { lpData["title"] = title }
            if let description = linkPreview.description { lpData["description"] = description }
            if let imageUrl = linkPreview.imageUrl { lpData["imageUrl"] = imageUrl }
            data["linkPreview"] = lpData
        }

        try await ref.setData(data)
    }

    /// Attach a link preview to an existing message (used for non-blocking preview generation).
    func attachLinkPreview(_ linkPreview: LinkPreview, toMessage messageId: String, inConversation conversationId: String) async throws {
        var lpData: [String: Any] = ["url": linkPreview.url]
        if let title = linkPreview.title { lpData["title"] = title }
        if let description = linkPreview.description { lpData["description"] = description }
        if let imageUrl = linkPreview.imageUrl { lpData["imageUrl"] = imageUrl }

        try await db.collection("conversations")
            .document(conversationId)
            .collection("messages")
            .document(messageId)
            .updateData(["linkPreview": lpData])
    }

    /// Fetch a page of messages using cursor-based pagination.
    /// Returns `(messages, nextCursor)` — cursor is nil if no more pages.
    func fetchMessages(conversationId: String, cursor: Message? = nil) async throws -> (messages: [Message], nextCursor: Message?) {
        let uid = try requireUid()
        try await verifyMembership(conversationId: conversationId, uid: uid)

        var query = db.collection("conversations")
            .document(conversationId)
            .collection("messages")
            .order(by: "createdAt", descending: true)
            .limit(to: messagesPageSize)

        if let cursor {
            // Create a document snapshot for the cursor
            let docRef = db.collection("conversations")
                .document(conversationId)
                .collection("messages")
                .document(cursor.id)
            // We need an actual snapshot for start(after:)
            let cursorDoc = try await docRef.getDocument()
            query = query.start(afterDocument: cursorDoc)
        }

        let snapshot = try await query.getDocuments()
        var fetched: [Message] = []

        for doc in snapshot.documents {
            if let msg = try? decodeMessage(doc: doc, data: doc.data()) {
                fetched.append(msg)
            }
        }

        let nextCursor = fetched.last
        return (fetched, nextCursor)
    }

    /// Delete a message. If it has an image, also delete from Storage.
    func deleteMessage(_ messageId: String, from conversationId: String) async throws {
        let uid = try requireUid()
        try await verifyMembership(conversationId: conversationId, uid: uid)

        let msgRef = db.collection("conversations")
            .document(conversationId)
            .collection("messages")
            .document(messageId)

        // Check for image before deleting
        let doc = try? await msgRef.getDocument()
        if let data = doc?.data(), let imageUrl = data["imageUrl"] as? String, !imageUrl.isEmpty {
            // Delete from Storage — extract path from URL
            deleteImageFromStorage(imageUrl: imageUrl, conversationId: conversationId, messageId: messageId)
        }

        try await msgRef.delete()
    }

    /// Mark all messages in a conversation as read by the current user.
    func markMessagesRead(conversationId: String) async throws {
        let uid = try requireUid()
        try await verifyMembership(conversationId: conversationId, uid: uid)

        let now = Timestamp(date: Date())

        let snapshot = try await db.collection("conversations")
            .document(conversationId)
            .collection("messages")
            .whereField("readBy.\(uid)", isEqualTo: NSNull())
            .getDocuments()

        let batch = db.batch()
        for doc in snapshot.documents {
            batch.updateData(["readBy.\(uid)": now], forDocument: doc.reference)
        }

        if !snapshot.documents.isEmpty {
            try await batch.commit()
        }

        // Also update membership lastReadAt
        let membershipRef = db.collection("users")
            .document(uid)
            .collection("conversationMemberships")
            .document(conversationId)

        try await membershipRef.setData(["lastReadAt": now], merge: true)
    }

    // MARK: - Real-Time Messages Listener

    /// Start listening to messages in a specific conversation.
    func startListeningMessages(conversationId: String) {
        messagesListener?.remove()
        messages = []

        let query = db.collection("conversations")
            .document(conversationId)
            .collection("messages")
            .order(by: "createdAt", descending: false)

        messagesListener = query.addSnapshotListener { [weak self] snapshot, error in
            guard let self, let documents = snapshot?.documents else {
                if let error { print("Messages listener error: \(error)") }
                return
            }

            var msgs: [Message] = []
            for doc in documents {
                if let msg = try? self.decodeMessage(doc: doc, data: doc.data()) {
                    msgs.append(msg)
                }
            }

            self.messages = msgs
        }
    }

    func stopListeningMessages() {
        messagesListener?.remove()
        messagesListener = nil
        messages = []
    }

    // MARK: - Image Upload

    /// Upload an image to Firebase Storage for a message.
    /// Compresses to JPEG 0.7 quality, resizes to max 1024px longest edge.
    /// Returns the download URL.
    func uploadImage(_ image: UIImage, conversationId: String, messageId: String) async throws -> String {
        isUploadingImage = true
        defer { isUploadingImage = false }

        let resized = resizeImage(image, maxDimension: 1024)
        guard let jpegData = resized.jpegData(compressionQuality: 0.7) else {
            throw MessagingError.imageCompressionFailed
        }

        let filename = UUID().uuidString + ".jpg"
        let storagePath = "chat_images/\(conversationId)/\(messageId)/\(filename)"
        let storageRef = Storage.storage().reference().child(storagePath)

        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"

        _ = try await storageRef.putDataAsync(jpegData, metadata: metadata)
        let url = try await storageRef.downloadURL()
        return url.absoluteString
    }

    // MARK: - Memberships (Internal)

    /// Create conversationMembership docs for each participant.
    private func createMemberships(conversationId: String, participantUids: [String]) async throws {
        let now = FieldValue.serverTimestamp()
        let batch = db.batch()

        for uid in participantUids {
            let ref = db.collection("users")
                .document(uid)
                .collection("conversationMemberships")
                .document(conversationId)

            batch.setData([
                "conversationId": conversationId,
                "joinedAt": now,
                "lastReadAt": now,
                "muted": false
            ], forDocument: ref)
        }

        try await batch.commit()
    }

    /// Verify the user is a member of the conversation.
    private func verifyMembership(conversationId: String, uid: String) async throws {
        let membershipRef = db.collection("users")
            .document(uid)
            .collection("conversationMemberships")
            .document(conversationId)

        let doc = try await membershipRef.getDocument()
        guard doc.exists else {
            throw MessagingError.notAMember
        }
    }

    // MARK: - Helpers

    /// Fetch display name for a UID from the users collection.
    private func fetchDisplayName(uid: String) async throws -> String {
        let doc = try await db.collection("users").document(uid).getDocument()
        if let data = doc.data(), let name = data["displayName"] as? String, !name.isEmpty {
            return name
        }
        return "Unknown"
    }

    /// Decode a Conversation from Firestore data.
    private func decodeConversation(doc: QueryDocumentSnapshot, data: [String: Any]) throws -> Conversation {
        let type = (data["type"] as? String).flatMap { ConversationType(rawValue: $0) } ?? .dm
        let participants = data["participants"] as? [String] ?? []
        let createdBy = data["createdBy"] as? String ?? ""
        let createdAt = (data["createdAt"] as? Timestamp)?.dateValue()
        let participantNames = data["participantNames"] as? [String: String] ?? [:]

        // Decode lastMessage
        var lastMessage: LastMessage?
        if let lm = data["lastMessage"] as? [String: Any] {
            lastMessage = LastMessage(
                text: lm["text"] as? String ?? "",
                senderUid: lm["senderUid"] as? String ?? "",
                senderName: lm["senderName"] as? String ?? "",
                timestamp: (lm["timestamp"] as? Timestamp)?.dateValue()
            )
        }

        // Decode metadata
        var metadata: ConversationMetadata?
        if let md = data["metadata"] as? [String: Any] {
            metadata = ConversationMetadata(
                name: md["name"] as? String,
                eventId: md["eventId"] as? String
            )
        }

        return Conversation(
            id: doc.documentID,
            type: type,
            participants: participants,
            createdBy: createdBy,
            createdAt: createdAt,
            lastMessage: lastMessage,
            metadata: metadata,
            participantNames: participantNames
        )
    }

    /// Decode a Message from Firestore data.
    private func decodeMessage(doc: QueryDocumentSnapshot, data: [String: Any]) throws -> Message {
        let senderUid = data["senderUid"] as? String ?? ""
        let senderName = data["senderName"] as? String ?? ""
        let text = data["text"] as? String ?? ""
        let createdAt = (data["createdAt"] as? Timestamp)?.dateValue()
        let imageUrl = data["imageUrl"] as? String
        let readByRaw = data["readBy"] as? [String: Any] ?? [:]
        var readBy: [String: Date] = [:]
        for (uid, value) in readByRaw {
            if let ts = value as? Timestamp {
                readBy[uid] = ts.dateValue()
            }
        }

        var linkPreview: LinkPreview?
        if let lp = data["linkPreview"] as? [String: Any] {
            linkPreview = LinkPreview(
                url: lp["url"] as? String ?? "",
                title: lp["title"] as? String,
                description: lp["description"] as? String,
                imageUrl: lp["imageUrl"] as? String
            )
        }

        return Message(
            id: doc.documentID,
            senderUid: senderUid,
            senderName: senderName,
            text: text,
            createdAt: createdAt,
            imageUrl: imageUrl,
            linkPreview: linkPreview,
            readBy: readBy
        )
    }

    /// Resize an image to fit within maxDimension pixels on the longest edge.
    private func resizeImage(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let width = size.width
        let height = size.height

        if width <= maxDimension && height <= maxDimension {
            return image
        }

        let scale: CGFloat
        if width > height {
            scale = maxDimension / width
        } else {
            scale = maxDimension / height
        }

        let newSize = CGSize(width: width * scale, height: height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)

        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    /// Delete an image from Firebase Storage.
    private func deleteImageFromStorage(imageUrl: String, conversationId: String, messageId: String) {
        // Extract the storage path from the download URL
        // URL format: https://firebasestorage.googleapis.com/.../o/chat_images%2F...&...
        // We reconstruct the path from known structure
        let filename = imageUrl.components(separatedBy: "/").last ?? ""
        guard !filename.isEmpty && filename.hasSuffix(".jpg") else { return }

        let storagePath = "chat_images/\(conversationId)/\(messageId)/\(filename)"
        let storageRef = Storage.storage().reference().child(storagePath)

        Task.detached {
            try? await storageRef.delete()
        }
    }
}

// MARK: - Error Types

enum MessagingError: LocalizedError {
    case notAuthenticated
    case cannotMessageSelf
    case tooFewParticipants
    case creatorAlreadyIncluded
    case notAMember
    case imageCompressionFailed
    case conversationNotFound

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "You must be signed in."
        case .cannotMessageSelf:
            return "You can't start a conversation with yourself."
        case .tooFewParticipants:
            return "A group needs at least one other participant."
        case .creatorAlreadyIncluded:
            return "You're already included in the participant list."
        case .notAMember:
            return "You're not a member of this conversation."
        case .imageCompressionFailed:
            return "Failed to compress image."
        case .conversationNotFound:
            return "Conversation not found."
        }
    }
}
