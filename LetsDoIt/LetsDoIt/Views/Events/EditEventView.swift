import SwiftUI
import FirebaseAuth

/// Form for editing an existing event.
/// Same fields as CreateEventView, pre-filled from the event.
/// Only accessible to the event creator.
struct EditEventView: View {
    let event: Event
    var onUpdate: ((Event) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var eventManager = EventManager.shared

    @State private var title: String
    @State private var description: String
    @State private var location: String
    @State private var dateTime: Date
    @State private var selectedUids: [String]
    @State private var createGroupChat: Bool

    @State private var showingContactPicker = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showingCancelConfirmation = false

    private var currentUid: String? {
        Auth.auth().currentUser?.uid
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Editing allows past dates (you might be rescheduling to an earlier time on the same day,
    /// or the event was created with a past date by mistake). Creation enforces future-only.
    private var isValid: Bool {
        !trimmedTitle.isEmpty
        && trimmedTitle.count <= 100
        && !selectedUids.isEmpty
    }

    init(event: Event, onUpdate: ((Event) -> Void)? = nil) {
        self.event = event
        self.onUpdate = onUpdate

        let uid = Auth.auth().currentUser?.uid ?? ""
        // Pre-fill invitees excluding the creator (creator is always auto-added)
        let others = event.invitees.filter { $0 != uid }

        _title = State(initialValue: event.title)
        _description = State(initialValue: event.description ?? "")
        _location = State(initialValue: event.location ?? "")
        _dateTime = State(initialValue: event.dateTime)
        _selectedUids = State(initialValue: others)
        _createGroupChat = State(initialValue: event.conversationId != nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    // Title
                    HStack(spacing: 12) {
                        Text("Title")
                        Spacer()
                        TextField("e.g. Saturday BBQ", text: $title)
                            .multilineTextAlignment(.trailing)
                            .textFieldStyle(.plain)
                    }
                    if !title.isEmpty && trimmedTitle.count > 100 {
                        Text("Title must be 100 characters or fewer (\(trimmedTitle.count)/100)")
                            .font(.caption)
                            .foregroundColor(.red)
                    }

                    // Description
                    HStack(spacing: 12) {
                        Text("Description")
                        Spacer()
                        TextField("Optional", text: $description, axis: .vertical)
                            .multilineTextAlignment(.trailing)
                            .textFieldStyle(.plain)
                            .lineLimit(3...6)
                    }

                    // Location
                    HStack(spacing: 12) {
                        Text("Location")
                        Spacer()
                        TextField("Optional", text: $location)
                            .multilineTextAlignment(.trailing)
                            .textFieldStyle(.plain)
                    }

                    // Date & Time
                    HStack(spacing: 12) {
                        Text("Date & Time")
                        Spacer()
                        DatePicker(
                            "",
                            selection: $dateTime,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                        .labelsHidden()
                    }
                }

                Section("Invitees") {
                    Button {
                        showingContactPicker = true
                    } label: {
                        HStack {
                            Text(inviteeSummary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if selectedUids.isEmpty {
                        Text("Select at least one contact to invite.")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }

                if event.conversationId != nil {
                    Section {
                        Toggle("Group chat", isOn: $createGroupChat)
                        Text("Turning off does not delete the existing conversation.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } header: {
                        Text("Group Chat")
                    }
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundColor(.red)
                    }
                }

                // Destructive actions
                Section {
                    Button(role: .destructive) {
                        showingCancelConfirmation = true
                    } label: {
                        Label("Cancel Event", systemImage: "xmark.circle")
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                } header: {
                    Text("Danger Zone")
                }
            }
            .navigationTitle("Edit Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                    .bold()
                    .disabled(!isValid || isSaving)
                }
            }
            .sheet(isPresented: $showingContactPicker) {
                MultiContactPickerView(selectedUids: $selectedUids)
            }
            .alert("Cancel Event", isPresented: $showingCancelConfirmation) {
                Button("Cancel Event", role: .destructive) {
                    cancelEvent()
                }
                Button("Dismiss", role: .cancel) {}
            } message: {
                Text("This will mark \"\(event.title)\" as cancelled. Invitees will be notified.")
            }
        }
    }

    private var inviteeSummary: String {
        let count = selectedUids.count
        if count == 0 {
            return "No contacts selected"
        }
        return "\(count) contact\(count == 1 ? "" : "s") selected"
    }

    private func save() {
        guard isValid else { return }
        isSaving = true
        errorMessage = nil

        Task {
            do {
                let uid = currentUid ?? ""
                // Rebuild the full invitees list (others + creator)
                var allInvitees = selectedUids
                if !allInvitees.contains(uid) {
                    allInvitees.append(uid)
                }

                var updatedEvent = event
                // Build a mutable copy with updated fields.
                // Since Event is a struct with `let` properties, we construct a new instance.
                let rebuiltEvent = Event(
                    id: event.id,
                    title: trimmedTitle,
                    description: description.isEmpty ? nil : description,
                    location: location.isEmpty ? nil : location,
                    dateTime: dateTime,
                    createdBy: event.createdBy,
                    createdAt: event.createdAt,
                    updatedAt: event.updatedAt, // server will override
                    invitees: allInvitees,
                    rsvps: event.rsvps,
                    conversationId: event.conversationId, // unchanged in edit
                    status: event.status
                )

                try await eventManager.updateEvent(rebuiltEvent)
                await MainActor.run {
                    isSaving = false
                    onUpdate?(rebuiltEvent)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func cancelEvent() {
        Task {
            do {
                try await eventManager.cancelEvent(id: event.id)
                await MainActor.run {
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

#Preview {
    EditEventView(
        event: Event(
            id: "preview-1",
            title: "Saturday BBQ",
            description: "Bring your favorite dish!",
            location: "Central Park",
            dateTime: Date().addingTimeInterval(86400 * 3),
            createdBy: "creator-uid",
            invitees: ["creator-uid", "friend-1", "friend-2"],
            rsvps: ["creator-uid": .accepted, "friend-1": .accepted, "friend-2": .maybe],
            conversationId: "conv-123"
        )
    )
}
