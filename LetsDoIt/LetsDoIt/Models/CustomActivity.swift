import Foundation

struct CustomActivity: ActivityDisplayable, Identifiable, Codable, Hashable {
    let id: String
    let emoji: String
    let label: String
    let category: ActivityCategory
    let createdAt: Date?
    let visibleTo: [String]

    init(
        id: String = UUID().uuidString,
        emoji: String,
        label: String,
        category: ActivityCategory,
        createdAt: Date? = nil,
        visibleTo: [String] = []
    ) {
        self.id = id
        self.emoji = emoji
        self.label = label
        self.category = category
        self.createdAt = createdAt
        self.visibleTo = visibleTo
    }

    // MARK: - Hashable
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: CustomActivity, rhs: CustomActivity) -> Bool {
        lhs.id == rhs.id
    }
}
