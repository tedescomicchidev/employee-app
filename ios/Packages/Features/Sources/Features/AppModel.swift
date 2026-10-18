import Core
import Observation

/// Auth state machine for the app shell. Drives sign-in, role loading, silent refresh,
/// re-sign-in and sign-out (FR-AUTH-001, -002, -005).
@MainActor @Observable
public final class AppModel {
    public enum Phase: Equatable {
        case launching
        case signedOut
        case signingIn
        case loadingProfile
        case signedIn(Session)
    }

    public enum Issue: Equatable {
        case cancelled, offline, failed, notAllowed, misconfigured, unavailable
    }

    public private(set) var phase: Phase = .launching
    public private(set) var issue: Issue?
    /// Signed in, but the refresh token is gone: show the "Sign in again" sheet, keep drafts.
    public var needsReauth = false
    /// Last refresh failed for lack of network; the cached session stays on screen.
    public private(set) var isOffline = false
    public private(set) var isReauthenticating = false

    private let auth: any AuthService
    private let meService: any MeService
    private let cleaner: SessionCleaner

    public init(auth: any AuthService, me: any MeService, cleaner: SessionCleaner) {
        self.auth = auth
        self.meService = me
        self.cleaner = cleaner
    }

    public var session: Session? {
        if case let .signedIn(session) = phase { session } else { nil }
    }

    /// Restore a cached account silently; otherwise show sign-in.
    public func start() async {
        guard phase == .launching else { return }
        if await auth.hasCachedAccount() {
            phase = .loadingProfile
            await loadProfile()
        } else {
            phase = .signedOut
        }
    }

    public func signIn() async {
        guard phase != .signingIn else { return }
        issue = nil
        phase = .signingIn
        do {
            try await auth.signIn()
            phase = .loadingProfile
            await loadProfile()
        } catch {
            phase = .signedOut
            issue = Self.issue(for: error)
        }
    }

    /// Re-fetch identity and roles. Keeps the current session on screen while it runs.
    public func reload() async {
        guard session != nil else { return }
        await loadProfile()
    }

    /// "Sign in again" sheet action. Drafts are untouched.
    public func reauthenticate() async {
        guard !isReauthenticating else { return }
        isReauthenticating = true
        defer { isReauthenticating = false }
        do {
            try await auth.signIn()
            needsReauth = false
            await loadProfile()
        } catch AuthError.cancelled {
            // Sheet stays; the user can try again.
        } catch {
            issue = Self.issue(for: error)
        }
    }

    /// Clears tokens, cached data, notifications and conversation state.
    public func signOut() async {
        try? await auth.signOut()
        await cleaner.clearAll()
        needsReauth = false
        isOffline = false
        issue = nil
        phase = .signedOut
    }

    private func loadProfile() async {
        do {
            let token = try await auth.accessToken()
            let session = try await meService.me(accessToken: token)
            isOffline = false
            needsReauth = false
            phase = .signedIn(session)
        } catch AuthError.interactionRequired {
            if session != nil { needsReauth = true } else { phase = .signedOut }
        } catch AuthError.offline where session != nil {
            isOffline = true
        } catch AuthError.failed(.accountNotAllowed) {
            // The API refused this account (wrong tenant, no role assignment). Drop the cached account.
            try? await auth.signOut()
            await cleaner.clearAll()
            phase = .signedOut
            issue = .notAllowed
        } catch {
            if session != nil {
                isOffline = Self.issue(for: error) == .offline
            } else {
                phase = .signedOut
                issue = Self.issue(for: error)
            }
        }
    }

    private static func issue(for error: Error) -> Issue {
        switch error as? AuthError {
        case .cancelled: .cancelled
        case .offline: .offline
        case .failed(.accountNotAllowed): .notAllowed
        case .failed(.misconfigured): .misconfigured
        case .failed(.unavailable): .unavailable
        default: .failed
        }
    }
}
