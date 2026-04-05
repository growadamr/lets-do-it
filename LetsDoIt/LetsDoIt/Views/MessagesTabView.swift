import SwiftUI

struct MessagesTabView: View {
    var body: some View {
        NavigationStack {
            ConversationsListView()
                .navigationTitle("Messages")
        }
    }
}
