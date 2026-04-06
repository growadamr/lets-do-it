import Foundation

/// Centralized configuration for the app's timing and duration constants.
enum AppConfig {
    
    // MARK: - Selections
    
    /// How long a selection remains active before expiring.
    static let selectionExpiryDuration: TimeInterval = 60 * 60  // 1 hour
    
    /// How often the ActivityListView refreshes its selection state.
    static let selectionRefreshInterval: TimeInterval = 30  // seconds
    
    // MARK: - Invite Codes
    
    /// How long an invite code remains valid.
    static let inviteCodeExpiryDuration: TimeInterval = 24 * 60 * 60  // 24 hours
    
    // MARK: - Cloud Functions (documented for reference)
    
    /// How often `checkForMatches` runs (server-side).
    static let matchCheckInterval: TimeInterval = 5 * 60  // 5 minutes

    /// How often `processScheduledActivities` runs (server-side).
    static let scheduleProcessInterval: TimeInterval = 5 * 60  // 5 minutes

    /// How often `sendPendingNotifications` runs (server-side).
    static let notificationSendInterval: TimeInterval = 60  // 1 minute
    
    /// How often `cleanupExpiredSelections` runs (server-side).
    static let cleanupInterval: TimeInterval = 15 * 60  // 15 minutes
    
    /// Random delay range for push notifications (server-side).
    static let notificationDelayRange: ClosedRange<Int> = 1...10  // minutes
}
