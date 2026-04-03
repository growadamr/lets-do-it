import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore

@MainActor
class ContactManager: ObservableObject {
    static let shared = ContactManager()

    /// All contacts for the current user
    @Published var contacts: [Contact] = []

    /// The currently selected contact for activity matching
    @Published var selectedContact: Contact?

    /// Set when a new contact appears without a name — triggers the name-entry sheet
    @Published var pendingContactForNaming: Contact?

    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?
    private var lastContactUids: Set<String> = []

    private init() {}

    // MARK: - Models

    struct Contact: Identifiable, Equatable, Hashable {
        let id: String          // contact document ID (same as contact UID)
        let uid: String         // Firebase Auth UID of the contact
        var displayName: String
        var fcmToken: String
        let addedAt: Date

        static func == (lhs: Contact, rhs: Contact) -> Bool {
            lhs.id == rhs.id && lhs.displayName == rhs.displayName
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }
    }

    // MARK: - Add Contact via Invite Code

    /// Generates a reusable invite code for adding contacts.
    /// Unlike the old pairing system, codes expire in 24 hours and can be used multiple times.
    func generateInviteCode() async throws -> String {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw ContactError.notAuthenticated
        }

        // Delete any existing active codes from this user
        let existing = try await db.collection("inviteCodes")
            .whereField("createdBy", isEqualTo: userId)
            .whereField("used", isEqualTo: false)
            .getDocuments()

        for doc in existing.documents {
            try await doc.reference.delete()
        }

        // Generate a random 6-digit code
        let code = String(format: "%06d", Int.random(in: 0...999999))
        let expiresAt = Date().addingTimeInterval(24 * 60 * 60) // 24 hours

        try await db.collection("inviteCodes").document(code).setData([
            "createdBy": userId,
            "createdAt": FieldValue.serverTimestamp(),
            "expiresAt": Timestamp(date: expiresAt),
            "used": false  // kept for backwards compatibility; codes are now reusable
        ])

