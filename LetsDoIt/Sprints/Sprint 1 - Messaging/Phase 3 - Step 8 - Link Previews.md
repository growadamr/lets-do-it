# Phase 3, Step 8: Link Previews — Implementation Log

**Date:** 2026-04-05
**Status:** ✅ Complete — BUILD SUCCEEDED

---

## What Was Done

### New Files Created

| File | Purpose |
|------|---------|
| `Services/LinkPreviewGenerator.swift` | `LPMetadataProvider` wrapper for fetching Open Graph metadata (title, description, thumbnail image) from URLs |
| `Views/Messaging/LinkPreviewView.swift` | Renders a link preview card with optional thumbnail, title, description — sender-aware tinting |

### Files Modified

| File | Change |
|------|--------|
| `Services/MessagingManager.swift` | Added `messageId: String?` parameter to `sendMessage` (for pre-generated IDs); added `attachLinkPreview(_:toMessage:inConversation:)` for non-blocking preview attachment |
| `Views/Messaging/ChatView.swift` | Non-blocking URL detection: message sends immediately with pre-generated ID, then `Task.detached` generates preview and calls `attachLinkPreview` |
| `Views/Messaging/MessageBubbleView.swift` | Renders `LinkPreviewView` with `isFromCurrentUser` between image and text when `message.linkPreview` is non-nil |

---

## Service Details

### `LinkPreviewGenerator`

```swift
struct LinkPreviewGenerator
```

| Method | Description |
|---|---|
| `generatePreview(url: String) async -> LinkPreview?` | Entry point — fetches metadata for a URL string with 5-second timeout, returns `nil` on failure |
| `extractFirstURL(from text: String) -> String?` | Regex-based URL extraction (`https?://\S+`), strips trailing punctuation. Used by ChatView before calling `generatePreview(url:)` |
| `fetchMetadata(url:) async throws -> LinkPreview` | Uses `LPMetadataProvider.startFetchingMetadata(for:)` to get `LPLinkMetadata` |
| `fetchDescription(url:) async -> String?` | Best-effort HTML fetch — parses `og:description` or `<meta name="description">` via regex (3-second timeout) |
| `extractImageURL(from:) async -> String?` | Loads `UIImage` from `NSItemProvider`, compresses to JPEG, saves to temp directory, returns local `file://` URL |
| `withTimeout(seconds:operation:) async throws -> T` | Generic timeout wrapper using `withThrowingTaskGroup` |

### `LinkPreviewView`

| Property | Type | Notes |
|---|---|---|
| `linkPreview` | `LinkPreview` | Input model |
| `isFromCurrentUser` | `Bool` | Controls card tint: blue-tinted for self, gray for others |
| `openURL` | `@Environment(\.openURL)` | Tap-to-open-Safari gesture |

**Layout (top to bottom):**
1. Optional `AsyncImage` thumbnail — 120px height, `.fill` aspect ratio, clipped to rounded rect, placeholder with link icon on failure/loading
2. Domain label (`.caption2`, secondary) — extracted from URL host
3. Title label (`.subheadline.bold()`, 2-line limit)
4. Description label (`.caption`, `.secondary`, 2-line limit)
5. Background: blue 15% opacity for self, `systemGray6` for others; matching border tint

---

## Modified File Details

### `MessagingManager.sendMessage`

Added two optional parameters:
- `messageId: String?` — When provided, uses it as the Firestore document ID instead of auto-generating one. This enables the non-blocking preview flow (we need to know the doc ID ahead of time to update it later).
- `linkPreview: LinkPreview?` — Serialized into a nested Firestore map (unchanged from initial implementation).

### `MessagingManager.attachLinkPreview`

New method for the non-blocking preview attachment flow:

```swift
func attachLinkPreview(_ linkPreview: LinkPreview, toMessage messageId: String, inConversation conversationId: String) async throws
```

Uses `updateData` on the existing message document to add the `linkPreview` field after the message has already been created.

### `ChatView.sendMessage`

Non-blocking flow for text messages:

1. Generate a stable `messageId` via `UUID().uuidString`
2. Send the message **immediately** using the pre-generated ID (no preview)
3. If text contains a URL, spawn a `Task.detached` that:
   - Calls `LinkPreviewGenerator.generatePreview(url:)` (5-second timeout)
   - If successful, calls `MessagingManager.attachLinkPreview(_:toMessage:inConversation:)` to update the message doc
4. If preview generation fails or times out — the message was already sent, no error to user

Image messages skip link preview generation (images are the primary content).

### `MessageBubbleView.bubble`

Added link preview rendering between the image and text blocks:

```swift
if let linkPreview = message.linkPreview {
    LinkPreviewView(linkPreview: linkPreview, isFromCurrentUser: isFromCurrentUser)
        .padding(.horizontal, 4)
}
```

Sender-based tinting: blue-tinted card for current user's messages, gray-tinted for others — matching the bubble's own color scheme.

---

## Architecture Decisions

1. **Non-blocking preview via pre-generated message ID** — The message sends immediately to Firestore with a client-generated UUID. A `Task.detached` then attempts to generate the link preview in the background. If successful, it calls `attachLinkPreview` to `updateData` on the existing message doc. This means the user never waits for metadata fetching — the message appears instantly, and the preview card "pops in" when ready (via the real-time listener).

2. **Dual description fetching strategy** — `LPLinkMetadata` doesn't expose a description field. To fill this gap, `fetchDescription(url:)` performs a separate lightweight HTML request (3-second timeout) to parse `og:description` or `<meta name="description">` tags. This runs inside the same 5-second `withTimeout` group as `LPMetadataProvider`, so the total wait is still bounded at 5 seconds.

3. **Thumbnail images saved locally as temp files** — `LPMetadataProvider` returns image data via `NSItemProvider` (not a remote URL). The generator loads the `UIImage`, compresses to JPEG, and saves to `FileManager.default.temporaryDirectory`. The `LinkPreviewView` renders this via `AsyncImage` with the local `file://` URL. A placeholder with a link icon is shown while loading or on failure.

4. **Sender-aware `LinkPreviewView`** — The view accepts `isFromCurrentUser: Bool` to tint the card background and border. Current user's messages get a blue-tinted card (`Color.blue.opacity(0.15)`); others get `systemGray6`. This keeps the preview visually consistent with the bubble's color scheme.

5. **Single URL per message** — Only the first URL in a message text is previewed. This avoids cluttering the bubble with multiple preview cards.

6. **`openURL` environment action** — Uses SwiftUI's `@Environment(\.openURL)` rather than `UIApplication.shared.open` directly. Respects the user's default browser and works in all presentation contexts.

---

## Build Verification
```
xcodebuild -scheme LetsDoIt -destination 'platform=iOS Simulator,name=iPhone 17' build
→ BUILD SUCCEEDED
```
