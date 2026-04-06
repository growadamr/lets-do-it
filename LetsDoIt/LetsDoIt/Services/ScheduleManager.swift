import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore

@MainActor
class ScheduleManager: ObservableObject {
    static let shared = ScheduleManager()

    /// All schedules for the current user, sorted by scheduledAt ascending
    @Published var schedules: [ScheduledActivity] = []

    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?

    private init() {}

    // MARK: - Current User Helper

    private var currentUid: String? {
        Auth.auth().currentUser?.uid
    }

    private func requireUid() throws -> String {
        guard let uid = currentUid else {
            throw ScheduleManagerError.notAuthenticated
        }
        return uid
    }

    // MARK: - Schedule CRUD

    /// Create a new scheduled activity.
    func createSchedule(
        activityId: String,
        targetContactUid: String,
        scheduledAt: Date,
        recurrence: RecurrenceRule?
    ) async throws -> ScheduledActivity {
        let uid = try requireUid()

        let ref = db.collection("users")
            .document(uid)
            .collection("scheduledActivities")
            .document()

        let scheduleId = ref.documentID
        let now = Date()

        var data: [String: Any] = [
            "activityId": activityId,
            "targetContactUid": targetContactUid,
            "scheduledAt": Timestamp(date: scheduledAt),
            "enabled": true,
            "createdAt": FieldValue.serverTimestamp()
        ]

        if let recurrence {
            data["recurrence"] = try Firestore.Encoder().encode(recurrence)
        }

        try await ref.setData(data)

        return ScheduledActivity(
            id: scheduleId,
            activityId: activityId,
            targetContactUid: targetContactUid,
            scheduledAt: scheduledAt,
            recurrence: recurrence,
            enabled: true,
            createdAt: now,
            lastActivatedAt: nil
        )
    }

    /// Update a scheduled activity's mutable fields.
    func updateSchedule(_ schedule: ScheduledActivity) async throws {
        let uid = try requireUid()

        var data: [String: Any] = [
            "activityId": schedule.activityId,
            "targetContactUid": schedule.targetContactUid,
            "scheduledAt": Timestamp(date: schedule.scheduledAt),
            "enabled": schedule.enabled
        ]

        if let recurrence = schedule.recurrence {
            data["recurrence"] = try Firestore.Encoder().encode(recurrence)
        } else {
            data["recurrence"] = NSNull()
        }

        try await db.collection("users")
            .document(uid)
            .collection("scheduledActivities")
            .document(schedule.id)
            .setData(data, merge: true)
    }

    /// Delete a scheduled activity.
    func deleteSchedule(id: String) async throws {
        let uid = try requireUid()

        try await db.collection("users")
            .document(uid)
            .collection("scheduledActivities")
            .document(id)
            .delete()
    }

    /// Toggle the enabled state of a scheduled activity.
    func toggleEnabled(id: String, enabled: Bool) async throws {
        let uid = try requireUid()

        try await db.collection("users")
            .document(uid)
            .collection("scheduledActivities")
            .document(id)
            .updateData(["enabled": enabled])
    }

    // MARK: - Real-Time Listener

    /// Start listening to the current user's scheduled activities.
    func startListening() {
        guard let uid = currentUid else { return }

        listener?.remove()

        let query = db.collection("users")
            .document(uid)
            .collection("scheduledActivities")
            .order(by: "scheduledAt", descending: false)

        listener = query.addSnapshotListener { [weak self] snapshot, error in
            guard let self, let documents = snapshot?.documents else {
                if let error {
                    print("[ScheduleManager] Listener error: \(error)")
                }
                return
            }

            var decoded: [ScheduledActivity] = []
            for doc in documents {
                let data = doc.data()
                if let schedule = self.decodeSchedule(doc: doc, data: data) {
                    decoded.append(schedule)
                }
            }

            self.schedules = decoded
        }
    }

    /// Stop listening and clear all cached schedules.
    func stopListening() {
        listener?.remove()
        listener = nil
        schedules = []
    }

    // MARK: - Helpers

    /// Filter schedules by target contact UID.
    func schedulesForContact(_ contactUid: String) -> [ScheduledActivity] {
        schedules.filter { $0.targetContactUid == contactUid }
    }

    /// Human-readable description of a schedule's next activation.
    func nextActivationDescription(_ schedule: ScheduledActivity) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full

        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "h:mm a"

        let date = schedule.scheduledAt

        // For recurring schedules, show recurrence pattern
        if let recurrence = schedule.recurrence {
            let timeStr = timeFormatter.string(from: date)

            switch recurrence.type {
            case .daily:
                return "Daily at \(timeStr)"
            case .weekly:
                return "Weekly at \(timeStr)"
            case .custom:
                if let days = recurrence.daysOfWeek, !days.isEmpty {
                    let dayLabels = days.sorted().map { dayIndex in
                        let calendar = Calendar.current
                        let weekdaySymbols = calendar.weekdaySymbols
                        let idx = min(dayIndex, weekdaySymbols.count - 1)
                        let full = weekdaySymbols[idx]
                        return String(full.prefix(3))
                    }
                    let daysStr = dayLabels.joined(separator: ", ")
                    return "Every \(daysStr) at \(timeStr)"
                } else {
                    return "Weekly at \(timeStr)"
                }
            }
        }

        // One-time schedule
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today at \(timeFormatter.string(from: date))"
        } else if calendar.isDateInTomorrow(date) {
            return "Tomorrow at \(timeFormatter.string(from: date))"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday at \(timeFormatter.string(from: date))"
        } else {
            let relativeDate = formatter.localizedString(for: date, relativeTo: Date())
            return "\(relativeDate.capitalized) at \(timeFormatter.string(from: date))"
        }
    }

    // MARK: - Decoding

    private func decodeSchedule(doc: QueryDocumentSnapshot, data: [String: Any]) -> ScheduledActivity? {
        guard let activityId = data["activityId"] as? String,
              let targetContactUid = data["targetContactUid"] as? String else {
            return nil
        }

        let scheduledAt = (data["scheduledAt"] as? Timestamp)?.dateValue() ?? Date()
        let enabled = data["enabled"] as? Bool ?? true
        let createdAt = (data["createdAt"] as? Timestamp)?.dateValue()
        let lastActivatedAt = (data["lastActivatedAt"] as? Timestamp)?.dateValue()

        let recurrence: RecurrenceRule?
        if let recurrenceData = data["recurrence"] as? [String: Any] {
            do {
                recurrence = try Firestore.Decoder().decode(RecurrenceRule.self, from: recurrenceData)
            } catch {
                print("[ScheduleManager] Failed to decode recurrence for \(doc.documentID): \(error)")
                recurrence = nil
            }
        } else {
            recurrence = nil
        }

        return ScheduledActivity(
            id: doc.documentID,
            activityId: activityId,
            targetContactUid: targetContactUid,
            scheduledAt: scheduledAt,
            recurrence: recurrence,
            enabled: enabled,
            createdAt: createdAt,
            lastActivatedAt: lastActivatedAt
        )
    }
}

// MARK: - Error Types

enum ScheduleManagerError: LocalizedError {
    case notAuthenticated
    case scheduleNotFound
    case invalidRecurrence

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "You must be signed in."
        case .scheduleNotFound:
            return "Schedule not found."
        case .invalidRecurrence:
            return "The recurrence rule is invalid."
        }
    }
}
