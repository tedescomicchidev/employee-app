import Core
import Features
import Foundation
import os
import UserNotifications

/// Builds the dependency graph. DEBUG builds can swap in the stubbed auth layer via launch arguments.
@MainActor
enum AppBootstrap {
    private static let logger = Logger(subsystem: "ch.example.employee", category: "auth")

    static func makeEnvironment() -> AppEnvironment {
        let mode = ModeStore()
        #if DEBUG
        if let environment = StubLaunch.environment(mode: mode) { return configure(environment) }
        #endif
        guard let config = AuthConfiguration.load() else {
            return unavailable(.misconfigured, mode: mode)
        }
        do {
            let msal = try MSALAuthService(configuration: config)
            let events = URLSessionEventSink(baseURL: config.apiBaseURL) { try await msal.accessToken() }
            return configure(AppEnvironment(
                auth: msal, me: URLSessionMeService(baseURL: config.apiBaseURL), mode: mode,
                announcements: URLSessionAnnouncementService(baseURL: config.apiBaseURL),
                feedCache: FeedCache(fileURL: FeedCache.defaultFileURL()),
                vacation: URLSessionVacationService(baseURL: config.apiBaseURL),
                vacationCache: VacationCache(fileURL: VacationCache.defaultFileURL()),
                events: events, taskContext: taskContext(),
                agent: URLSessionAgentService(baseURL: config.apiBaseURL)), clearing: events)
        } catch {
            // Typically "Failed to retrieve teamId from keychain" (-42008) in an unsigned build.
            // Codes only: no tokens, no identifiers.
            let nsError = error as NSError
            let internalCode = nsError.userInfo["MSALInternalErrorCodeKey"] ?? "-"
            logger.error("MSAL init failed: \(nsError.domain, privacy: .public) \(nsError.code) internal \(String(describing: internalCode), privacy: .public)")
            return unavailable(.unavailable, mode: mode)
        }
    }

    private static func unavailable(_ failure: AuthFailure, mode: ModeStore) -> AppEnvironment {
        let service = UnconfiguredAuthService(failure: failure)
        return configure(AppEnvironment(auth: service, me: service, mode: mode))
    }

    /// Sign-out hooks (FR-AUTH-005): drafts, scheduled notifications, cached responses.
    /// Stopgap participant id: a random per-install uuid. The server-issued, deletable mapping
    /// (`GET /v1/me/participant`, ADR-009) is not built yet.
    private static func taskContext() -> TaskContext {
        let key = "experiment.participant_id"
        let stored = UserDefaults.standard.string(forKey: key).flatMap(UUID.init)
        let id = stored ?? UUID()
        if stored == nil { UserDefaults.standard.set(id.uuidString, forKey: key) }
        return TaskContext(
            participantId: id,
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev",
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            locale: Locale.current.language.languageCode?.identifier ?? "en")
    }

    private static func configure(
        _ environment: AppEnvironment, clearing events: URLSessionEventSink? = nil
    ) -> AppEnvironment {
        var extra: [SessionCleaner.Hook] = [
            { UNUserNotificationCenter.current().removeAllPendingNotificationRequests() },
            { URLCache.shared.removeAllCachedResponses() },
        ]
        if let events { extra.append { await events.clear() } }
        Task { [extra] in await environment.registerSessionCleanup(also: extra) }
        return environment
    }
}
