import Foundation

struct ConversationMembership: Codable, Hashable {
    let conversationId: String
    let lastReadAt: Date?
    let muted: Bool
    let joinedAt: Date?
}
