import Foundation

struct ActivityCatalog {
    static let items: [ActivityItem] = [
        // Activities
        ActivityItem(id: "walk", emoji: "🚶", label: "Go for a walk?", category: .activities),
        ActivityItem(id: "workout", emoji: "💪", label: "Work out?", category: .activities),
        ActivityItem(id: "movie", emoji: "🎬", label: "Watch a movie?", category: .activities),
        ActivityItem(id: "cook", emoji: "🍳", label: "Cook together?", category: .activities),
        ActivityItem(id: "game", emoji: "🎮", label: "Play a game?", category: .activities),
        ActivityItem(id: "drive", emoji: "🚗", label: "Go for a drive?", category: .activities),

        // Places
        ActivityItem(id: "restaurant", emoji: "🍽️", label: "Go out to eat?", category: .places),
        ActivityItem(id: "cafe", emoji: "☕", label: "Hit a café?", category: .places),
        ActivityItem(id: "park", emoji: "🌳", label: "Go to the park?", category: .places),
        ActivityItem(id: "beach", emoji: "🏖️", label: "Go to the beach?", category: .places),
        ActivityItem(id: "store", emoji: "🛒", label: "Go shopping?", category: .places),

        // General
        ActivityItem(id: "drinks", emoji: "🍻", label: "Drinks?", category: .general),
        ActivityItem(id: "coffee", emoji: "☕", label: "Coffee?", category: .general),
        ActivityItem(id: "snack", emoji: "🍿", label: "Snack?", category: .general),
        ActivityItem(id: "chat", emoji: "💬", label: "Just talk?", category: .general),
        ActivityItem(id: "nap", emoji: "😴", label: "Nap time?", category: .general),
    ]

    /// Grouped by category for sectioned list display
    static var grouped: [(category: ActivityCategory, items: [ActivityItem])] {
        ActivityCategory.allCases.map { category in
            (category: category, items: items.filter { $0.category == category })
        }
    }
}
