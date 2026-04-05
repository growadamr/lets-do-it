import SwiftUI

struct MessagesTabView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "message")
                    .font(.system(size: 60))
                    .foregroundColor(.secondary)

                Text("No messages yet")
                    .font(.title2.bold())

                Text("Start a conversation with your contacts")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
            .navigationTitle("Messages")
        }
    }
}
