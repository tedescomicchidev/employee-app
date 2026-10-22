import Core
import Foundation
import UserNotifications

/// Receives the tap on "Your week is ready" (FR-BRF-003.2). The notification carries only a route, so there
/// is nothing to read from it: the tap just opens the Week tab, which reads the calendar at that moment.
/// A tap that arrives before the screen exists (a cold start from the notification) is kept until it attaches.
@MainActor
public final class BriefingTapRouter: NSObject, UNUserNotificationCenterDelegate {
    private var pendingTaps = 0
    private var onTap: (@MainActor () -> Void)?

    public nonisolated override init() { super.init() }

    /// The shell registers how a tap opens the briefing; taps that came earlier are delivered now.
    public func attach(_ handler: @escaping @MainActor () -> Void) {
        onTap = handler
        while pendingTaps > 0 {
            pendingTaps -= 1
            handler()
        }
    }

    func receive(identifier: String) {
        guard identifier == BriefingReminder.identifier else { return }
        if let onTap { onTap() } else { pendingTaps += 1 }
    }

    public nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
    ) async {
        let identifier = response.notification.request.identifier
        await receive(identifier: identifier)
    }

    /// A reminder that fires while the app is open still shows as a banner.
    public nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
