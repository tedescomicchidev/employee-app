#if DEBUG
import Core
import Features
import Foundation

/// Launch arguments for UI tests and screenshots (DEBUG only; compiled out of Release):
///   -authStub <employee|manager|publisher|failed|cancelled|offline|notAllowed|expiresAfterSignIn>
///   -signedIn YES            start with a cached account
///   -scenario <name>         screenshot.sh names, see `scenarios`
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
        var environment = AppEnvironment(auth: stub, me: stub, mode: mode)
        environment.autoSignIn = argument("-scenario").map(autoSignIn.contains) ?? false
        environment.debug = DebugHooks(
            useScenario: { await stub.use($0) },
            expireSession: { await stub.expireSession() })
        return environment
    }
}
#endif
