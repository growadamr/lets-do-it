import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore

@MainActor
class ActivityManager: ObservableObject {
    static let shared = ActivityManager()

    /// Current user's custom activities (real-time)
    @Published var customActivities: [CustomActivity] = []

    /// Activity preferences — activityId → enabled (only stores overrides; missing = enabled)
    @Published var preferences: [String: Bool] = [:]

    private let db = Firestore.firestore()
    private var customActivitiesListener: ListenerRegistration?
    private var preferencesListener: ListenerRegistration?

    private init() {}

    // MARK: - Helpers

    private var currentUid: String? {
        Auth.auth().currentUser?.uid
    }

    private func requireUid() throws -> String {
        guard let uid = currentUid else {
            throw ActivityManagerError.notAuthenticated
        }
        return uid
    }

    // MARK: - Preferences

    /// Start real-time listener on current user's activity preferences.
    func startListeningPreferences() {
        guard let uid = currentUid else { return }

        preferencesListener?.remove()

        let ref = db.collection("users")
            .document(uid)
            .collection("activityPreferences")

        preferencesListener = ref.addSnapshotListener { [weak self] snapshot, error in
            guard let self, let documents = snapshot?.documents else {
                if let error { print("[ActivityManager] Preferences listener error: \(error)") }
                return
            }

            var prefs: [String: Bool] = [:]
            for doc in documents {
                let data = doc.data()
                let enabled = data["enabled"] as? Bool ?? true
                prefs[doc.documentID] = enabled
            }
            self.preferences = prefs
        }
    }

    func stopListeningPreferences() {
        preferencesListener?.remove()
        preferencesListener = nil
        preferences = [:]
    }

    /// One-time fetch of all preferences (useful before the listener kicks in).
    func loadPreferences() async throws {
        let uid = try requireUid()

        let snapshot = try await db.collection("users")
            .document(uid)
            .collection("activityPreferences")
            .getDocuments()

        var prefs: [String: Bool] = [:]
        for doc in snapshot.documents {
            let data = doc.data()
            let enabled = data["enabled"] as? Bool ?? true
            prefs[doc.documentID] = enabled
        }
        self.preferences = prefs
    }

    /// Toggle an activity preference on/off. Creates the doc if it doesn't exist.
    func togglePreference(activityId: String) async throws {
        let uid = try requireUid()
        let currentlyEnabled = isEnabled(activityId)
        let newEnabled = !currentlyEnabled

        let ref = db.collection("users")
            .document(uid)
            .collection("activityPreferences")
            .document(activityId)

        try await ref.setData(["enabled": newEnabled], merge: true)
    }

    /// Check if an activity is enabled for the current user.
    /// Missing preference defaults to `true` (catalog items are enabled by default).
    func isEnabled(_ activityId: String) -> Bool {
        preferences[activityId] ?? true
    }

    // MARK: - Custom Activities

    /// Start real-time listener on current user's custom activities.
    func startListeningCustomActivities() {
        guard let uid = currentUid else { return }

        customActivitiesListener?.remove()

        let ref = db.collection("users")
            .document(uid)
            .collection("customActivities")
            .order(by: "createdAt", descending: false)

        customActivitiesListener = ref.addSnapshotListener { [weak self] snapshot, error in
            guard let self, let documents = snapshot?.documents else {
                if let error { print("[ActivityManager] Custom activities listener error: \(error)") }
                return
            }

            var activities: [CustomActivity] = []
            for doc in documents {
                let data = doc.data()
                guard let emoji = data["emoji"] as? String,
                      let label = data["label"] as? String,
                      let categoryRaw = data["category"] as? String,
                      let category = ActivityCategory(rawValue: categoryRaw) else {
                    continue
                }

                let createdAt = (data["createdAt"] as? Timestamp)?.dateValue()
                let visibleTo = data["visibleTo"] as? [String] ?? []

                let activity = CustomActivity(
                    id: doc.documentID,
                    emoji: emoji,
                    label: label,
                    category: category,
                    createdAt: createdAt,
                    visibleTo: visibleTo
                )
                activities.append(activity)
            }
            self.customActivities = activities
        }
    }

