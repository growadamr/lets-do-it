import Foundation

// MARK: - RSVPStatus

enum RSVPStatus: String, Codable, CaseIterable {
    case accepted
    case declined
    case maybe

    var displayLabel: String {
        switch self {
        case .accepted: return "Accepted"
        case .declined: return "Declined"
        case .maybe: return "Maybe"
        }
    }

    var colorName: String {
        switch self {
        case .accepted: return "green"
        case .declined: return "red"
        case .maybe: return "yellow"
        }
    }
}

// MARK: - EventStatus

enum EventStatus: String, Codable, CaseIterable {
    case active
    case cancelled
}

// MARK: - Event

struct Event: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let description: String?
    let location: String?
    let dateTime: Date
    let createdBy: String
    let createdAt: Date?
    let updatedAt: Date?
    let invitees: [String]
    let rsvps: [String: RSVPStatus]
    let conversationId: String?
    let status: EventStatus

    init(
        id: String = UUID().uuidString,
        title: String,
        description: String? = nil,
        location: String? = nil,
        dateTime: Date,
        createdBy: String,
        createdAt: Date? = nil,
        updatedAt: Date? = nil,
        invitees: [String] = [],
        rsvps: [String: RSVPStatus] = [:],
        conversationId: String? = nil,
        status: EventStatus = .active
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.location = location
        self.dateTime = dateTime
        self.createdBy = createdBy
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.invitees = invitees
        self.rsvps = rsvps
        self.conversationId = conversationId
        self.status = status
    }

    // MARK: - Hashable

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: Event, rhs: Event) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - CodingKeys

extension Event {
    enum CodingKeys: String, CodingKey {
        case id
        case title
        case description
        case location
        case dateTime
        case createdBy
        case createdAt
        case updatedAt
        case invitees
        case rsvps
        case conversationId
        case status
    }
}
