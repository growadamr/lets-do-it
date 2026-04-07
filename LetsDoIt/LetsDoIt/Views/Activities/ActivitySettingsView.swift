import SwiftUI

struct ActivitySettingsView: View {
    @ObservedObject private var activityManager = ActivityManager.shared
    @Environment(\.dismiss) private var dismiss
    let contactUid: String

    var body: some View {
        NavigationStack {
            Form {
                catalogSection
                customActivitiesSection
                createCustomActivityButton
            }
            .navigationTitle("Activity Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .bold()
                }
            }
            .sheet(isPresented: $showingEditActivity) {
                if let activity = selectedEditActivity {
                    EditCustomActivityView(activity: activity) {
                        selectedEditActivity = nil
                    }
                }
            }
        }
    }

    // MARK: - Catalog Activities Section

    private var catalogSection: some View {
        Section("Catalog Activities") {
            ForEach(ActivityCatalog.grouped, id: \.category) { group in
                DisclosureGroup(group.category.rawValue) {
                    ForEach(group.items) { item in
                        Toggle(isOn: Binding(
                            get: { activityManager.isEnabled(for: contactUid, activityId: item.id) },
                            set: { _ in
                                Task {
                                    try? await activityManager.togglePreference(for: contactUid, activityId: item.id)
                                }
                            }
                        )) {
                            Label {
                                Text(item.label)
                            } icon: {
                                Text(item.emoji)
                            }
                        }
                        .tint(.accentColor)
                    }
                }
            }
        }
    }

    // MARK: - My Custom Activities Section

    @ViewBuilder
    private var customActivitiesSection: some View {
        Section("My Custom Activities") {
            if activityManager.customActivities.isEmpty {
                ContentUnavailableView(
                    "No Custom Activities",
                    systemImage: "plus.circle",
                    description: Text("Create your first custom activity below.")
                )
                .listRowSeparator(.hidden)
            } else {
                ForEach(activityManager.customActivities) { activity in
                    HStack(spacing: 12) {
                        Text(activity.emoji)
                            .font(.title2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(activity.label)
                                .font(.body)
                            Text(activity.category.rawValue)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedEditActivity = activity
                        showingEditActivity = true
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            Task {
                                try? await activityManager.deleteCustomActivity(id: activity.id)
                            }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }

    @State private var selectedEditActivity: CustomActivity?
    @State private var showingEditActivity = false

    // MARK: - Create Custom Activity Button

    @ViewBuilder
    private var createCustomActivityButton: some View {
        Section {
            NavigationLink {
                CreateCustomActivityView()
            } label: {
                Label("Create Custom Activity", systemImage: "plus.circle.fill")
                    .foregroundColor(.accentColor)
            }
        } footer: {
            Text("Create activities with custom emoji, labels, and per-contact visibility.")
        }
    }
}

#Preview {
    ActivitySettingsView(contactUid: "preview_contact_123")
}
