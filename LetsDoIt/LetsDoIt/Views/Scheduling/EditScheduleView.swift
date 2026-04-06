import SwiftUI

// MARK: - Edit Schedule View

/// Form for editing an existing scheduled activity.
/// Same layout as CreateScheduleView, pre-filled with existing data.
/// Supports save (update) and delete.
struct EditScheduleView: View {
    let schedule: ScheduledActivity

    @Environment(\.dismiss) private var dismiss
    @StateObject private var scheduleManager = ScheduleManager.shared
    @StateObject private var contactManager = ContactManager.shared
    @StateObject private var activityManager = ActivityManager.shared

    @State private var selectedContactUid: String
    @State private var selectedActivityId: String?
    @State private var scheduledAt: Date
    @State private var recurrence: RecurrenceRule?

    @State private var effectiveActivities: [any ActivityDisplayable] = []
    @State private var showingContactPicker = false
    @State private var showingRecurrencePicker = false
    @State private var isSaving = false
    @State private var showingDeleteConfirmation = false
    @State private var errorMessage: String?

    init(schedule: ScheduledActivity) {
        self.schedule = schedule
        _selectedContactUid = State(initialValue: schedule.targetContactUid)
        _selectedActivityId = State(initialValue: schedule.activityId)
        _scheduledAt = State(initialValue: schedule.scheduledAt)
        _recurrence = State(initialValue: schedule.recurrence)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Contact") {
                    Button {
                        showingContactPicker = true
                    } label: {
                        HStack {
                            Text(contactSummary)
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                Section("Activity") {
                        Picker("Activity", selection: $selectedActivityId) {
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

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundColor(.red)
                    }
                }

                Section {
                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        Label("Delete Schedule", systemImage: "trash")
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            }
            .navigationTitle("Edit Schedule")
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
                SingleContactPickerView(selectedUid: Binding(
                    get: { selectedContactUid },
                    set: { selectedContactUid = $0 ?? selectedContactUid }
                ))
            }
            .sheet(isPresented: $showingRecurrencePicker) {
                RecurrencePickerView(recurrence: $recurrence)
            }
            .confirmationDialog(
                "Delete Schedule",
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    delete()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Are you sure you want to delete this schedule? This cannot be undone.")
            }
            .onChange(of: selectedContactUid) { oldValue, newValue in
                Task {
                    await loadEffectiveActivities(for: newValue)
                }
            }
            .task {
                // Load effective activities for the pre-selected contact
                if !effectiveActivities.isEmpty { return }
                await loadEffectiveActivities(for: selectedContactUid)
            }
        }
    }

    // MARK: - Validation

    private var isValid: Bool {
        selectedActivityId != nil &&
        scheduledAt > Date()
    }

    // MARK: - Helpers

    private var contactSummary: String {
        if let contact = contactManager.contacts.first(where: { $0.uid == selectedContactUid }) {
            return contact.displayName.isEmpty ? "Unnamed Contact" : contact.displayName
        }
        return "Unknown Contact"
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

                // Ensure the current activity is in the list (might be a custom activity no longer visible)
                if let currentId = selectedActivityId,
                   !activities.contains(where: { $0.id == currentId }) {
                    // Keep it available even if not in effective list (edge case: custom activity visibility changed)
                    // For now, just clear selection if not found — user must re-pick
                    self.selectedActivityId = nil
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
              let activityId = selectedActivityId else {
            return
        }

        isSaving = true
        errorMessage = nil

        Task {
            do {
                let newSchedule = ScheduledActivity(
                    id: schedule.id,
                    activityId: activityId,
                    targetContactUid: selectedContactUid,
                    scheduledAt: scheduledAt,
                    recurrence: recurrence,
                    enabled: schedule.enabled,
                    createdAt: schedule.createdAt,
                    lastActivatedAt: schedule.lastActivatedAt
                )

                try await scheduleManager.updateSchedule(newSchedule)

                await MainActor.run {
                    isSaving = false
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

    // MARK: - Delete

    private func delete() {
        Task {
            do {
                try await scheduleManager.deleteSchedule(id: schedule.id)
                await MainActor.run {
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    let sampleSchedule = ScheduledActivity(
        id: UUID().uuidString,
        activityId: "walk",
        targetContactUid: "test_uid",
        scheduledAt: Date().addingTimeInterval(86400),
        recurrence: RecurrenceRule(type: .daily)
    )

    return NavigationStack {
        EditScheduleView(schedule: sampleSchedule)
    }
}
