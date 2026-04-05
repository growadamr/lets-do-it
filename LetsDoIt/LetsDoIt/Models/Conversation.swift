import Foundation

enum ConversationType: String, Codable {
    case dm
    case group
    case event
}

struct LastMessage: Codable, Hashable {
    let text: String
    let senderUid: String
    let senderName: String
    let timestamp: Date?
}

struct ConversationMetadata: Codable, Hashable {
    let name: String?
    let eventId: String?
}

struct Conversation: Identifiable, Codable, Hashable {
    let id: String
    let type: ConversationType
    let participants: [String]          // array of UIDs
    let createdBy: String
    let createdAt: Date?
    let lastMessage: LastMessage?       // denormalized for list view sorting
    let metadata: ConversationMetadata? // group name or linked eventId
    let participantNames: [String: String]  // uid → display name cache
}
