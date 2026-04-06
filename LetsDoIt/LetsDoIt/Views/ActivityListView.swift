import SwiftUI
import Combine

struct ActivityListView: View {
    @ObservedObject private var contactManager = ContactManager.shared
    @ObservedObject private var activityManager = ActivityManager.shared
    @State private var activeSelections: Set<String> = []
    @State private var effectiveActivities: [any ActivityDisplayable] = []
    @State private var timer = Timer.publish(every: AppConfig.selectionRefreshInterval, on: .main, in: .common).autoconnect()
    @State private var isLoading = true
    @State private var isActivitiesLoading = false
    @State private var errorMessage: String?
    @State private var showingCreateSchedule = false
    @State private var scheduleActivityId: String?

    var body: some View {
        Group {
            if isLoading || isActivitiesLoading {
                ProgressView("Loading activities...")
            } else if let error = errorMessage {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 40))
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Button("Retry") {
                        Task { await refreshAll() }
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
            } else {
                selectionList
            }
        }
        .task {
            await refreshAll()
        }
        .onReceive(timer) { _ in
            Task { await refreshSelections() }
        }
    }

    // MARK: - Computed Properties

    private var groupedActivities: [(category: ActivityCategory, items: [any ActivityDisplayable])] {
        ActivityCategory.allCases.map { category in
            (category: category, items: effectiveActivities.filter { $0.category == category })
        }
    }

    // MARK: - Views

    private var selectionList: some View {
        List {
            ForEach(groupedActivities, id: \.category) { group in
                Section(group.category.rawValue) {
                    ForEach(group.items, id: \.id) { item in
                        ActivityRow(
                            item: item,
                            isSelected: activeSelections.contains(item.id),
                            onTap: {
                                Task { await selectItem(item) }
                            }
                        )
                        .contextMenu {
                            Button {
                                scheduleActivityId = item.id
                                showingCreateSchedule = true
                            } label: {
                                Label("Schedule This Activity", systemImage: "calendar.badge.clock")
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .sheet(isPresented: $showingCreateSchedule) {
            if let contactUid = contactManager.selectedContact?.uid,
               let activityId = scheduleActivityId {
                CreateScheduleView(
                    preselectedContactUid: contactUid,
                    preselectedActivityId: activityId
                )
            }
        }
    }

    // MARK: - Data Loading

    private func refreshAll() async {
        await refreshSelections()
        await loadEffectiveActivities()
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

    private func loadEffectiveActivities() async {
        guard let contactUid = contactManager.selectedContact?.uid else {
            effectiveActivities = []
            return
        }

        isActivitiesLoading = true
        errorMessage = nil

        do {
            effectiveActivities = try await activityManager.getEffectiveActivities(for: contactUid)
            isActivitiesLoading = false
        } catch {
            errorMessage = "Failed to load activities: \(error.localizedDescription)"
            isActivitiesLoading = false
        }
    }

    private func selectItem(_ item: any ActivityDisplayable) async {
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
