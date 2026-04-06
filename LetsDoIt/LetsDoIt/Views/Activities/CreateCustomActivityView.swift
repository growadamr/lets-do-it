import SwiftUI

/// Form for creating a new custom activity.
/// Includes emoji picker, label input, category picker, and contact visibility picker.
struct CreateCustomActivityView: View {
    var onComplete: ((CustomActivity) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @StateObject private var activityManager = ActivityManager.shared

    @State private var selectedEmoji = ""
    @State private var label = ""
    @State private var selectedCategory = ActivityCategory.activities
    @State private var visibleToUids: [String] = []

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
                                if selectedEmoji.isEmpty {
                                    Text("Pick one")
                                        .foregroundColor(.secondary)
                                } else {
                                    Text(selectedEmoji)
                                        .font(.title2)
                                }
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
                    if label.isEmpty && selectedEmoji.isEmpty {
                        Text("Enter a label for this activity.")
                            .font(.caption)
                            .foregroundColor(.secondary)
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
            .navigationTitle("New Custom Activity")
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
                let activity = try await activityManager.createCustomActivity(
                    emoji: selectedEmoji,
                    label: label.trimmingCharacters(in: .whitespacesAndNewlines),
                    category: selectedCategory,
                    visibleTo: visibleToUids
                )
                await MainActor.run {
                    isSaving = false
                    onComplete?(activity)
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
    CreateCustomActivityView()
}
