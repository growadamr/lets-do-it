import UIKit
import SwiftUI
import FirebaseCore

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        // Use SwiftUI to create the window
        guard let windowScene = scene as? UIWindowScene else { return }

        window = UIWindow(windowScene: windowScene)

        let authManager = AuthManager.shared

        // Check if user is already authenticated
        if let user = authManager.user {
            window?.rootViewController = UIHostingController(rootView: ContentView())
        } else {
            window?.rootViewController = UIHostingController(rootView: AuthView())
        }

        window?.makeKeyAndVisible()
    }
}
