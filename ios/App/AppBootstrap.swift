import Core
import Features
import Foundation
import UserNotifications

/// Builds the dependency graph. DEBUG builds can swap in the stubbed auth layer via launch arguments.
@MainActor
enum AppBootstrap {
    static func makeEnvironment() -> AppEnvironment {
        let mode = ModeStore()
        #if DEBUG
        if let environment = StubLaunch.environment(mode: mode) { return configure(environment) }
        #endif
        guard let config = AuthConfiguration.load(), let msal = try? MSALAuthService(configuration: config) else {
            let unconfigured = UnconfiguredAuthService()
            return configure(AppEnvironment(auth: unconfigured, me: unconfigured, mode: mode))
        }
        return configure(AppEnvironment(
            auth: msal, me: URLSessionMeService(baseURL: config.apiBaseURL), mode: mode))
    }

    /// Sign-out hooks (FR-AUTH-005): drafts, scheduled notifications, cached responses.
    private static func configure(_ environment: AppEnvironment) -> AppEnvironment {
        let drafts = environment.drafts
        let cleaner = environment.cleaner
        Task {
            await cleaner.register { await drafts.clear() }
            await cleaner.register { UNUserNotificationCenter.current().removeAllPendingNotificationRequests() }
            await cleaner.register { URLCache.shared.removeAllCachedResponses() }
        }
        return environment
    }
}
