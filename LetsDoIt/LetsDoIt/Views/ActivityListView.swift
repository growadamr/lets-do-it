import SwiftUI
import Combine

struct ActivityListView: View {
    @StateObject private var selectionManager = SelectionManager.shared
    @ObservedObject private var pairingManager = PairingManager.shared
    @State private var tappedItemId: String?
    @State private var timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        List {
            ForEach(ActivityCatalog.grouped, id: \.category) { group in
                Section(group.category.rawValue) {
                    ForEach(group.items) { item in
                        ActivityRow(
                            item: item,
                            isSelected: selectionManager.activeSelections.contains(item.id),
                            onTap: {
                                Task { await selectItem(item) }
                            }
                        )
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .onAppear {
            if let pairId = pairingManager.pairId {
                selectionManager.startListening(pairId: pairId)
            }
        }
        .onDisappear {
            selectionManager.stopListening()
        }
        .onReceive(timer) { _ in
            if let pairId = pairingManager.pairId {
                selectionManager.startListening(pairId: pairId)
            }
        }
    }

    private func selectItem(_ item: ActivityItem) async {
        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()

        do {
            try await selectionManager.toggleSelection(itemId: item.id)
        } catch {
            print("Selection error: \(error)")
        }
    }
}
