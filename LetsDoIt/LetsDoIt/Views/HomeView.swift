import SwiftUI
import Combine

struct HomeView: View {
    @StateObject private var pairingManager = PairingManager.shared
    @StateObject private var matchListener = MatchListener.shared
    @State private var showCreateCode = false
    @State private var showJoinCode = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if pairingManager.isPaired {
                    VStack(spacing: 12) {
                        if let name = pairingManager.partnerName, !name.isEmpty {
                            Text("Connected with \(name)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }

                        ActivityListView()

                        if let pairId = pairingManager.pairId {
                            NavigationLink("Match History") {
                                MatchHistoryView(pairId: pairId)
                            }
                            .padding(.top, 8)
                        }

                        Button("Disconnect", role: .destructive) {
                            Task { try? await pairingManager.unpair() }
                        }
                        .padding(.bottom, 16)
                    }
                } else {
                    Spacer()

                    Image(systemName: "person.2.circle")
                        .font(.system(size: 80))
                        .foregroundColor(.accentColor)

                    Text("Let's do it!")
                        .font(.largeTitle.bold())

                    Text("Connect with someone to get started")
                        .foregroundColor(.secondary)

                    VStack(spacing: 12) {
                        Button {
                            showCreateCode = true
                        } label: {
                            Label("Create Invite Code", systemImage: "plus.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)

                        Button {
                            showJoinCode = true
                        } label: {
                            Label("Enter a Code", systemImage: "keyboard")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    }
                    .padding(.horizontal, 40)

                    Spacer()
                }
            }
            .padding()
            .navigationTitle("Let's do it!")
            .sheet(isPresented: $showCreateCode) {
                CreateCodeView()
                    .presentationDetents([.medium])
            }
            .sheet(isPresented: $showJoinCode) {
                JoinCodeView()
                    .presentationDetents([.medium])
            }
            .onAppear {
                pairingManager.listenForPairStatus()
                if let pairId = pairingManager.pairId {
                    matchListener.startListening(pairId: pairId)
                }
            }
            .onChange(of: pairingManager.pairId) { _, newPairId in
                if let pairId = newPairId {
                    matchListener.startListening(pairId: pairId)
                } else {
                    matchListener.stopListening()
                }
            }
            .alert(
                "It's a match!",
                isPresented: Binding(
                    get: { matchListener.latestMatch != nil },
                    set: { if !$0 { matchListener.dismissMatch() } }
                )
            ) {
                Button("OK") {
                    matchListener.dismissMatch()
                }
            } message: {
                if let match = matchListener.latestMatch {
                    Text("\(match.emoji) You both want: \(match.label)")
                }
            }
        }
    }
}
