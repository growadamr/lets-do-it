import SwiftUI
import FirebaseCore

@main
struct LetsDoItApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

    init() {
        FirebaseApp.configure()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(DeepLinkRouter.shared)
                .environment(NetworkMonitor.shared)
        }
    }
}
