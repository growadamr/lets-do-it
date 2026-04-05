import SwiftUI

struct HomeView: View {
    var body: some View {
        TabView {
            ActivityTabView()
                .tabItem {
                    Label("Activity", systemImage: "star.circle")
                }

            MessagesTabView()
                .tabItem {
                    Label("Messages", systemImage: "message")
                }

            ContactsTabView()
                .tabItem {
                    Label("Contacts", systemImage: "person.2")
                }
        }
    }
}
