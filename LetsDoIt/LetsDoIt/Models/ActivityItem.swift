import Foundation

struct ActivityItem: Identifiable, Hashable {
    let id: String          // unique key, e.g., "drinks"
    let emoji: String
    let label: String
    let category: ActivityCategory
}

enum ActivityCategory: String, CaseIterable {
    case activities = "Activities"
    case places = "Places"
    case general = "General"
}
