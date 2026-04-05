import Foundation
import LinkPresentation
import UIKit

/// Generates link previews from URLs using Apple's LinkPresentation framework.
/// Fetches Open Graph metadata (title, description, thumbnail image) for a given URL.
/// Part of Phase 3, Step 8 — Link Previews.
struct LinkPreviewGenerator {

    /// Generate a `LinkPreview` for a URL string.
    /// Returns `nil` if the URL is invalid, or if metadata fetching fails.
    static func generatePreview(url: String) async -> LinkPreview? {
        guard let url = URL(string: url) else { return nil }

        do {
            return try await withTimeout(seconds: 5) {
                try await fetchMetadata(url: url)
            }
        } catch {
            return nil
        }
    }

    /// Extract the first URL from text using a regex.
    /// Used by ChatView to detect URLs before calling `generatePreview(url:)`.
    static func extractFirstURL(from text: String) -> String? {
        let pattern = "https?://\\S+"
        guard let range = text.range(of: pattern, options: .regularExpression) else { return nil }
        let raw = String(text[range])
        // Strip trailing punctuation that's unlikely to be part of the URL
        let cleaned = raw.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?)\"'"))
        return cleaned
    }

    // MARK: - Private

    /// Fetch metadata from `LPMetadataProvider` and construct a `LinkPreview`.
    private static func fetchMetadata(url: URL) async throws -> LinkPreview {
        let provider = LPMetadataProvider()
        let metadata = try await provider.startFetchingMetadata(for: url)

        let title = metadata.title

        // Attempt to fetch a description via a lightweight HTML fetch as fallback.
        let description = await fetchDescription(url: url)

        // Extract image from the imageProvider if available
        let imageUrl: String?
        if let imageProvider = metadata.imageProvider {
            imageUrl = await extractImageURL(from: imageProvider)
        } else {
            imageUrl = nil
        }

        return LinkPreview(
            url: url.absoluteString,
            title: title,
            description: description,
            imageUrl: imageUrl
        )
    }

    /// Fetch the page's <title> and og:description via a simple HTML request.
    /// Returns nil on any failure — this is a best-effort enhancement.
    private static func fetchDescription(url: URL) async -> String? {
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 3
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let html = String(data: data, encoding: .utf8) else { return nil }

            // Try og:description first
            if let range = html.range(of: #"<meta[^>]+property="og:description"[^>]+content="([^"]*)""#, options: .regularExpression),
               let contentRange = html.range(of: #"content="([^"]*)""#, options: .regularExpression, range: range),
               let match = html[contentRange].firstMatch(of: /content="([^"]*)"/) {
                return String(match.1)
            }

            // Try description meta
            if let range = html.range(of: #"<meta[^>]+name="description"[^>]+content="([^"]*)""#, options: .regularExpression),
               let contentRange = html.range(of: #"content="([^"]*)""#, options: .regularExpression, range: range),
               let match = html[contentRange].firstMatch(of: /content="([^"]*)"/) {
                return String(match.1)
            }

            return nil
        } catch {
            return nil
        }
    }

    /// Load image data from an NSItemProvider and save to a local temp URL.
    private static func extractImageURL(from provider: NSItemProvider) async -> String? {
        // Try loading as UIImage via continuation
        if provider.canLoadObject(ofClass: UIImage.self) {
            do {
                let image = try await withCheckedThrowingContinuation { continuation in
                    provider.loadObject(ofClass: UIImage.self) { object, error in
                        if let image = object as? UIImage {
                            continuation.resume(returning: image)
                        } else if let error {
                            continuation.resume(throwing: error)
                        } else {
                            continuation.resume(returning: UIImage())
                        }
                    }
                }
                if let jpegData = image.jpegData(compressionQuality: 0.8) {
                    let cacheDir = FileManager.default.temporaryDirectory
                    let fileURL = cacheDir.appendingPathComponent(UUID().uuidString + ".jpg")
                    try? jpegData.write(to: fileURL)
                    return fileURL.absoluteString
                }
            } catch {
                return nil
            }
        }

        // Try loading as Data (public.jpeg or public.png)
        let typeIdentifiers = ["public.jpeg", "public.png", "public.image"]
        for typeIdentifier in typeIdentifiers {
            if provider.hasItemConformingToTypeIdentifier(typeIdentifier) {
                do {
                    let item = try await withCheckedThrowingContinuation { continuation in
                        provider.loadItem(forTypeIdentifier: typeIdentifier) { item, error in
                            if let item {
                                continuation.resume(returning: item)
                            } else if let error {
                                continuation.resume(throwing: error)
                            } else {
                                continuation.resume(returning: NSData())
                            }
                        }
                    }
                    if let data = item as? Data, let image = UIImage(data: data),
                       let jpegData = image.jpegData(compressionQuality: 0.8) {
                        let cacheDir = FileManager.default.temporaryDirectory
                        let fileURL = cacheDir.appendingPathComponent(UUID().uuidString + ".jpg")
                        try? jpegData.write(to: fileURL)
                        return fileURL.absoluteString
                    }
                } catch {
                    continue
                }
            }
        }

        return nil
    }

    /// Simple timeout wrapper using Task sleep.
    private static func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw TimeoutError()
            }

            guard let result = try await group.next() else {
                throw TimeoutError()
            }
            group.cancelAll()
            return result
        }
    }
}

private struct TimeoutError: Error {}
