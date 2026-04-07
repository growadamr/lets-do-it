import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseMessaging
import UIKit
import UserNotifications

/// Manages FCM token lifecycle: permission request, remote notification registration,
/// and syncing the token to the user's Firestore document.
@MainActor
struct TokenManager {

    /// Tracks whether the APNs device token has been received.
    /// Until this is true, FCM token sync is skipped to avoid error 505 spam.
    static var apnsTokenReceived: Bool = false

    // MARK: - Permission & Registration

    /// Request notification permission from the user. Returns `true` if granted.
    static func requestPermission() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .badge, .sound])
            if granted {
                print("[TokenManager] Notification permission granted")
            } else {
                print("[TokenManager] Notification permission denied — user must enable in Settings")
            }
            return granted
        } catch {
            print("[TokenManager] Notification permission request failed: \(error)")
            return false
        }
    }

    /// Register the app for remote notifications (APNs).
    static func registerForRemoteNotifications() {
        UIApplication.shared.registerForRemoteNotifications()
    }

    // MARK: - Token Sync

    /// Fetch the current FCM token and write it to `users/{uid}/fcmToken`.
    static func syncTokenToFirestore(uid: String) async {
        guard apnsTokenReceived else {
            // APNs token not yet available — skip sync silently.
            // AppDelegate will trigger this once the APNs token arrives.
            return
        }
        do {
            let token = try await Messaging.messaging().token()
            let db = Firestore.firestore()
            try await db.collection("users").document(uid)
                .updateData(["fcmToken": token])
            print("[TokenManager] FCM token synced to Firestore for user \(uid)")
        } catch {
            // Non-critical — app still works, user just won't get pushes
            print("[TokenManager] Failed to sync FCM token: \(error)")
        }
    }

    /// Convenience: request permission (if not already determined), register, and sync token.
    /// Safe to call multiple times — permission dialog only shows once.
    static func setupNotifications(for uid: String) async {
        // Check current authorization status
        let settings = await UNUserNotificationCenter.current().notificationSettings()

        // Only request if status is still "notDetermined" — if denied, respect user choice
        if settings.authorizationStatus == .notDetermined {
            let granted = await requestPermission()
            if granted {
                registerForRemoteNotifications()
            }
        } else if settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional {
            // Already authorized — just register
            registerForRemoteNotifications()
        } else {
            print("[TokenManager] Notifications previously denied — skipping registration")
        }
    }

    /// Refresh the token for an already-authenticated user (called on app launch).
    static func refreshTokenIfAvailable() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        await syncTokenToFirestore(uid: uid)
    }
}
