import Foundation

// MARK: - RecurrenceType

enum RecurrenceType: String, Codable, CaseIterable {
    case daily
    case weekly
    case custom

    var displayLabel: String {
        switch self {
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        case .custom: return "Custom"
        }
    }
}

// MARK: - RecurrenceRule

struct RecurrenceRule: Codable, Hashable {
    let type: RecurrenceType
    let daysOfWeek: [Int]?

    init(type: RecurrenceType, daysOfWeek: [Int]? = nil) {
        self.type = type
        self.daysOfWeek = daysOfWeek
    }
}

// MARK: - ScheduledActivity

struct ScheduledActivity: Identifiable, Codable, Hashable {
    let id: String
    let activityId: String
    let targetContactUid: String
    let scheduledAt: Date
    let recurrence: RecurrenceRule?
    let enabled: Bool
    let createdAt: Date?
    let lastActivatedAt: Date?

    init(
        id: String = UUID().uuidString,
        activityId: String,
        targetContactUid: String,
        scheduledAt: Date,
        recurrence: RecurrenceRule? = nil,
        enabled: Bool = true,
        createdAt: Date? = nil,
        lastActivatedAt: Date? = nil
    ) {
        self.id = id
        self.activityId = activityId
        self.targetContactUid = targetContactUid
        self.scheduledAt = scheduledAt
        self.recurrence = recurrence
        self.enabled = enabled
        self.createdAt = createdAt
        self.lastActivatedAt = lastActivatedAt
    }

    // MARK: - Hashable

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: ScheduledActivity, rhs: ScheduledActivity) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - CodingKeys

extension ScheduledActivity {
    enum CodingKeys: String, CodingKey {
        case id
        case activityId
        case targetContactUid
        case scheduledAt
        case recurrence
        case enabled
        case createdAt
        case lastActivatedAt
    }
}
