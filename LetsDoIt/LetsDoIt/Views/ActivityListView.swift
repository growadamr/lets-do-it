import SwiftUI
import Combine

struct ActivityListView: View {
    @StateObject private var contactManager = ContactManager.shared
    @State private var activeSelections: Set<String> = []
    @State private var timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        List {
            ForEach(ActivityCatalog.grouped, id: \.category) { group in
                Section(group.category.rawValue) {
                    ForEach(group.items) { item in
                        ActivityRow(
                            item: item,
                            isSelected: activeSelections.contains(item.id),
                            onTap: {
                                Task { await selectItem(item) }
                            }
                        )
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .task {
            await refreshSelections()
        }
        .onReceive(timer) { _ in
            Task { await refreshSelections() }
        }
    }

    private func refreshSelections() async {
        activeSelections = await contactManager.getActiveSelections()
    }

    private func selectItem(_ item: ActivityItem) async {
        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()

        do {
            try await contactManager.toggleSelection(itemId: item.id)
            await refreshSelections()
        } catch {
            print("Selection error: \(error)")
        }
    }
}
