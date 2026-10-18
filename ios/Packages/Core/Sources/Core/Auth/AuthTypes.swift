import Foundation

/// Entra app roles (ADR-003). The API is the authority; the UI only hides what the API would deny.
public enum Role: String, Sendable, CaseIterable, Codable {
    case communicator = "Communicator"
    case manager = "Manager"
    case employee = "Employee"
}

/// Identity as returned by `GET /v1/me`. Never contains a token.
public struct Session: Sendable, Equatable {
    public let oid: String
    public let displayName: String
    public let upn: String
    public let roles: Set<Role>
    public let tenantID: String

    public init(oid: String, displayName: String, upn: String, roles: Set<Role>, tenantID: String) {
        self.oid = oid
        self.displayName = displayName
        self.upn = upn
        self.roles = roles
        self.tenantID = tenantID
    }

    public func has(_ role: Role) -> Bool { roles.contains(role) }

    /// Highest-privilege role first, for the "name + role" line on the home screen.
    public var primaryRole: Role {
        [Role.communicator, .manager, .employee].first(where: roles.contains) ?? .employee
    }
}

public enum AuthFailure: Sendable, Equatable {
    /// Wrong tenant, disabled or unassigned account.
    case accountNotAllowed
    case misconfigured
    case generic
}

public enum AuthError: Error, Sendable, Equatable {
    case cancelled
    case offline
    /// Silent refresh is impossible; the user has to sign in again.
    case interactionRequired
    case failed(AuthFailure)
}

/// Sign-in boundary. The MSAL implementation lives in the app target; tests use `StubAuthService`.
/// Tokens never leave this boundary except as the short-lived bearer from `accessToken()`.
public protocol AuthService: Sendable {
    /// Whether an account is cached (Keychain) and could be refreshed silently.
    func hasCachedAccount() async -> Bool
    func signIn() async throws
    /// Silent only. Throws `.interactionRequired` when the user must sign in again.
    func accessToken() async throws -> String
    func signOut() async throws
}

public protocol MeService: Sendable {
    func me(accessToken: String) async throws -> Session
}
