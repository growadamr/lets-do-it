import SwiftUI
import Combine

struct ActivityListView: View {
    @ObservedObject private var contactManager = ContactManager.shared
    @State private var activeSelections: Set<String> = []
    @State private var timer = Timer.publish(every: AppConfig.selectionRefreshInterval, on: .main, in: .common).autoconnect()
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading selections...")
            } else if let error = errorMessage {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 40))
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Button("Retry") {
                        Task { await refreshSelections() }
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
            } else {
                selectionList
            }
        }
        .task {
            await refreshSelections()
        }
        .onReceive(timer) { _ in
            Task { await refreshSelections() }
        }
    }

    private var selectionList: some View {
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
    }

    private func refreshSelections() async {
        isLoading = true
        errorMessage = nil
        do {
            activeSelections = await contactManager.getActiveSelections()
            isLoading = false
        } catch {
            errorMessage = "Failed to load selections: \(error.localizedDescription)"
            isLoading = false
        }
    }

    private func selectItem(_ item: ActivityItem) async {
        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()

        do {
            try await contactManager.toggleSelection(itemId: item.id)
            await refreshSelections()
        } catch {
            errorMessage = "Failed to select: \(error.localizedDescription)"
        }
    }
}