        return code
    }

    /// Join with an invite code to add the code creator as a contact.
    /// This is idempotent — if already contacts, does nothing.
    func joinWithCode(_ code: String) async throws {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            throw ContactError.notAuthenticated
        }

        let codeRef = db.collection("inviteCodes").document(code)
        let codeDoc = try await codeRef.getDocument()

        guard let data = codeDoc.data(),
              let createdBy = data["createdBy"] as? String,
              let expiresAt = data["expiresAt"] as? Timestamp else {
            throw ContactError.invalidCode
        }

        guard expiresAt.dateValue() > Date() else { throw ContactError.codeExpired }
        guard createdBy != currentUserId else { throw ContactError.cannotAddSelf }

        // Add the code creator as a contact (idempotent)
        try await addContact(contactUid: createdBy)
    }

    // MARK: - Contact Management

    /// Add a user as a contact (bidirectional).
    /// Creates the contact with an empty display name — both users set their own name.
    func addContact(contactUid: String) async throws {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            throw ContactError.notAuthenticated
        }

        let contactRef = db.collection("users")
            .document(currentUserId)
            .collection("contacts")
            .document(contactUid)

        let doc = try? await contactRef.getDocument()
        if doc?.exists == true {
            return  // Already a contact
        }

        try await contactRef.setData([
            "uid": contactUid,
            "displayName": "",
            "addedAt": FieldValue.serverTimestamp()
        ])

        // Refresh contacts list
        await refreshContacts()
    }

    /// Remove a contact.
    func removeContact(contactUid: String) async throws {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            throw ContactError.notAuthenticated
        }

        let contactRef = db.collection("users")
            .document(currentUserId)
            .collection("contacts")
            .document(contactUid)

        try await contactRef.delete()

        if selectedContact?.uid == contactUid {
            selectedContact = nil
        }

        await refreshContacts()
    }

    // MARK: - Listen for Contacts

    /// Start real-time listening for the current user's contacts.
    func startListening() {
        guard let userId = Auth.auth().currentUser?.uid else { return }

        listener?.remove()

        let contactsRef = db.collection("users")
            .document(userId)
            .collection("contacts")
            .order(by: "addedAt", descending: false)

        listener = contactsRef.addSnapshotListener { [weak self] snapshot, error in
            guard let self, let documents = snapshot?.documents else { return }

            var contacts: [Contact] = []
            for doc in documents {
                let data = doc.data()
                guard let uid = data["uid"] as? String else {
                    continue
                }

                let displayName = data["displayName"] as? String ?? ""
                let fcmToken = data["fcmToken"] as? String ?? ""
                let addedAt = (data["addedAt"] as? Timestamp)?.dateValue() ?? Date()

                let contact = Contact(
                    id: doc.documentID,
                    uid: uid,
                    displayName: displayName,
                    fcmToken: fcmToken,
                    addedAt: addedAt
                )
                contacts.append(contact)

                // Detect a new contact with no name — trigger name entry
                if !self.lastContactUids.contains(uid) && displayName.isEmpty {
                    self.pendingContactForNaming = contact
                }
            }

            self.lastContactUids = Set(contacts.map { $0.uid })
            self.contacts = contacts
        }
    }

    /// Manually refresh contacts (useful after adding via code).
    func refreshContacts() async {
        guard let userId = Auth.auth().currentUser?.uid else { return }

        do {
            let snapshot = try await db.collection("users")
                .document(userId)
                .collection("contacts")
                .order(by: "addedAt", descending: false)
                .getDocuments()

            var contacts: [Contact] = []
            for doc in snapshot.documents {
                let data = doc.data()
                guard let uid = data["uid"] as? String else {
                    continue
                }

                let displayName = data["displayName"] as? String ?? ""
                let fcmToken = data["fcmToken"] as? String ?? ""
                let addedAt = (data["addedAt"] as? Timestamp)?.dateValue() ?? Date()

                let contact = Contact(
                    id: doc.documentID,
                    uid: uid,
                    displayName: displayName,
                    fcmToken: fcmToken,
                    addedAt: addedAt
                )
                contacts.append(contact)

                // Detect a new contact with no name — trigger name entry
                if !self.lastContactUids.contains(uid) && displayName.isEmpty {
                    self.pendingContactForNaming = contact
                }
            }

            self.lastContactUids = Set(contacts.map { $0.uid })
            self.contacts = contacts
        } catch {
            print("Failed to refresh contacts: \(error)")
        }
    }

    // MARK: - Contact Naming

    /// Save a display name for a contact.
    func saveContactName(contactUid: String, name: String) async {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }

        do {
            let contactRef = db.collection("users")
                .document(currentUserId)
                .collection("contacts")
                .document(contactUid)

            try await contactRef.updateData(["displayName": name])
        } catch {
            print("Failed to save contact name: \(error)")
        }

        pendingContactForNaming = nil
        await refreshContacts()
    }

    func stopListening() {
        listener?.remove()
        contacts = []
        lastContactUids = []
    }

    // MARK: - Selections for a Specific Contact

    /// Toggle an activity selection for the currently selected contact.
    func toggleSelection(itemId: String) async throws {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        guard let contact = selectedContact else { return }

        let selectionsRef = db.collection("users")
            .document(userId)
            .collection("selections")

        // Query only by matched=false, filter in code to avoid composite index
        let snapshot = try await selectionsRef
            .whereField("matched", isEqualTo: false)
            .getDocuments()

        let matchingDocs = snapshot.documents.filter {
            let data = $0.data()
            return (data["userId"] as? String) == userId &&
                   (data["targetUserId"] as? String) == contact.uid &&
                   (data["itemId"] as? String) == itemId
        }

        if !matchingDocs.isEmpty {
            // Deselect: delete the selection
            for doc in matchingDocs {
                try await doc.reference.delete()
            }
        } else {
            // Select: create a new selection with 60-min expiry
            let now = Date()
            let expiresAt = now.addingTimeInterval(60 * 60) // 60 minutes

            try await selectionsRef.addDocument(data: [
                "userId": userId,
                "targetUserId": contact.uid,
                "itemId": itemId,
                "createdAt": Timestamp(date: now),
                "expiresAt": Timestamp(date: expiresAt),
                "matched": false
            ])
        }
    }

    /// Get active selections for the current user + selected contact.
    func getActiveSelections() async -> Set<String> {
        guard let userId = Auth.auth().currentUser?.uid else { return [] }
        guard let contact = selectedContact else { return [] }

        let selectionsRef = db.collection("users")
            .document(userId)
            .collection("selections")

        // Query only by matched=false, filter in code
        let snapshot = try? await selectionsRef
            .whereField("matched", isEqualTo: false)
            .getDocuments()
        guard let documents = snapshot?.documents else { return [] }

        let now = Date()
        var active = Set<String>()

        for doc in documents {
            let data = doc.data()
            guard (data["userId"] as? String) == userId,
                  (data["targetUserId"] as? String) == contact.uid,
                  let itemId = data["itemId"] as? String,
                  let expiresAt = data["expiresAt"] as? Timestamp else {
                continue
            }

            if expiresAt.dateValue() > now {
                active.insert(itemId)
            }
        }

        return active
    }
}

// MARK: - Error Types

enum ContactError: LocalizedError {
    case notAuthenticated
    case invalidCode
    case codeExpired
    case cannotAddSelf
    case userNotFound

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "You must be signed in."
        case .invalidCode: return "That code doesn't exist."
        case .codeExpired: return "That code has expired."
        case .cannotAddSelf: return "You can't add yourself."
        case .userNotFound: return "That user doesn't exist."
        }
    }
}
