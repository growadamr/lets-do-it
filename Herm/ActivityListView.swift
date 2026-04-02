import SwiftUI

struct ActivityListView: View {
    let pairId: String

    var body: some View {
        VStack(spacing: 20) {
            Text("Select an activity")
                .font(.title2)
                .fontWeight(.bold)

            // Activity list
            List {
                Section(header: Text("Activities")) {
                    // TODO: Implement activity items
                    // Each item should have:
                    // - itemId (e.g., "drinks", "coffee", "walk")
                    // - onTap gesture to create selection
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}

#Preview {
    ActivityListView(pairId: "test-pair")
}
