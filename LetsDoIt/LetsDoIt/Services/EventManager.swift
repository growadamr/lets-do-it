import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore

@MainActor
class EventManager: ObservableObject {
    static let shared = EventManager()

    /// Upcoming events (dateTime >= now), sorted by dateTime ascending (soonest first)
    @Published var events: [Event] = []

    /// Past events (dateTime < now), sorted by dateTime descending (most recent first)
    @Published var pastEvents: [Event] = []

    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?

    private init() {}

    // MARK: - Current User Helper

    private var currentUid: String? {
        Auth.auth().currentUser?.uid
    }

    private func requireUid() throws -> String {
        guard let uid = currentUid else {
            throw EventManagerError.notAuthenticated
        }
        return uid
    }

    // MARK: - Events CRUD

    /// Create a new event with optional group conversation.
    ///
    /// - Parameters:
    ///   - title: Event title (required, 1-100 chars)
    ///   - description: Optional event description
    ///   - location: Optional location string
    ///   - dateTime: When the event occurs
    ///   - invitees: Array of UIDs to invite (must include creator for read access)
    ///   - createConversation: If true, creates a group chat linked to this event
    /// - Returns: The created Event (createdAt/updatedAt will be nil until listener populates them)
    func createEvent(
        title: String,
        description: String?,
        location: String?,
        dateTime: Date,
        invitees: [String],
        createConversation: Bool
    ) async throws -> Event {
        let uid = try requireUid()

        // Ensure creator is in invitees list
        var allInvitees = invitees
        if !allInvitees.contains(uid) {
            allInvitees.append(uid)
        }

        // Optionally create a linked group conversation
        var conversationId: String?
        if createConversation && !invitees.isEmpty {
            let group = try await MessagingManager.shared.createGroup(name: title, participantUids: invitees)
            conversationId = group.id
        }

        let ref = db.collection("events").document()
        let eventId = ref.documentID

        let data: [String: Any] = [
            "title": title,
            "description": description ?? NSNull(),
            "location": location ?? NSNull(),
            "dateTime": Timestamp(date: dateTime),
            "createdBy": uid,
            "createdAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp(),
            "invitees": allInvitees,
            "rsvps": [uid: RSVPStatus.accepted.rawValue], // Creator auto-accepts
            "conversationId": conversationId ?? NSNull(),
            "status": EventStatus.active.rawValue
        ]

        try await ref.setData(data)

        return Event(
            id: eventId,
            title: title,
            description: description,
            location: location,
            dateTime: dateTime,
            createdBy: uid,
            createdAt: nil,
            updatedAt: nil,
            invitees: allInvitees,
            rsvps: [uid: .accepted],
            conversationId: conversationId,
            status: .active
        )
    }

    /// Update an event's mutable fields. Only the creator can call this.
    func updateEvent(_ event: Event) async throws {
        let uid = try requireUid()
        guard event.createdBy == uid else {
            throw EventManagerError.notCreator
        }

        let data: [String: Any] = [
            "title": event.title,
            "description": event.description ?? NSNull(),
            "location": event.location ?? NSNull(),
            "dateTime": Timestamp(date: event.dateTime),
            "invitees": event.invitees,
            "conversationId": event.conversationId ?? NSNull(),
            "status": event.status.rawValue,
            "updatedAt": FieldValue.serverTimestamp()
        ]

        try await db.collection("events").document(event.id).updateData(data)
    }

    /// Cancel an event by setting status to .cancelled.
    func cancelEvent(id: String) async throws {
        let uid = try requireUid()

        let doc = try await db.collection("events").document(id).getDocument()
        guard doc.exists else { throw EventManagerError.eventNotFound }
        guard let data = doc.data(), data["createdBy"] as? String == uid else {
            throw EventManagerError.notCreator
        }

        try await db.collection("events").document(id).updateData([
            "status": EventStatus.cancelled.rawValue,
            "updatedAt": FieldValue.serverTimestamp()
        ])
    }

    /// Delete an event document entirely. Only the creator can call this.
    func deleteEvent(id: String) async throws {
        let uid = try requireUid()

        let doc = try await db.collection("events").document(id).getDocument()
        guard doc.exists else { throw EventManagerError.eventNotFound }
        guard let data = doc.data(), data["createdBy"] as? String == uid else {
            throw EventManagerError.notCreator
        }

        try await db.collection("events").document(id).delete()
    }

    // MARK: - RSVP

