#if DEBUG
import Foundation

/// Scenario-driven stub for UI tests, screenshots and the debug menu. Compiled only in DEBUG.
public enum StubScenario: String, Sendable, CaseIterable {
    case employee, manager, publisher
    case failed, cancelled, offline, notAllowed
    case expiresAfterSignIn
}

public extension Session {
    static func stub(_ scenario: StubScenario) -> Session {
        switch scenario {
        case .manager:
            Session(oid: "stub-manager", displayName: "Maria Keller", upn: "mgr1@example.test",
                    roles: [.manager, .employee], tenantID: "stub-tenant")
        case .publisher:
            Session(oid: "stub-ceo", displayName: "Reto Brunner", upn: "ceo@example.test",
                    roles: [.communicator, .manager, .employee], tenantID: "stub-tenant")
        default:
            Session(oid: "stub-employee", displayName: "Anna Muster", upn: "emp1@example.test",
                    roles: [.employee], tenantID: "stub-tenant")
        }
    }
}

public actor StubAuthService: AuthService, MeService {
    private var scenario: StubScenario
    private var signedIn: Bool
    private var expired = false
    private var issued = 0

    public init(scenario: StubScenario, signedIn: Bool = false) {
        self.scenario = scenario
        self.signedIn = signedIn
    }

    public func hasCachedAccount() -> Bool { signedIn }

    public func signIn() throws {
        switch scenario {
        case .failed: throw AuthError.failed(.generic)
        case .notAllowed: throw AuthError.failed(.accountNotAllowed)
        case .cancelled: throw AuthError.cancelled
        case .offline: throw AuthError.offline
        default:
            signedIn = true
            expired = false
            issued = 0
        }
    }

    public func accessToken() throws -> String {
        guard signedIn, !expired else { throw AuthError.interactionRequired }
        // `expiresAfterSignIn`: the first token (for /me) works, the next refresh needs a new sign-in.
        if scenario == .expiresAfterSignIn, issued >= 1 { throw AuthError.interactionRequired }
        issued += 1
        return "stub-token"
    }

    public func signOut() { signedIn = false }

    public func me(accessToken: String) -> Session { .stub(scenario) }

    /// Debug menu: seed a different role or outcome without restarting.
    public func use(_ scenario: StubScenario) { self.scenario = scenario }

    /// Debug menu: simulate an expired or revoked refresh token.
    public func expireSession() { expired = true }
}
#endif
