import SwiftUI

/// Displays a "Seen by" indicator showing the names of users who have read a message.
/// Truncates to "Name + N others" when more than 2 readers are present.
/// Part of Phase 3, Step 9 — Read Receipts & Unread Tracking.
struct ReadReceiptsView: View {
    let readBy: [String: Date]       // uid → read timestamp
    let participantNames: [String: String]
    let currentUid: String

    /// The display names of users who have read the message, excluding the current user.
    private var readerNames: [String] {
        readBy
            .filter { $0.key != currentUid }
            .sorted { $0.value < $1.value }
            .compactMap { participantNames[$0.key] }
    }

    /// The formatted "Seen by" string, with truncation for long lists.
    private var seenByText: String {
        guard !readerNames.isEmpty else { return "" }

        if readerNames.count <= 2 {
            return "Seen by " + readerNames.joined(separator: ", ")
        } else {
            let othersCount = readerNames.count - 1
            return "Seen by \(readerNames[0]) + \(othersCount) other\(othersCount > 1 ? "s" : "")"
        }
    }

    var body: some View {
        guard !readerNames.isEmpty else { return AnyView(EmptyView()) }

        return AnyView(
            Text(seenByText)
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.trailing, 28)
                .padding(.bottom, 2)
                .frame(maxWidth: .infinity, alignment: .trailing)
        )
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 12) {
        ReadReceiptsView(
            readBy: [
                "me": Date().addingTimeInterval(-60),
                "alice": Date().addingTimeInterval(-30),
            ],
            participantNames: ["me": "Me", "alice": "Alice"],
            currentUid: "me"
        )

        ReadReceiptsView(
            readBy: [
                "me": Date().addingTimeInterval(-120),
                "alice": Date().addingTimeInterval(-60),
                "bob": Date().addingTimeInterval(-30),
            ],
            participantNames: ["me": "Me", "alice": "Alice", "bob": "Bob"],
            currentUid: "me"
        )

        ReadReceiptsView(
            readBy: [
                "me": Date().addingTimeInterval(-120),
                "alice": Date().addingTimeInterval(-60),
                "bob": Date().addingTimeInterval(-30),
                "charlie": Date().addingTimeInterval(-15),
            ],
            participantNames: ["me": "Me", "alice": "Alice", "bob": "Bob", "charlie": "Charlie"],
            currentUid: "me"
        )

        // No readers except self
        ReadReceiptsView(
            readBy: ["me": Date()],
            participantNames: ["me": "Me", "alice": "Alice"],
            currentUid: "me"
        )
    }
    .padding()
}
