import SwiftUI

/// Form for creating a new event.
/// Includes title, description, location, date/time picker, invitee picker,
/// and a toggle for creating an optional group chat.
struct CreateEventView: View {
    var onCreate: ((Event) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var eventManager = EventManager.shared

    @State private var title = ""
    @State private var description = ""
    @State private var location = ""
    @State private var dateTime = Date().addingTimeInterval(3600) // default: 1 hour from now
    @State private var selectedUids: [String] = []
    @State private var createGroupChat = true

    @State private var showingContactPicker = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isValid: Bool {
        !trimmedTitle.isEmpty
        && trimmedTitle.count <= 100
        && dateTime > Date()
        && !selectedUids.isEmpty
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
                    if trimmedTitle.isEmpty && title.isEmpty {
                        Text("Enter a title for your event.")
                            .font(.caption)
                            .foregroundColor(.secondary)
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
                            in: Date()...,
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

                Section {
                    Toggle("Create group chat", isOn: $createGroupChat)
                    if createGroupChat {
                        Text("A group conversation will be created and linked to this event.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("Group Chat")
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("New Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        save()
                    }
                    .bold()
                    .disabled(!isValid || isSaving)
                }
            }
            .sheet(isPresented: $showingContactPicker) {
                MultiContactPickerView(selectedUids: $selectedUids)
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
                let event = try await eventManager.createEvent(
                    title: trimmedTitle,
                    description: description.isEmpty ? nil : description,
                    location: location.isEmpty ? nil : location,
                    dateTime: dateTime,
                    invitees: selectedUids,
                    createConversation: createGroupChat
                )
                await MainActor.run {
                    isSaving = false
                    onCreate?(event)
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
}

#Preview {
    CreateEventView()
}
