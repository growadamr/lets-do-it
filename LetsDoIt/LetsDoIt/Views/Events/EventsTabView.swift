import SwiftUI

// MARK: - Events Tab View (Tab Shell)

struct EventsTabView: View {
    @Environment(DeepLinkRouter.self) private var router
    @StateObject private var eventManager = EventManager.shared
    @State private var navPath = NavigationPath()
    @State private var showCreateEvent = false
    @State private var eventToEdit: Event?
    @State private var selectedEventId: String?

    var body: some View {
        NavigationStack(path: $navPath) {
            EventsListView(onSelectEvent: { eventId in
                selectedEventId = eventId
            })
                .environmentObject(eventManager)
                .navigationDestination(item: $selectedEventId) { eventId in
                    if let event = findEvent(by: eventId) {
                        EventDetailView(event: event)
                            .environmentObject(eventManager)
                    }
                }
                .navigationTitle("Events")
                .task {
                    eventManager.startListening()
                }
                .onDisappear {
                    eventManager.stopListening()
                }
        }
        .onChange(of: router.route) { _, newRoute in
            if case .event(let id) = newRoute {
                selectedEventId = id
                router.clear()
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showCreateEvent = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showCreateEvent) {
            CreateEventView { _ in
                // Real-time listener will auto-populate the list
            }
        }
        .sheet(item: $eventToEdit) { event in
            EditEventView(event: event) { _ in
                // Real-time listener will auto-refresh
            }
        }
    }

    private func findEvent(by id: String) -> Event? {
        eventManager.events.first { $0.id == id }
        ?? eventManager.pastEvents.first { $0.id == id }
    }
}
