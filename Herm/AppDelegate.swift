import UIKit
import FirebaseCore
import FirebaseAuth
import FirebaseMessaging

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // Configure Firebase
        FirebaseApp.configure()

        // Configure Firebase Messaging
        Messaging.messaging().delegate = self

        return true
    }

    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        // Handle Firebase Auth deep links
        return Auth.handle(url) || super.application(app, open: url, options: options)
    }

    func application(
        _ application: UIApplication,
        continue userActivity: NSUserActivity,
        restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void
    ) -> Bool {
        return super.application(application, continue: userActivity, restorationHandler: restorationHandler)
    }
}

extension AppDelegate: MessagingDelegate {
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let token = fcmToken else { return }

        // Save FCM token to Firestore
        let user = Auth.auth().currentUser
        guard let user = user else { return }

        db.collection("users").document(user.uid).updateData([
            "fcmToken": token
        ]) { error in
            if let error = error {
                print("Unable to save FCM token: \(error)")
            }
        }
    }
}
