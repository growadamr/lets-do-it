import SwiftUI

// MARK: - Events List View

struct EventsListView: View {
    @EnvironmentObject var eventManager: EventManager
    @State private var eventToDelete: Event?
    @State private var showDeleteConfirmation = false

    var body: some View {
        Group {
            if eventManager.events.isEmpty && eventManager.pastEvents.isEmpty {
                ContentUnavailableView(
                    "No Events Yet",
                    systemImage: "calendar.badge.exclamationmark",
                    description: Text("Events you're invited to will appear here.")
                )
            } else {
                List {
                    if !eventManager.events.isEmpty {
                        Section("Upcoming") {
                            ForEach(eventManager.events) { event in
                                eventRow(event)
                            }
                            .onDelete(perform: deleteEvents)
                        }
                    }

                    if !eventManager.pastEvents.isEmpty {
                        Section("Past") {
                            ForEach(eventManager.pastEvents) { event in
                                eventRow(event)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .confirmationDialog(
            "Delete Event",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                Task {
                    if let event = eventToDelete {
                        try await eventManager.deleteEvent(id: event.id)
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete \"\(eventToDelete?.title ?? "")\"? This will remove it for everyone.")
        }
    }

    // MARK: - Event Row

    @ViewBuilder
    private func eventRow(_ event: Event) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Title + status badge
            HStack {
                Text(event.title)
                    .font(.headline)
                if event.status == .cancelled {
                    Text("Cancelled")
                        .font(.caption2)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.red, in: Capsule(style: .circular))
                }
            }

            // Date
            Label(
                event.dateTime.formatted(date: .abbreviated, time: .shortened),
                systemImage: "calendar"
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)

            // Location (if present)
            if let location = event.location, !location.isEmpty {
                Label(location, systemImage: "mappin")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // RSVP summary
            if !event.rsvps.isEmpty {
                Text(rsvpSummary(for: event))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if eventManager.isCreator(event) {
                Button(role: .destructive) {
                    eventToDelete = event
                    showDeleteConfirmation = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }

    // MARK: - RSVP Summary

    private func rsvpSummary(for event: Event) -> String {
        let counts = Dictionary(grouping: event.rsvps.values, by: { $0 })
        let accepted = counts[.accepted]?.count ?? 0
        let declined = counts[.declined]?.count ?? 0
        let maybe = counts[.maybe]?.count ?? 0

        var parts: [String] = []
        if accepted > 0 { parts.append("\(accepted) accepted") }
        if maybe > 0 { parts.append("\(maybe) maybe") }
        if declined > 0 { parts.append("\(declined) declined") }
        return parts.joined(separator: " · ")
    }

    // MARK: - Delete

    private func deleteEvents(at offsets: IndexSet) {
        guard let index = offsets.first,
              index < eventManager.events.count else { return }
        eventToDelete = eventManager.events[index]
        showDeleteConfirmation = true
    }
}
