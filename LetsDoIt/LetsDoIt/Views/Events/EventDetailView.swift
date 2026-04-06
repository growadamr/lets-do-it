import SwiftUI
import FirebaseAuth

/// Full event detail with RSVP buttons, attendee list, "Open Chat", and Edit (creator only).
struct EventDetailView: View {
    let event: Event

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var eventManager: EventManager
    @State private var editingEvent: Event?
    @State private var isRSVPing = false
    @State private var rsvpError: String?

    private var currentUid: String? {
        Auth.auth().currentUser?.uid
    }

    private var myRSVP: RSVPStatus? {
        guard let uid = currentUid else { return nil }
        return event.rsvps[uid]
    }

    private var isCreator: Bool {
        eventManager.isCreator(event)
    }

    // MARK: - Attendee Grouping

    private struct AttendeeInfo: Identifiable {
        let uid: String
        var displayName: String
        var rsvp: RSVPStatus?
        var id: String { uid }
        var isYou: Bool { uid == Auth.auth().currentUser?.uid }
    }

    private var attendeesByStatus: (accepted: [AttendeeInfo], maybe: [AttendeeInfo], declined: [AttendeeInfo], noResponse: [AttendeeInfo]) {
        var accepted: [AttendeeInfo] = []
        var maybe: [AttendeeInfo] = []
        var declined: [AttendeeInfo] = []
        var noResponse: [AttendeeInfo] = []

        for uid in event.invitees {
            let name = eventManager.inviteeName(for: uid, in: event)
            let rsvp = event.rsvps[uid]
            let info = AttendeeInfo(uid: uid, displayName: name, rsvp: rsvp)

            if rsvp == nil {
                noResponse.append(info)
            } else {
                switch rsvp {
                case .accepted: accepted.append(info)
                case .maybe: maybe.append(info)
                case .declined: declined.append(info)
                case .none: noResponse.append(info)
                }
            }
        }

        return (accepted, maybe, declined, noResponse)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // MARK: Header
                headerSection

                // MARK: RSVP Buttons
                rsvpSection

                // MARK: Error Display
                if let rsvpError {
                    Label(rsvpError, systemImage: "exclamationmark.triangle")
                        .foregroundColor(.red)
                        .font(.subheadline)
                }

                // MARK: Attendee List
                attendeeSection

                // MARK: Open Chat
                if let conversationId = event.conversationId, !conversationId.isEmpty {
                    openChatButton(conversationId)
                }

                // Spacer at bottom
                Spacer(minLength: 24)
            }
            .padding(.horizontal)
            .padding(.top)
        }
        .navigationTitle(event.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if isCreator {
                    Button("Edit") {
                        editingEvent = event
                    }
                    .bold()
                }
            }
        }
        .sheet(item: $editingEvent) { ev in
            EditEventView(event: ev) { _ in
                // Listener will auto-refresh; dismiss if cancelled
            }
            .onDisappear {
                // If the event was cancelled or deleted, dismiss
                if let updated = eventManager.events.first(where: { $0.id == event.id }) {
                    if updated.status == .cancelled {
                        // Keep view open to show cancelled status
                    }
                } else if eventManager.pastEvents.first(where: { $0.id == event.id }) == nil {
                    // Event was deleted
                    dismiss()
                }
            }
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Cancelled badge
            if event.status == .cancelled {
                Text("Cancelled")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.red, in: Capsule(style: .circular))
            }

            // Date & Time
            Label(
                event.dateTime.formatted(date: .abbreviated, time: .shortened),
                systemImage: "calendar"
            )
            .font(.body)

            // Location
            if let location = event.location, !location.isEmpty {
                Label(location, systemImage: "mappin")
                    .font(.body)
            }

            // Description
            if let description = event.description, !description.isEmpty {
                Text(description)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }

            Divider()

            // Creator label
            let creatorName = eventManager.inviteeName(for: event.createdBy, in: event)
            Text("Created by \(creatorName)")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - RSVP Section

    private var rsvpSection: some View {
        VStack(spacing: 12) {
            Text("Your RSVP")
                .font(.headline)

            HStack(spacing: 12) {
                rsvpButton(status: .accepted, icon: "checkmark.circle", label: "Accept")
                rsvpButton(status: .maybe, icon: "questionmark.circle", label: "Maybe")
                rsvpButton(status: .declined, icon: "xmark.circle", label: "Decline")
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private func rsvpButton(status: RSVPStatus, icon: String, label: String) -> some View {
        let isSelected = myRSVP == status
        let isDisabled = isRSVPing || event.status == .cancelled

        return Button {
            submitRSVP(status)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.title2)
                Text(label)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                isSelected ? Color.accentColor.opacity(0.15) : Color(uiColor: .tertiarySystemFill),
                in: RoundedRectangle(cornerRadius: 10)
            )
            .foregroundColor(isSelected ? .accentColor : .primary)
        }
        .disabled(isDisabled)
    }

    private func submitRSVP(_ status: RSVPStatus) {
        guard currentUid != nil else { return }
        // Don't re-send the same status
        if myRSVP == status { return }

        isRSVPing = true
        rsvpError = nil

        Task {
            do {
                try await eventManager.rsvp(eventId: event.id, status: status)
                await MainActor.run {
                    isRSVPing = false
                }
            } catch {
                await MainActor.run {
                    isRSVPing = false
                    rsvpError = error.localizedDescription
                }
            }
        }
    }

    // MARK: - Attendee Section

    private var attendeeSection: some View {
        let groups = attendeesByStatus

        return Group {
            if !groups.accepted.isEmpty {
                attendeeGroup(title: "Accepted", icon: "checkmark.circle.fill", tint: .green, attendees: groups.accepted)
            }
            if !groups.maybe.isEmpty {
                attendeeGroup(title: "Maybe", icon: "questionmark.circle.fill", tint: .orange, attendees: groups.maybe)
            }
            if !groups.declined.isEmpty {
                attendeeGroup(title: "Declined", icon: "xmark.circle.fill", tint: .red, attendees: groups.declined)
            }
            if !groups.noResponse.isEmpty {
                attendeeGroup(title: "No Response", icon: "person", tint: .gray, attendees: groups.noResponse)
            }
        }
    }

    private func attendeeGroup(title: String, icon: String, tint: Color, attendees: [AttendeeInfo]) -> some View {
        Section {
            ForEach(attendees) { attendee in
                HStack {
                    Circle()
                        .fill(tint.opacity(0.2))
                        .frame(width: 32, height: 32)
                        .overlay {
                            Image(systemName: "person.fill")
                                .font(.caption)
                                .foregroundColor(tint)
                        }
                    Text(attendee.displayName)
                        .font(.body)
                    if attendee.isYou {
                        Text("(You)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .foregroundStyle(tint)
                Text("\(title) (\(attendees.count))")
                    .font(.subheadline.bold())
                    .foregroundStyle(tint)
            }
        }
    }

    // MARK: - Open Chat Button

    private func openChatButton(_ conversationId: String) -> some View {
        Button {
            NotificationCenter.default.post(
                name: .openConversation,
                object: nil,
                userInfo: ["id": conversationId]
            )
        } label: {
            HStack {
                Image(systemName: "bubble.left.and.bubble.right")
                Text("Open Chat")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            .foregroundColor(.accentColor)
        }
    }
}

#Preview {
    NavigationStack {
        EventDetailView(
            event: Event(
                id: "preview-1",
                title: "Saturday BBQ",
                description: "Bring your favorite dish! We'll have drinks covered.",
                location: "Central Park, Near the Lake",
                dateTime: Date().addingTimeInterval(86400 * 3),
                createdBy: "creator-uid",
                createdAt: Date().addingTimeInterval(-86400),
                updatedAt: nil,
                invitees: ["creator-uid", "friend-1", "friend-2", "friend-3"],
                rsvps: [
                    "creator-uid": .accepted,
                    "friend-1": .accepted,
                    "friend-2": .maybe,
                    "friend-3": .declined
                ],
                conversationId: "conv-123",
                status: .active
            )
        )
        .environmentObject(EventManager.shared)
    }
}
