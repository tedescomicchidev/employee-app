import Foundation
import UserNotifications

/// What the scheduler needs from the system's notification centre, so tests can stand in for it.
public protocol NotificationCentre: Sendable {
    func authorization() async -> NotificationAuthorization
    func requestAuthorization() async -> Bool
    /// The weekly request: the system centre builds the `UNNotificationRequest` itself, so no
    /// non-Sendable system object crosses an isolation boundary.
    func scheduleWeekly(identifier: String, title: String) async throws
    func cancel(identifiers: [String]) async
    func pendingIdentifiers() async -> [String]
}

public enum NotificationAuthorization: Sendable, Equatable {
    case notDetermined, denied, allowed
}

/// The real centre. `UNUserNotificationCenter` is thread-safe; the wrapper holds no state.
/// Outside an app bundle (a SwiftPM test host) the system centre does not exist and asking for it
/// raises, so there it answers "denied" and does nothing.
public struct SystemNotificationCentre: NotificationCentre {
    public init() {}

    private static var isAvailable: Bool {
        Bundle.main.bundleURL.pathExtension == "app" && Bundle.main.bundleIdentifier != nil
    }

    public func authorization() async -> NotificationAuthorization {
        guard Self.isAvailable else { return .denied }
        return switch await UNUserNotificationCenter.current().notificationSettings().authorizationStatus {
        case .notDetermined: .notDetermined
        case .denied: .denied
        case .authorized, .provisional, .ephemeral: .allowed
        @unknown default: .denied
        }
    }

    public func requestAuthorization() async -> Bool {
        guard Self.isAvailable else { return false }
        return (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    public func scheduleWeekly(identifier: String, title: String) async throws {
        guard Self.isAvailable else { return }
        try await UNUserNotificationCenter.current().add(BriefingReminder.request(title: title))
    }

    public func cancel(identifiers: [String]) async {
        guard Self.isAvailable else { return }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    public func pendingIdentifiers() async -> [String] {
        guard Self.isAvailable else { return [] }
        return await UNUserNotificationCenter.current().pendingNotificationRequests().map(\.identifier)
    }
}

/// FR-BRF-003: a local notification every Monday at 07:00 Europe/Zurich that says only "Your week is
/// ready". It carries no calendar content, because it is created before anything is read (Work IQ output
/// cannot be generated unattended, ADR-008). Tapping it opens the briefing, which is generated then.
public struct BriefingReminder: Sendable {
    public static let identifier = "briefing.weekly"
    /// The tap's route; nothing else travels in the notification.
    public static let routeKey = "route"
    public static let routeValue = "briefing"

    private let centre: any NotificationCentre

    public init(centre: any NotificationCentre = SystemNotificationCentre()) {
        self.centre = centre
    }

    /// Monday (2 in the Gregorian calendar) 07:00 in Zurich, repeating. A calendar trigger follows the
    /// daylight-saving change, so the notification stays at 07:00 local time all year.
    public static func trigger() -> UNCalendarNotificationTrigger {
        var components = DateComponents()
        components.timeZone = TimeZone(identifier: "Europe/Zurich")
        components.weekday = 2
        components.hour = 7
        components.minute = 0
        return UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
    }

    public static func request(title: String) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = title
        content.sound = .default
        content.userInfo = [routeKey: routeValue]
        return UNNotificationRequest(identifier: identifier, content: content, trigger: trigger())
    }

    public func authorization() async -> NotificationAuthorization { await centre.authorization() }

    /// In-context ask, after the opt-in. Returns whether notifications are now allowed.
    public func requestAuthorization() async -> Bool { await centre.requestAuthorization() }

    /// Schedules the weekly reminder if the user allowed notifications. Replaces the pending one, so it is
    /// safe to call on every launch. Returns whether a reminder is now scheduled.
    @discardableResult
    public func schedule(title: String) async -> Bool {
        guard await centre.authorization() == .allowed else { return false }
        await centre.cancel(identifiers: [Self.identifier])
        do {
            try await centre.scheduleWeekly(identifier: Self.identifier, title: title)
            return true
        } catch {
            return false
        }
    }

    /// Opt-out and sign-out (FR-BRF-003.3).
    public func cancel() async { await centre.cancel(identifiers: [Self.identifier]) }

    public func isScheduled() async -> Bool { await centre.pendingIdentifiers().contains(Self.identifier) }
}