    func stopListeningCustomActivities() {
        customActivitiesListener?.remove()
        customActivitiesListener = nil
        customActivities = []
    }

    /// Create a new custom activity and store it in Firestore.
    func createCustomActivity(emoji: String, label: String, category: ActivityCategory, visibleTo: [String]) async throws -> CustomActivity {
        let uid = try requireUid()

        let id = "custom_\(UUID().uuidString)"
        let now = Date()

        let activity = CustomActivity(
            id: id,
            emoji: emoji,
            label: label,
            category: category,
            createdAt: now,
            visibleTo: visibleTo
        )

        let ref = db.collection("users")
            .document(uid)
            .collection("customActivities")
            .document(id)

        try await ref.setData([
            "emoji": emoji,
            "label": label,
            "category": category.rawValue,
            "createdAt": Timestamp(date: now),
            "visibleTo": visibleTo
        ])

        return activity
    }

    /// Update an existing custom activity in Firestore.
    func updateCustomActivity(_ activity: CustomActivity) async throws {
        let uid = try requireUid()

        let ref = db.collection("users")
            .document(uid)
            .collection("customActivities")
            .document(activity.id)

        var data: [String: Any] = [
            "emoji": activity.emoji,
            "label": activity.label,
            "category": activity.category.rawValue,
            "visibleTo": activity.visibleTo
        ]

        if let createdAt = activity.createdAt {
            data["createdAt"] = Timestamp(date: createdAt)
        }

        try await ref.setData(data, merge: true)
    }

    /// Delete a custom activity from Firestore.
    func deleteCustomActivity(id: String) async throws {
        let uid = try requireUid()

        let ref = db.collection("users")
            .document(uid)
            .collection("customActivities")
            .document(id)

        try await ref.delete()
    }

    /// One-time fetch of another user's custom activities where the current user is in `visibleTo`.
    func fetchVisibleCustomActivities(for uid: String) async throws -> [CustomActivity] {
        guard let currentUid = currentUid else {
            throw ActivityManagerError.notAuthenticated
        }

        let snapshot = try await db.collection("users")
            .document(uid)
            .collection("customActivities")
            .whereField("visibleTo", arrayContains: currentUid)
            .getDocuments()

        var activities: [CustomActivity] = []
        for doc in snapshot.documents {
            let data = doc.data()
            guard let emoji = data["emoji"] as? String,
                  let label = data["label"] as? String,
                  let categoryRaw = data["category"] as? String,
                  let category = ActivityCategory(rawValue: categoryRaw) else {
                continue
            }

            let createdAt = (data["createdAt"] as? Timestamp)?.dateValue()
            let visibleTo = data["visibleTo"] as? [String] ?? []

            let activity = CustomActivity(
                id: doc.documentID,
                emoji: emoji,
                label: label,
                category: category,
                createdAt: createdAt,
                visibleTo: visibleTo
            )
            activities.append(activity)
        }
        return activities
    }

    // MARK: - Activity Resolution (for Match History, Notifications)

    /// Resolve an activity ID (catalog or custom) to its display details.
    ///
    /// Lookup order:
    /// 1. Catalog items (static lookup)
    /// 2. Current user's customActivities collection
    /// 3. Contact's customActivities collection (they created it)
    /// 4. Fallback: ("🎯", itemId)
    func resolveActivityDetails(itemId: String, contactUid: String) async -> (emoji: String, label: String) {
        // 1. Catalog lookup
        if let catalogItem = ActivityCatalog.items.first(where: { $0.id == itemId }) {
            return (catalogItem.emoji, catalogItem.label)
        }

        // 2. Custom activity lookup
        guard itemId.hasPrefix("custom_") else {
            return ("🎯", itemId)
        }

        // Try current user's collection first
        if let uid = currentUid {
            if let activity = try? await fetchCustomActivity(uid: uid, activityId: itemId) {
                return (activity.emoji, activity.label)
            }
        }

        // Try contact's collection
        if let activity = try? await fetchCustomActivity(uid: contactUid, activityId: itemId) {
            return (activity.emoji, activity.label)
        }

        // Fallback
        return ("🎯", itemId)
    }

