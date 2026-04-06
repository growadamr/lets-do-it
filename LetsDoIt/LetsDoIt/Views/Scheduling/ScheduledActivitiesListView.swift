import SwiftUI

// MARK: - Scheduled Activities List View

struct ScheduledActivitiesListView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var scheduleManager = ScheduleManager.shared
    @StateObject private var contactManager = ContactManager.shared
    @StateObject private var activityManager = ActivityManager.shared

    /// When set, only show schedules for this contact.
    var filterContactUid: String?

    @State private var resolvedActivities: [String: (emoji: String, label: String)] = [:]
    @State private var scheduleToDelete: ScheduledActivity?
    @State private var showDeleteConfirmation = false
    @State private var scheduleToEdit: ScheduledActivity?

    // MARK: - Computed Data

    private var filteredSchedules: [ScheduledActivity] {
        if let filterContactUid {
            return scheduleManager.schedules.filter { $0.targetContactUid == filterContactUid }
        }
        return scheduleManager.schedules
    }

    private var groupedSchedules: [(contactUid: String, contactName: String, schedules: [ScheduledActivity])] {
        let grouped = Dictionary(grouping: filteredSchedules, by: \.targetContactUid)
        return grouped.map { contactUid, schedules in
            let name = contactName(for: contactUid)
            let sorted = schedules.sorted { $0.scheduledAt < $1.scheduledAt }
            return (contactUid: contactUid, contactName: name, schedules: sorted)
        }.sorted { $0.contactName < $1.contactName }
    }

    // MARK: - Body

    var body: some View {
        Group {
            if filteredSchedules.isEmpty {
                ContentUnavailableView(
                    "No Scheduled Activities",
                    systemImage: "calendar.badge.clock",
                    description: Text("Schedule activities to auto-activate at specific times.")
                )
            } else {
                List {
                    ForEach(groupedSchedules, id: \.contactUid) { group in
                        Section(group.contactName) {
                            ForEach(group.schedules) { schedule in
                                scheduleRow(schedule)
                                    .onTapGesture {
                                        scheduleToEdit = schedule
                                    }
                            }
                            .onDelete { offsets in
                                guard let index = offsets.first,
                                      index < group.schedules.count else { return }
                                scheduleToDelete = group.schedules[index]
                                showDeleteConfirmation = true
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Scheduled Activities")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
        .confirmationDialog(
            "Delete Schedule",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                Task {
                    if let schedule = scheduleToDelete {
                        try await scheduleManager.deleteSchedule(id: schedule.id)
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let schedule = scheduleToDelete,
               let details = resolvedActivities[schedule.id] {
                Text("Delete \"\(details.label)\" for \(contactName(for: schedule.targetContactUid))?")
            } else {
                Text("Are you sure you want to delete this schedule?")
            }
        }
        .navigationDestination(item: $scheduleToEdit) { schedule in
            EditScheduleView(schedule: schedule)
        }
        .task {
            scheduleManager.startListening()
            await resolveAllActivities()
        }
    }

    // MARK: - Schedule Row

    @ViewBuilder
    private func scheduleRow(_ schedule: ScheduledActivity) -> some View {
        let details = resolvedActivities[schedule.id] ?? ("🎯", "Loading...")

        HStack(spacing: 12) {
            // Activity emoji
            Text(details.emoji)
                .font(.system(size: 30))

            VStack(alignment: .leading, spacing: 4) {
                // Activity label
                Text(details.label)
                    .font(.headline)

                // Next activation description
                Text(scheduleManager.nextActivationDescription(schedule))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                // Enabled/disabled status label
                Text(schedule.enabled ? "Enabled" : "Paused")
                    .font(.caption2)
                    .foregroundStyle(schedule.enabled ? .green : .gray)
            }

            Spacer()

            // Enable/disable toggle
            Toggle("", isOn: Binding(
                get: { schedule.enabled },
                set: { newValue in
                    Task {
                        try await scheduleManager.toggleEnabled(id: schedule.id, enabled: newValue)
                    }
                }
            ))
            .labelsHidden()
        }
        .padding(.vertical, 4)
        .opacity(schedule.enabled ? 1 : 0.6)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                scheduleToDelete = schedule
                showDeleteConfirmation = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Helpers

    private func contactName(for uid: String) -> String {
        contactManager.contacts.first(where: { $0.uid == uid })?.displayName ?? "Unknown Contact"
    }

    private func resolveAllActivities() async {
        let schedules = filteredSchedules
        for schedule in schedules where resolvedActivities[schedule.id] == nil {
            let details = await activityManager.resolveActivityDetails(
                itemId: schedule.activityId,
                contactUid: schedule.targetContactUid
            )
            resolvedActivities[schedule.id] = details
        }
    }
}

#Preview {
    NavigationStack {
        ScheduledActivitiesListView()
    }
}
