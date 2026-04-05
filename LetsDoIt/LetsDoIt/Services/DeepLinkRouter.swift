import Foundation
import Observation

/// Supported deep link destinations. Extensible for future sprints
/// (e.g. `.event(String)` for Sprint 3).
enum DeepLinkRoute: Codable, Hashable {
    case conversation(String)   // conversationId
    // Sprint 3: case event(String)

    private enum CodingKeys: String, CodingKey {
        case type, id
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        let id = try container.decode(String.self, forKey: .id)

        switch type {
        case "conversation":
            self = .conversation(id)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown route type: \(type)"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .conversation(let id):
            try container.encode("conversation", forKey: .type)
            try container.encode(id, forKey: .id)
        }
    }
}

/// Generic deep link router — publishes a route for any consumer to observe.
/// Injected as an `EnvironmentObject` at the app root.
@Observable
final class DeepLinkRouter {
    static let shared = DeepLinkRouter()

    var route: DeepLinkRoute?

    private init() {}

    /// Publish a deep link route. Consumers observe `route` and react.
    /// Must be called on the main thread.
    func handle(_ route: DeepLinkRoute) {
        dispatchPrecondition(condition: .onQueue(.main))
        print("[DeepLinkRouter] Handling route: \(route)")
        self.route = route
    }

    /// Clear the current route after it has been consumed.
    func clear() {
        route = nil
    }

    /// Convenience: parse a conversation ID directly from an FCM data payload.
    /// FCM notifications from the Cloud Function include `conversationId` in the `data` dict.
    /// Safe to call from any thread — dispatches to main queue.
    func handleFCMPayload(_ userInfo: [AnyHashable: Any]) {
        let conversationId: String? = {
            // Direct top-level key
            if let id = userInfo["conversationId"] as? String { return id }
            // Nested under "data" (some FCM configurations)
            if let data = userInfo["data"] as? [AnyHashable: Any],
               let id = data["conversationId"] as? String { return id }
            return nil
        }()

        DispatchQueue.main.async {
            if let conversationId {
                print("[DeepLinkRouter] Handling conversationId from FCM: \(conversationId)")
                self.handle(.conversation(conversationId))
            } else {
                print("[DeepLinkRouter] No conversationId found in FCM payload")
            }
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    /// Post with `userInfo["id"] = conversationId (String)` to open a conversation
    /// from anywhere in the app (e.g. ContactsListView Message button).
    static let openConversation = Notification.Name("openConversation")
}