    /// Fetch a single custom activity document by ID from a specific user's collection.
    private func fetchCustomActivity(uid: String, activityId: String) async throws -> CustomActivity? {
        let doc = try await db.collection("users")
            .document(uid)
            .collection("customActivities")
            .document(activityId)
            .getDocument()

        guard let data = doc.data() else { return nil }

        guard let emoji = data["emoji"] as? String,
              let label = data["label"] as? String,
              let categoryRaw = data["category"] as? String,
              let category = ActivityCategory(rawValue: categoryRaw) else {
            return nil
        }

        let createdAt = (data["createdAt"] as? Timestamp)?.dateValue()
        let visibleTo = data["visibleTo"] as? [String] ?? []

        return CustomActivity(
            id: activityId,
            emoji: emoji,
            label: label,
            category: category,
            createdAt: createdAt,
            visibleTo: visibleTo
        )
    }

    // MARK: - Effective Activity List

    /// Compute the effective activity list for a given contact.
    ///
    /// Returns the union of:
    /// 1. Catalog items enabled by both users
    /// 2. Custom activities mutually visible to both users
    ///
    /// Results are sorted by category order then label.
    func getEffectiveActivities(for contactUid: String) async throws -> [any ActivityDisplayable] {
        let uid = try requireUid()

        // 1. My enabled catalog items (all catalog items where I haven't disabled them)
        let myEnabledCatalog = ActivityCatalog.items.filter { isEnabled($0.id) }

        // 2. My custom activities visible to this contact
        let myVisibleCustoms = customActivities.filter { $0.visibleTo.contains(contactUid) }

        // 3. Contact's enabled catalog items (fetch their prefs)
        let contactPrefsSnapshot = try await db.collection("users")
            .document(contactUid)
            .collection("activityPreferences")
            .getDocuments()

        var contactDisabled = Set<String>()
        for doc in contactPrefsSnapshot.documents {
            if let enabled = doc.data()["enabled"] as? Bool, !enabled {
                contactDisabled.insert(doc.documentID)
            }
        }
        let contactEnabledCatalog = ActivityCatalog.items.filter { !contactDisabled.contains($0.id) }

        // 4. Contact's custom activities visible to me
        let contactVisibleCustoms = try await fetchVisibleCustomActivities(for: contactUid)

        // 5. Intersection: mutually enabled catalog items
        let myEnabledIds = Set(myEnabledCatalog.map { $0.id })
        let contactEnabledIds = Set(contactEnabledCatalog.map { $0.id })
        let mutualCatalogIds = myEnabledIds.intersection(contactEnabledIds)

        let mutualCatalog = myEnabledCatalog.filter { mutualCatalogIds.contains($0.id) }

        // 6. Custom activities: union of mine visible to them + theirs visible to me.
        //    Unlike catalog items (which require mutual enablement), a custom activity
        //    only needs to be created by one user with the other in visibleTo.
        //    Deduplicate by ID in case both users independently created the same activity.
        var seenCustomIds = Set<String>()
        var mutualCustoms: [any ActivityDisplayable] = []
        for activity in myVisibleCustoms + contactVisibleCustoms {
            if !seenCustomIds.contains(activity.id) {
                seenCustomIds.insert(activity.id)
                mutualCustoms.append(activity)
            }
        }

        // 7. Combine and sort by category order then label
        let allItems: [any ActivityDisplayable] = mutualCatalog + mutualCustoms

        let categoryOrder = Dictionary(uniqueKeysWithValues: ActivityCategory.allCases.enumerated().map { ($1, $0) })

        return allItems.sorted { a, b in
            let aOrder = categoryOrder[a.category, default: Int.max]
            let bOrder = categoryOrder[b.category, default: Int.max]
            if aOrder != bOrder { return aOrder < bOrder }
            return a.label < b.label
        }
    }
}

// MARK: - Error Types

enum ActivityManagerError: LocalizedError {
    case notAuthenticated
    case activityNotFound
    case invalidEmoji
    case labelTooLong

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "You must be signed in."
        case .activityNotFound:
            return "Activity not found."
        case .invalidEmoji:
            return "Please enter a valid emoji."
        case .labelTooLong:
            return "Label must be 50 characters or fewer."
        }
    }
}
