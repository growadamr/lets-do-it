import SwiftUI

/// Form for editing an existing custom activity.
/// Pre-filled with the activity's current values; saves updates to Firestore.
struct EditCustomActivityView: View {
    let activity: CustomActivity
    var onComplete: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var activityManager = ActivityManager.shared

    @State private var selectedEmoji: String
    @State private var label: String
    @State private var selectedCategory: ActivityCategory
    @State private var visibleToUids: [String]

    @State private var showingEmojiPicker = false
    @State private var showingContactPicker = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var isValid: Bool {
        !selectedEmoji.isEmpty
        && !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && label.count <= 50
        && !visibleToUids.isEmpty
    }

    init(activity: CustomActivity, onComplete: (() -> Void)? = nil) {
        self.activity = activity
        self.onComplete = onComplete
        _selectedEmoji = State(initialValue: activity.emoji)
        _label = State(initialValue: activity.label)
        _selectedCategory = State(initialValue: activity.category)
        _visibleToUids = State(initialValue: activity.visibleTo)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Activity") {
                    // Emoji picker button
                    HStack(spacing: 12) {
                        Text("Emoji")
                        Spacer()
                        Button {
                            showingEmojiPicker = true
                        } label: {
                            HStack(spacing: 8) {
                                Text(selectedEmoji)
                                    .font(.title2)
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    // Label text field
                    HStack(spacing: 12) {
                        Text("Label")
                        Spacer()
                        TextField("e.g. Date night", text: $label)
                            .multilineTextAlignment(.trailing)
                            .textFieldStyle(.plain)
                    }
                    if !label.isEmpty && label.count > 50 {
                        Text("Label must be 50 characters or fewer (\(label.count)/50)")
                            .font(.caption)
                            .foregroundColor(.red)
                    }

                    // Category picker
                    HStack(spacing: 12) {
                        Text("Category")
                        Spacer()
                        Picker("Category", selection: $selectedCategory) {
                            ForEach(ActivityCategory.allCases, id: \.self) { category in
                                Text(category.rawValue).tag(category)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                }

                Section("Visible To") {
                    Button {
                        showingContactPicker = true
                    } label: {
                        HStack {
                            Text("\(visibleToUids.count) contact\(visibleToUids.count == 1 ? "" : "s") selected")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if visibleToUids.isEmpty {
                        Text("Select at least one contact who can see this activity.")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Edit Activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                    .bold()
                    .disabled(!isValid || isSaving)
                }
            }
            .sheet(isPresented: $showingEmojiPicker) {
                EmojiPickerView { emoji in
                    selectedEmoji = emoji
                }
            }
            .sheet(isPresented: $showingContactPicker) {
                MultiContactPickerView(selectedUids: $visibleToUids)
            }
        }
    }

    private func save() {
        guard isValid else { return }
        isSaving = true
        errorMessage = nil

        Task {
            do {
                let updated = CustomActivity(
                    id: activity.id,
                    emoji: selectedEmoji,
                    label: label.trimmingCharacters(in: .whitespacesAndNewlines),
                    category: selectedCategory,
                    createdAt: activity.createdAt,
                    visibleTo: visibleToUids
                )
                try await activityManager.updateCustomActivity(updated)
                await MainActor.run {
                    isSaving = false
                    onComplete?()
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

#Preview {
    EditCustomActivityView(
        activity: CustomActivity(
            id: "preview_1",
            emoji: "🎯",
            label: "Preview Activity",
            category: .activities,
            createdAt: Date(),
            visibleTo: []
        )
    )
}
