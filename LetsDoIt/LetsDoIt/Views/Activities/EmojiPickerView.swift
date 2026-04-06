import SwiftUI

/// Grid-based emoji selector organized by category with search.
/// Used by CreateCustomActivityView and EditCustomActivityView.
struct EmojiPickerView: View {
    let onEmojiSelected: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var filteredSections: [(category: String, emojis: [String])] {
        guard !searchText.isEmpty else { return emojiSections }
        return emojiSections.compactMap { section in
            let filtered = section.emojis
            return filtered.isEmpty ? nil : (section.category, filtered)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(filteredSections, id: \.category) { section in
                    Section(section.category) {
                        LazyVGrid(
                            columns: Array(repeating: GridItem(.flexible()), count: 6),
                            spacing: 12
                        ) {
                            ForEach(section.emojis, id: \.self) { emoji in
                                Button {
                                    onEmojiSelected(emoji)
                                    dismiss()
                                } label: {
                                    Text(emoji)
                                        .font(.title2)
                                }
                                .buttonStyle(.plain)
                                .frame(maxWidth: .infinity)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                if filteredSections.isEmpty {
                    ContentUnavailableView(
                        "No Matches",
                        systemImage: "face.dashed",
                        description: Text("No emojis match \"\(searchText)\".")
                    )
                    .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
            .searchable(text: $searchText, prompt: "Search or pick an emoji")
            .navigationTitle("Choose an Emoji")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Emoji Data

private let emojiSections: [(category: String, emojis: [String])] = [
    (
        "Smileys & People",
        ["😀", "😃", "😄", "😁", "😆", "😅", "🤣", "😂", "🙂", "😊", "😇", "🥰", "😍", "🤩", "😘", "😗", "😋", "😛", "😜", "🤪", "😎", "🤗", "🤔", "🤫", "🤭", "😐", "😑", "😶", "😏", "😒", "🙄", "😬", "😌", "😔", "😪", "🤤", "😴", "😷", "🤒", "🤕", "🤢", "🤮", "🥵", "🥶", "🥴", "😵", "🤯", "🤠", "🥳", "😎", "🤓", "🧐", "👍", "👎", "👊", "✊", "🤛", "🤜", "👏", "🙌", "👐", "🤝", "🙏", "✌️", "🤞", "🤟", "🤘", "👌", "👈", "👉", "👆", "👇"]
    ),
    (
        "Activities & Sports",
        ["⚽", "🏀", "🏈", "⚾", "🥎", "🎾", "🏐", "🏉", "🥏", "🎱", "🏓", "🏸", "🥅", "⛳", "🎣", "🤿", "🏊", "🚴", "🏃", "🧘", "🏋️", "🤸", "⛷️", "🏂", "🎮", "🎯", "🎪", "🎭", "🎨", "🎬", "🎤", "🎧", "🎵", "🎶", "🎹", "🎸", "🥁"]
    ),
    (
        "Food & Drink",
        ["🍎", "🍐", "🍊", "🍋", "🍌", "🍉", "🍇", "🍓", "🫐", "🍒", "🍑", "🥭", "🍍", "🥥", "🥝", "🍅", "🥑", "🍔", "🍟", "🌭", "🍕", "🥪", "🌮", "🍜", "🍣", "🍦", "🍩", "🎂", "🍰", "🍪", "🍫", "🍬", "🍭", "☕", "🍵", "🧃", "🥤", "🍺", "🍻", "🥂", "🍷", "🍸", "🍹"]
    ),
    (
        "Travel & Places",
        ["🚗", "🚕", "🚙", "🚌", "🚎", "🏎️", "🚓", "🚑", "🚒", "✈️", "🚀", "🛸", "🚁", "🛶", "⛵", "🚢", "🏠", "🏡", "🏢", "🏣", "🏥", "🏦", "🏨", "🏪", "🏫", "🏖️", "🏝️", "🏜️", "🌋", "⛰️", "🗻", "🏕️", "🌅", "🌄"]
    ),
    (
        "Nature",
        ["🌵", "🎄", "🌲", "🌳", "🌴", "🌱", "🌿", "☘️", "🍀", "🍁", "🍂", "🍃", "🌺", "🌸", "🌷", "🌹", "🌻", "🌼", "🐶", "🐱", "🐭", "🐹", "🐰", "🦊", "🐻", "🐼", "🐨", "🐯", "🦁", "🐮", "🐷", "🐸", "🐵", "🐔", "🐧", "🐦", "🦆", "🦅", "🦉", "🦇", "🐺", "🐗", "🐴", "🦄", "🐝", "🐛", "🦋", "🐌", "🐞"]
    ),
    (
        "Objects",
        ["⌚", "📱", "💻", "⌨️", "🖥️", "🖨️", "🖱️", "💾", "💿", "📷", "📹", "🎥", "📽️", "📞", "☎️", "📟", "📠", "📺", "📻", "🎙️", "💡", "🔦", "📔", "📕", "📖", "📗", "📘", "📙", "📚", "📓", "📒", "📃", "📜", "📄", "📰", "🗞️", "📑", "🔖", "💰", "💳", "💎", "🔧", "🔨", "⚙️", "🧲"]
    ),
    (
        "Symbols & Shapes",
        ["❤️", "🧡", "💛", "💚", "💙", "💜", "🖤", "🤍", "🤎", "💔", "💕", "💖", "💗", "💘", "💝", "💞", "💟", "❣️", "💌", "💤", "💢", "💣", "💥", "💦", "💨", "🔥", "⭐", "🌟", "✨", "💫", "🎉", "🎊", "🏆", "🥇", "🥈", "🥉", "🎗️", "🎖️", "🔔", "🔕", "✅", "❌", "⭕", "❗", "❓", "‼️", "⁉️", "🔴", "🟢", "🔵", "🟡", "🟠", "⚫", "⚪", "🟤", "⬛", "⬜", "🔶", "🔷", "🔸", "🔹", "💠"]
    ),
]

#Preview {
    EmojiPickerView { emoji in
        print("Selected: \(emoji)")
    }
}
