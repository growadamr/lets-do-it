import SwiftUI

/// Landing page for the Activity tab when no contact is selected.
/// Shows a list of recent matches (like the Messages conversation list)
/// or the default "Let's do it!" empty state.
struct MatchesLandingView: View {
    @ObservedObject private var contactManager = ContactManager.shared
    @StateObject private var matchManager = MatchManager.shared
    @State private var showingContacts = false
    @State private var selectedMatch: Match?

    var body: some View {
        Group {
            if matchManager.matches.isEmpty {
                emptyState
            } else {
                matchList
            }
        }
        .navigationTitle("Let's do it!")
        .fullScreenCover(isPresented: $showingContacts) {
            ContactsListView(onSelect: {
                showingContacts = false
            })
            .presentationDetents([.large])
        }
        .sheet(item: $selectedMatch) { match in
            MatchDetailView(match: match)
                .presentationDetents([.medium])
        }
        .onAppear {
            matchManager.startListening()
        }
        .onDisappear {
            matchManager.stopListening()
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "person.2.circle")
                .font(.system(size: 80))
                .foregroundColor(.accentColor)

            Text("Let's do it!")
                .font(.largeTitle.bold())

            Text("Select a contact to get started")
                .foregroundColor(.secondary)

            Button("View Contacts") {
                showingContacts = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 40)

            Spacer()
        }
        .padding()
    }

    // MARK: - Match List

    private var matchList: some View {
        List {
            Section("Recent Matches") {
                ForEach(matchManager.matches) { match in
                    MatchRow(match: match, contactName: matchManager.contactDisplayName(for: match.contactUid))
                        .onTapGesture {
                            selectedMatch = match
                        }
                }
            }

            // Still show the "View Contacts" button below the matches
            Section {
                Button {
                    showingContacts = true
                } label: {
                    Label("Find New Activities", systemImage: "plus.circle.fill")
                        .foregroundColor(.accentColor)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}

// MARK: - Match Row

struct MatchRow: View {
    let match: Match
    let contactName: String

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color.accentColor.opacity(0.2))
                .frame(width: 44, height: 44)
                .overlay {
                    Text(match.emoji)
                        .font(.title2)
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(match.label)
                    .font(.body.bold())
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text("with \(contactName)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Text("•")
                        .foregroundColor(.secondary)

                    Text(match.date, style: .relative)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack {
        MatchesLandingView()
    }
}
