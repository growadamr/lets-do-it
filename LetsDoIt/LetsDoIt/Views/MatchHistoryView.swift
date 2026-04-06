import SwiftUI
import FirebaseFirestore
import FirebaseAuth

struct MatchHistoryView: View {
    @State private var matches: [MatchRecord] = []
    @State private var isLoading = true

    let contactUid: String

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
        guard let userId = Auth.auth().currentUser?.uid else { return }

        let db = Firestore.firestore()
        do {
            // NOTE: To optimize, create a Firestore composite index on:
            /// selections -> matched (ASC), userId (ASC), targetUserId (ASC), createdAt (DESC)
            // Query only by matched=true to avoid composite index requirement.
            // Filter and sort in code.
            let snapshot = try await db.collection("users")
                .document(userId)
                .collection("selections")
                .whereField("matched", isEqualTo: true)
                .getDocuments()

            // Filter and sort in code
            var validRecords: [(itemId: String, createdAt: Date, docId: String)] = []

            for doc in snapshot.documents {
                let data = doc.data()

                guard data["userId"] as? String == userId,
                      data["targetUserId"] as? String == contactUid,
                      let itemId = data["itemId"] as? String,
                      let createdAt = data["createdAt"] as? Timestamp else {
                    continue
                }

                validRecords.append((
                    itemId: itemId,
                    createdAt: createdAt.dateValue(),
                    docId: doc.documentID
                ))
            }

            // Sort by date descending
            validRecords.sort { $0.createdAt > $1.createdAt }

            // Deduplicate (two docs per match, one per user)
            var seen = Set<String>()
            var records: [MatchRecord] = []

            // Cache for resolved custom activities within this load
            var customActivityCache: [String: (emoji: String, label: String)] = [:]

            for record in validRecords {
                // Use a stable composite key: itemId + Unix timestamp
                let key = "\(record.itemId)_\(Int(record.createdAt.timeIntervalSince1970))"
                if seen.contains(key) {
                    continue
                }
                seen.insert(key)

                let details: (emoji: String, label: String)
                if let cached = customActivityCache[record.itemId] {
                    details = cached
                } else {
                    details = await ActivityManager.shared.resolveActivityDetails(
                        itemId: record.itemId,
                        contactUid: contactUid
                    )
                    customActivityCache[record.itemId] = details
                }

                records.append(MatchRecord(
                    id: record.docId,
                    itemId: record.itemId,
                    emoji: details.emoji,
                    label: details.label,
                    date: record.createdAt
                ))
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
