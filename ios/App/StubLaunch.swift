#if DEBUG
import Core
import Features
import Foundation

/// Launch arguments for UI tests and screenshots (DEBUG only; compiled out of Release):
///   -authStub <employee|manager|publisher|failed|cancelled|offline|notAllowed|expiresAfterSignIn>
///   -signedIn YES            start with a cached account
///   -scenario <name>         screenshot.sh names, see `scenarios`
///   -announcementStub <ok|validation|publishFails|publishOffline|offline|forbidden|feedEmpty|feedError|feedLoading|feedOffline>
enum StubLaunch {
    /// Scenarios that tap "Sign in" at launch, to show the failure banner.
    static let autoSignIn: Set<String> = ["signin-failed", "signin-cancelled", "signin-offline", "signin-not-allowed"]

    static let scenarios: [String: (StubScenario, signedIn: Bool)] = [
        "launch": (.employee, false),
        "signin": (.employee, false),
        "signin-failed": (.failed, false),
        "signin-cancelled": (.cancelled, false),
        "signin-offline": (.offline, false),
        "signin-not-allowed": (.notAllowed, false),
        "home-employee": (.employee, true),
        "home-manager": (.manager, true),
        "home-publisher": (.publisher, true),
        "compose-ok": (.publisher, true),
        "compose-validation": (.publisher, true),
        "review-ok": (.publisher, true),
        "review-success": (.publisher, true),
        "review-error": (.publisher, true),
        "review-offline": (.publisher, true),
        "audience-ok": (.publisher, true),
        "feed-ok": (.employee, true),
        "feed-loading": (.employee, true),
        "feed-empty": (.employee, true),
        "feed-error": (.employee, true),
        "feed-offline": (.employee, true),
        "detail-ok": (.employee, true),
    ]

    /// Feed scenarios: what the stub API does, and the announcement to open at launch (FR-ANN-003).
    static let feedScenarios: [String: (AnnouncementStubScenario, open: String?)] = [
        "feed-ok": (.ok, nil), "feed-loading": (.feedLoading, nil), "feed-empty": (.feedEmpty, nil),
        "feed-error": (.feedError, nil), "feed-offline": (.feedOffline, nil), "detail-ok": (.ok, "a4"),
    ]

    /// Publish-flow scenarios: autopilot step and what the stub API does (FR-ANN-001).
    static let announcementScenarios: [String: (AnnouncementAutopilot, AnnouncementStubScenario)] = [
        "compose-ok": (.composeOK, .ok),
        "compose-validation": (.composeValidation, .ok),
        "review-ok": (.reviewOK, .ok),
        "review-success": (.reviewSuccess, .ok),
        "review-error": (.reviewError, .publishFails),
        "review-offline": (.reviewOffline, .publishOffline),
        "audience-ok": (.audienceOK, .ok),
    ]

    @MainActor
    static func environment(mode: ModeStore, arguments: [String] = ProcessInfo.processInfo.arguments) -> AppEnvironment? {
        func argument(_ name: String) -> String? {
            arguments.firstIndex(of: name).flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
        }
        var resolved: (StubScenario, signedIn: Bool)?
        if let name = argument("-scenario"), let known = scenarios[name] { resolved = known }
        if let name = argument("-authStub"), let scenario = StubScenario(rawValue: name) {
            resolved = (scenario, argument("-signedIn") == "YES")
        }
        guard let (scenario, signedIn) = resolved else { return nil }
        let stub = StubAuthService(scenario: scenario, signedIn: signedIn)
        let name = argument("-scenario")
        let flow = name.flatMap { announcementScenarios[$0] }
        let feedFlow = name.flatMap { feedScenarios[$0] }
        let announcementScenario = flow?.1 ?? feedFlow?.0
            ?? argument("-announcementStub").flatMap(AnnouncementStubScenario.init) ?? .ok
        let cache = FeedCache()
        if name == "feed-offline" {
            // The last good fetch, so the offline banner has something to show (FR-ANN-003.3).
            let fetched = Date().addingTimeInterval(-3 * 3600)
            let snapshot = FeedSnapshot(
                userKey: "stub-employee", fetchedAt: fetched, items: StubAnnouncementService.feed(now: fetched))
            Task { await cache.save(snapshot) }
        }
        var environment = AppEnvironment(
            auth: stub, me: stub, mode: mode,
            announcements: StubAnnouncementService(scenario: announcementScenario), feedCache: cache)
        environment.openAnnouncementOnLaunch = feedFlow?.open
        environment.announcementAutopilot = flow?.0
        environment.autoSignIn = argument("-scenario").map(autoSignIn.contains) ?? false
        environment.debug = DebugHooks(
            useScenario: { await stub.use($0) },
            expireSession: { await stub.expireSession() })
        return environment
    }
}
#endif
