import SwiftUI

struct ActivityRow: View {
    let item: ActivityItem
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                Text(item.emoji)
                    .font(.title2)

                Text(item.label)
                    .font(.body)
                    .foregroundColor(.primary)

                Spacer()

                // Show a subtle indicator if the user has selected this item.
                // No indicator for partner's selections — those are invisible.
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.title3)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle()) // make entire row tappable
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }
}
