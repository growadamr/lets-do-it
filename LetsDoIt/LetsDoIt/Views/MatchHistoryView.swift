import SwiftUI
import FirebaseFirestore

struct MatchHistoryView: View {
    @State private var matches: [MatchRecord] = []
    @State private var isLoading = true

    let pairId: String

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
            } else if matches.isEmpty {
                Text("No matches yet — start tapping!")
                    .foregroundColor(.secondary)
            } else {
                List(matches) { match in
                    HStack {
                        Text(match.emoji)
                            .font(.title2)
                        VStack(alignment: .leading) {
                            Text(match.label)
                                .font(.body)
                            Text(match.date, style: .relative)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Match History")
        .task { await loadMatches() }
    }

    private func loadMatches() async {
        let db = Firestore.firestore()
        do {
            let snapshot = try await db.collection("pairs").document(pairId)
                .collection("selections")
                .whereField("matched", isEqualTo: true)
                .order(by: "createdAt", descending: true)
                .limit(to: 50)
                .getDocuments()

            // Deduplicate (two docs per match, one per user)
            var seen = Set<String>()
            var records: [MatchRecord] = []

            for doc in snapshot.documents {
                let data = doc.data()
                guard let itemId = data["itemId"] as? String,
                      let createdAt = data["createdAt"] as? Timestamp else {
                    continue
                }

                let key = itemId + createdAt.dateValue().description
                if seen.contains(key) {
                    continue
                }
                seen.insert(key)

                if let item = ActivityCatalog.items.first(where: { $0.id == itemId }) {
                    records.append(MatchRecord(
                        id: doc.documentID,
                        itemId: itemId,
                        emoji: item.emoji,
                        label: item.label,
                        date: createdAt.dateValue()
                    ))
                }
            }

            matches = records
        } catch {
            print("Failed to load matches: \(error)")
        }
        isLoading = false
    }
}

struct MatchRecord: Identifiable {
    let id: String
    let itemId: String
    let emoji: String
    let label: String
    let date: Date
}
