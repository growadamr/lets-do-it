import Foundation

struct LinkPreview: Codable, Hashable {
    let url: String
    let title: String?
    let description: String?
    let imageUrl: String?
}

struct Message: Identifiable, Codable, Hashable {
    let id: String
    let senderUid: String
    let senderName: String
    let text: String
    let createdAt: Date?
    let imageUrl: String?
    let linkPreview: LinkPreview?
    let readBy: [String: Date]   // uid → read timestamp
}
