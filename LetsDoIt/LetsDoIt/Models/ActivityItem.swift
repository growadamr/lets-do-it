import Foundation

// MARK: - Protocol

protocol ActivityDisplayable: Identifiable, Hashable {
    var id: String { get }
    var emoji: String { get }
    var label: String { get }
    var category: ActivityCategory { get }
}

// MARK: - Catalog Model

struct ActivityItem: ActivityDisplayable, Identifiable, Hashable {
    let id: String          // unique key, e.g., "drinks"
    let emoji: String
    let label: String
    let category: ActivityCategory
}

// MARK: - Category

enum ActivityCategory: String, CaseIterable, Codable {
    case activities = "Activities"
    case places = "Places"
    case general = "General"
}
