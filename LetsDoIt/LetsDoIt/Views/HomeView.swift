import SwiftUI

struct HomeView: View {
    @Environment(DeepLinkRouter.self) private var router
    @State private var selectedTab: Int = 1  // Messages tab is default

    var body: some View {
        TabView(selection: $selectedTab) {
            ActivityTabView()
                .tabItem {
                    Label("Activity", systemImage: "star.circle")
                }
                .tag(0)

            MessagesTabView()
                .tabItem {
                    Label("Messages", systemImage: "message")
                }
                .tag(1)

            ContactsTabView()
                .tabItem {
                    Label("Contacts", systemImage: "person.2")
                }
                .tag(2)

            EventsTabView()
                .tabItem {
                    Label("Events", systemImage: "calendar")
                }
                .tag(3)
        }
        .onChange(of: router.route) { _, newRoute in
            guard let route = newRoute else { return }
            switch route {
            case .event:
                selectedTab = 3
            case .conversation:
                selectedTab = 1
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openConversation)) { notification in
            guard let conversationId = notification.userInfo?["id"] as? String else { return }
            selectedTab = 1
            router.handle(.conversation(conversationId))
        }
        .onReceive(NotificationCenter.default.publisher(for: .openConversationWithMessage)) { notification in
            // Switch to Messages tab; MessagesTabView handles the navigation and prefilled message
            selectedTab = 1
        }
    }
}
