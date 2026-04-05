import UIKit
import FirebaseCore
import FirebaseMessaging
import FirebaseStorage
import UserNotifications

class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // Set UNUserNotificationCenter delegate for notification tap handling
        UNUserNotificationCenter.current().delegate = self
        Messaging.messaging().delegate = self
        return true
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension AppDelegate: UNUserNotificationCenterDelegate {
    /// Called when the user taps a notification — parse the deep-link payload and route.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        DeepLinkRouter.shared.handleFCMPayload(userInfo)
        completionHandler()
    }

    /// Called when a notification arrives while the app is in the foreground.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show banner + sound even when in foreground
        completionHandler([.banner, .sound])
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Messaging.messaging().apnsToken = deviceToken
    }
}

// MARK: - MessagingDelegate

extension AppDelegate: MessagingDelegate {
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let token = fcmToken else { return }
        print("FCM Token: \(token)")
        NotificationCenter.default.post(
            name: .fcmTokenReceived,
            object: nil,
            userInfo: ["token": token]
        )
    }
}

extension Notification.Name {
    static let fcmTokenReceived = Notification.Name("fcmTokenReceived")
}
