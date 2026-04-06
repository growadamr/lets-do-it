import SwiftUI

// MARK: - Recurrence Picker View

/// Sheet-based picker for selecting a recurrence rule: one-time, daily, weekly, or custom days of week.
struct RecurrencePickerView: View {
    @Binding var recurrence: RecurrenceRule?

    @Environment(\.dismiss) private var dismiss

    @State private var selectedType: RecurrenceType = .custom
    @State private var selectedDays: Set<Int> = []
    @State private var showingValidationError = false

    private let weekdaySymbols: [String] = {
        var calendar = Calendar.current
        calendar.firstWeekday = 1 // Sunday
        return calendar.veryShortWeekdaySymbols
    }()

    init(recurrence: Binding<RecurrenceRule?>) {
        self._recurrence = recurrence

        // Initialize state from existing recurrence
        if let existing = recurrence.wrappedValue {
            self._selectedType = State(initialValue: existing.type)
            self._selectedDays = State(initialValue: Set(existing.daysOfWeek ?? []))
        } else {
            // Default to no recurrence (one-time)
            self._selectedType = State(initialValue: .daily)
            self._selectedDays = State(initialValue: [])
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Recurrence Type") {
                    Picker("Type", selection: $selectedType) {
                        Text("One-time").tag(RecurrenceType.daily)
                        Text("Daily").tag(RecurrenceType.daily)
                        Text("Weekly").tag(RecurrenceType.weekly)
                        Text("Custom").tag(RecurrenceType.custom)
                    }
                }

                if selectedType == .custom {
                    Section("Repeat On") {
                        HStack(spacing: 8) {
                            ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { index, symbol in
                                DayCircle(
                                    symbol: symbol,
                                    isSelected: selectedDays.contains(index),
                                    onTap: { toggleDay(index) }
                                )
                            }
                        }
                        .padding(.vertical, 8)

                        if selectedDays.isEmpty {
                            Text("Select at least one day.")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                }

                if showingValidationError {
                    Section {
                        Label("Please select at least one day for custom recurrence.", systemImage: "exclamationmark.triangle")
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Recurrence")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        applyRecurrence()
                    }
                    .bold()
                    .disabled(selectedType == .custom && selectedDays.isEmpty)
                }
            }
        }
    }

    private func toggleDay(_ index: Int) {
        if selectedDays.contains(index) {
            selectedDays.remove(index)
        } else {
            selectedDays.insert(index)
        }
    }

    private func applyRecurrence() {
        switch selectedType {
        case .daily:
            recurrence = RecurrenceRule(type: .daily)
        case .weekly:
            recurrence = RecurrenceRule(type: .weekly)
        case .custom:
            if selectedDays.isEmpty {
                showingValidationError = true
                return
            }
            recurrence = RecurrenceRule(type: .custom, daysOfWeek: selectedDays.sorted())
        }
        dismiss()
    }
}

// MARK: - Day Circle

struct DayCircle: View {
    let symbol: String
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack {
                Circle()
                    .fill(isSelected ? Color.accentColor : Color.gray.opacity(0.2))
                    .frame(width: 40, height: 40)

                Text(symbol)
                    .font(.caption.bold())
                    .foregroundColor(isSelected ? .white : .primary)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    struct PreviewWrapper: View {
        @State private var recurrence: RecurrenceRule?

        var body: some View {
            VStack {
                Text(recurrence?.displaySummary ?? "No recurrence")
                    .padding()

                Button("Open Picker") {
                    // In a real app this would present a sheet
                }
            }
            .sheet(isPresented: .constant(true)) {
                RecurrencePickerView(recurrence: $recurrence)
            }
        }
    }
    return PreviewWrapper()
}

// MARK: - RecurrenceRule Display Helper

extension RecurrenceRule {
    var displaySummary: String {
        switch type {
        case .daily:
            return "Daily"
        case .weekly:
            return "Weekly"
        case .custom:
            if let days = daysOfWeek, !days.isEmpty {
                var calendar = Calendar.current
                calendar.firstWeekday = 1
                let symbols = calendar.veryShortWeekdaySymbols
                let labels = days.sorted().map { symbols[$0] }
                return "Every \(labels.joined(separator: ", "))"
            }
            return "Weekly"
        }
    }
}
