import SwiftUI

// MARK: - Events Tab View (Tab Shell)

struct EventsTabView: View {
    @Environment(DeepLinkRouter.self) private var router
    @StateObject private var eventManager = EventManager.shared
    @State private var navPath = NavigationPath()
    @State private var showCreateEvent = false
    @State private var eventToEdit: Event?

    var body: some View {
        NavigationStack(path: $navPath) {
            EventsListView()
                .environmentObject(eventManager)
                .navigationTitle("Events")
                .task {
                    eventManager.startListening()
                }
                .onDisappear {
                    eventManager.stopListening()
                }
        }
        .onChange(of: router.route) { _, newRoute in
            guard case .event(let id) = newRoute else { return }
            // Step 6: Navigate to EventDetailView
            // For now, just clear the route — detail view not yet implemented.
            print("[EventsTabView] Received event deep link: \(id) (navigation pending Step 6)")
            router.clear()
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
}
