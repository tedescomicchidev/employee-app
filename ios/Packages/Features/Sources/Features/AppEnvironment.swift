import Core

#if DEBUG
/// Debug-menu hooks into the stubbed auth layer.
public struct DebugHooks: Sendable {
    public let useScenario: @Sendable (StubScenario) async -> Void
    public let expireSession: @Sendable () async -> Void

    public init(
        useScenario: @escaping @Sendable (StubScenario) async -> Void,
        expireSession: @escaping @Sendable () async -> Void
    ) {
        self.useScenario = useScenario
        self.expireSession = expireSession
    }
}
#endif

/// Everything the shell needs, injected by the app target (real MSAL or a stub).
public struct AppEnvironment: Sendable {
    public let auth: any AuthService
    public let me: any MeService
    public let cleaner: SessionCleaner
    public let drafts: DraftStore
    public let mode: ModeStore
    #if DEBUG
    public var debug: DebugHooks?
    /// Screenshots: tap "Sign in" at launch so failure states are visible.
    public var autoSignIn = false
    #endif

    public init(
        auth: any AuthService,
        me: any MeService,
        cleaner: SessionCleaner = SessionCleaner(),
        drafts: DraftStore = DraftStore(),
        mode: ModeStore
    ) {
        self.auth = auth
        self.me = me
        self.cleaner = cleaner
        self.drafts = drafts
        self.mode = mode
    }
}
