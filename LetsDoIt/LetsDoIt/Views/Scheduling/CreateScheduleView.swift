import SwiftUI

// MARK: - Create Schedule View

/// Form for creating a new scheduled activity.
/// Includes: single-contact picker, activity picker (effective list for the selected contact),
/// date/time picker, recurrence picker, and validation.
struct CreateScheduleView: View {
    /// Optional pre-selected contact UID (when navigated from a specific contact's view).
    var preselectedContactUid: String?
    /// Optional pre-selected activity ID (when navigated from "Schedule This Activity").
    var preselectedActivityId: String?

    var onCreate: ((ScheduledActivity) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @StateObject private var scheduleManager = ScheduleManager.shared
    @StateObject private var contactManager = ContactManager.shared
    @StateObject private var activityManager = ActivityManager.shared

    @State private var selectedContactUid: String?
    @State private var selectedActivityId: String?
    @State private var scheduledAt = Date().addingTimeInterval(3600) // default: 1 hour from now
    @State private var recurrence: RecurrenceRule?

    @State private var effectiveActivities: [any ActivityDisplayable] = []
    @State private var showingContactPicker = false
    @State private var showingRecurrencePicker = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Contact") {
                    Button {
                        showingContactPicker = true
                    } label: {
                        HStack {
                            Text(contactSummary)
                                .foregroundColor(selectedContactUid == nil ? .red : .primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                if selectedContactUid != nil {
                    Section("Activity") {
                        Picker("Activity", selection: $selectedActivityId) {
                            Text("Select an activity").tag(String?.none)

                            ForEach(effectiveActivities.indices, id: \.self) { index in
                                let activity = effectiveActivities[index]
                                HStack {
                                    Text(activity.emoji)
                                    Text(activity.label)
                                }
                                .tag(Optional(activity.id))
                            }
                        }

                        if selectedActivityId == nil {
                            Text("Select an activity to schedule.")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                }

                if selectedContactUid != nil && selectedActivityId != nil {
                    Section("Date & Time") {
                        DatePicker(
                            "Scheduled For",
                            selection: $scheduledAt,
                            in: Date()...,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                    }

                    Section("Recurrence") {
                        Button {
                            showingRecurrencePicker = true
                        } label: {
                            HStack {
                                Text(recurrenceSummary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("New Schedule")
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
                SingleContactPickerView(selectedUid: $selectedContactUid)
            }
            .sheet(isPresented: $showingRecurrencePicker) {
                RecurrencePickerView(recurrence: $recurrence)
            }
            .onChange(of: selectedContactUid) { oldValue, newValue in
                if let newUid = newValue {
                    Task {
                        await loadEffectiveActivities(for: newUid)
                    }
                    // If pre-selected activity isn't in the effective list, clear it
                    if let preId = preselectedActivityId,
                       !effectiveActivities.contains(where: { $0.id == preId }) {
                        selectedActivityId = nil
                    } else if let preId = preselectedActivityId {
                        selectedActivityId = preId
                    }
                } else {
                    effectiveActivities = []
                    selectedActivityId = nil
                }
            }
            .task {
                // Apply pre-selected values on load
                if let preUid = preselectedContactUid {
                    selectedContactUid = preUid
                }
            }
        }
    }

    // MARK: - Validation

    private var isValid: Bool {
        selectedContactUid != nil &&
        selectedActivityId != nil &&
        scheduledAt > Date()
    }

    // MARK: - Helpers

    private var contactSummary: String {
        if let uid = selectedContactUid,
           let contact = contactManager.contacts.first(where: { $0.uid == uid }) {
            return contact.displayName.isEmpty ? "Unnamed Contact" : contact.displayName
        }
        return "Select a contact"
    }

    private var recurrenceSummary: String {
        if let recurrence {
            return recurrence.displaySummary
        }
        return "One-time"
    }

    private func loadEffectiveActivities(for contactUid: String) async {
        do {
            let activities = try await activityManager.getEffectiveActivities(for: contactUid)
            await MainActor.run {
                self.effectiveActivities = activities

                // Restore pre-selected activity if valid
                if let preId = preselectedActivityId,
                   activities.contains(where: { $0.id == preId }) {
                    self.selectedActivityId = preId
                }
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to load activities: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Save

    private func save() {
        guard isValid,
              let contactUid = selectedContactUid,
              let activityId = selectedActivityId else {
            return
        }

        isSaving = true
        errorMessage = nil

        Task {
            do {
                let schedule = try await scheduleManager.createSchedule(
                    activityId: activityId,
                    targetContactUid: contactUid,
                    scheduledAt: scheduledAt,
                    recurrence: recurrence
                )
                await MainActor.run {
                    isSaving = false
                    onCreate?(schedule)
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

// MARK: - Preview

#Preview {
    CreateScheduleView()
}
