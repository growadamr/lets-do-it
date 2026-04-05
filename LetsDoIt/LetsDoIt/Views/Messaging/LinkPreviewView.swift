import SwiftUI

/// Renders a link preview card with an optional thumbnail, title, and description.
/// Tapping the card opens the URL in Safari.
/// Part of Phase 3, Step 8 — Link Previews.
struct LinkPreviewView: View {
    let linkPreview: LinkPreview
    let isFromCurrentUser: Bool

    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            if let url = URL(string: linkPreview.url) {
                openURL(url)
            }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                // Optional thumbnail image
                if let imageUrl = linkPreview.imageUrl, !imageUrl.isEmpty {
                    AsyncImage(url: URL(string: imageUrl)) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(height: 120)
                                .clipped()
                        case .failure:
                            thumbnailPlaceholder
                        case .empty:
                            thumbnailPlaceholder
                        @unknown default:
                            thumbnailPlaceholder
                        }
                    }
                    .frame(height: 120)
                }

                // Text content
                VStack(alignment: .leading, spacing: 4) {
                    // Domain label
                    if let host = URL(string: linkPreview.url)?.host {
                        Text(host)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }

                    // Title
                    if let title = linkPreview.title, !title.isEmpty {
                        Text(title)
                            .font(.subheadline.bold())
                            .lineLimit(2)
                    }

                    // Description
                    if let description = linkPreview.description, !description.isEmpty {
                        Text(description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                }
                .padding(10)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardBackgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(borderColor, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Styling

    private var cardBackgroundColor: Color {
        isFromCurrentUser
            ? Color.blue.opacity(0.15)
            : Color(.systemGray6)
    }

    private var borderColor: Color {
        isFromCurrentUser
            ? Color.blue.opacity(0.3)
            : Color.gray.opacity(0.3)
    }

    private var thumbnailPlaceholder: some View {
        Color(.systemGray5)
            .overlay {
                Image(systemName: "link")
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
            .frame(height: 120)
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 16) {
        LinkPreviewView(
            linkPreview: LinkPreview(
                url: "https://www.example.com/some-article",
                title: "Example Article Title — A Very Descriptive Headline",
                description: "This is a sample description that might span a couple of lines to show how the view handles longer text content.",
                imageUrl: nil
            ),
            isFromCurrentUser: true
        )

        LinkPreviewView(
            linkPreview: LinkPreview(
                url: "https://news.ycombinator.com",
                title: nil,
                description: nil,
                imageUrl: nil
            ),
            isFromCurrentUser: false
        )
    }
    .padding()
}