    /// Submit an RSVP for the current user on an event.
    /// Invitees can update only the rsvps field (enforced by Firestore rules).
    func rsvp(eventId: String, status: RSVPStatus) async throws {
        let uid = try requireUid()

        let doc = try await db.collection("events").document(eventId).getDocument()
        guard doc.exists else { throw EventManagerError.eventNotFound }
        guard let data = doc.data(),
              let invitees = data["invitees"] as? [String],
              invitees.contains(uid) else {
            throw EventManagerError.notInvitee
        }

        try await db.collection("events").document(eventId)
            .updateData(["rsvps.\(uid)": status.rawValue])
    }

    // MARK: - Real-Time Listener

    /// Start listening to events where the current user is an invitee.
    /// Splits into upcoming (events) and past (pastEvents).
    func startListening() {
        guard let uid = currentUid else { return }

        listener?.remove()

        let query = db.collection("events")
            .whereField("invitees", arrayContains: uid)

        listener = query.addSnapshotListener { [weak self] snapshot, error in
            guard let self, let documents = snapshot?.documents else {
                if let error {
                    print("[EventManager] Event listener error: \(error)")
                }
                return
            }

            var upcoming: [Event] = []
            var past: [Event] = []
            let now = Date()

            for doc in documents {
                let data = doc.data()
                do {
                    let event = try self.decodeEvent(doc: doc, data: data)
                    if event.dateTime >= now {
                        upcoming.append(event)
                    } else {
                        past.append(event)
                    }
                } catch {
                    print("[EventManager] Failed to decode event '\(doc.documentID)': \(error)")
                }
            }

            // Upcoming: soonest first (ascending)
            upcoming.sort { $0.dateTime < $1.dateTime }
            // Past: most recent first (descending)
            past.sort { $0.dateTime > $1.dateTime }

            self.events = upcoming
            self.pastEvents = past
        }
    }

    /// Stop listening and clear all cached events.
    func stopListening() {
        listener?.remove()
        listener = nil
        events = []
        pastEvents = []
    }

    // MARK: - Helpers

    /// Check if the current user is the creator of the given event.
    func isCreator(_ event: Event) -> Bool {
        guard let uid = currentUid else { return false }
        return event.createdBy == uid
    }

    /// Resolve a display name for a UID within the context of an event.
    /// 1. Check ContactManager for a user-set contact name
    /// 2. Fall back to "Unknown"
    func inviteeName(for uid: String, in event: Event) -> String {
        if let contact = ContactManager.shared.contacts.first(where: { $0.uid == uid }),
           !contact.displayName.isEmpty {
            return contact.displayName
        }
        return "Unknown"
    }

    // MARK: - Decoding

    private func decodeEvent(doc: QueryDocumentSnapshot, data: [String: Any]) throws -> Event {
        let title = data["title"] as? String ?? "Untitled"
        let description = data["description"] as? String
        let location = data["location"] as? String
        let dateTime = (data["dateTime"] as? Timestamp)?.dateValue() ?? Date()
        let createdBy = data["createdBy"] as? String ?? ""
        let createdAt = (data["createdAt"] as? Timestamp)?.dateValue()
        let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue()
        let invitees = data["invitees"] as? [String] ?? []
        let conversationId = data["conversationId"] as? String

        let status = (data["status"] as? String).flatMap { EventStatus(rawValue: $0) } ?? .active

        // Decode rsvps map
        var rsvps: [String: RSVPStatus] = [:]
        if let rsvpsRaw = data["rsvps"] as? [String: String] {
            for (uid, rawValue) in rsvpsRaw {
                rsvps[uid] = RSVPStatus(rawValue: rawValue) ?? .declined
            }
        }

        return Event(
            id: doc.documentID,
            title: title,
            description: description,
            location: location,
            dateTime: dateTime,
            createdBy: createdBy,
            createdAt: createdAt,
            updatedAt: updatedAt,
            invitees: invitees,
            rsvps: rsvps,
            conversationId: conversationId,
            status: status
        )
    }
}

// MARK: - Error Types

enum EventManagerError: LocalizedError {
    case notAuthenticated
    case eventNotFound
    case notCreator
    case notInvitee
    case invalidEventData

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "You must be signed in."
        case .eventNotFound:
            return "Event not found."
        case .notCreator:
            return "Only the event creator can modify it."
        case .notInvitee:
            return "You are not invited to this event."
        case .invalidEventData:
            return "The event data is invalid."
        }
    }
}
