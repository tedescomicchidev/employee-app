import Core
import Foundation

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
    public let announcements: any AnnouncementService
    public let feedCache: FeedCache
    public let events: any EventSink
    public let taskContext: TaskContext
    #if DEBUG
    public var debug: DebugHooks?
    /// Screenshots: tap "Sign in" at launch so failure states are visible.
    public var autoSignIn = false
    /// Screenshots: open the publish flow at launch and drive it to this state.
    public var announcementAutopilot: AnnouncementAutopilot?
    /// Screenshots: open this announcement in the feed at launch.
    public var openAnnouncementOnLaunch: String?
    #endif

    public init(
        auth: any AuthService,
        me: any MeService,
        cleaner: SessionCleaner = SessionCleaner(),
        drafts: DraftStore = DraftStore(),
        mode: ModeStore,
        announcements: any AnnouncementService = UnconfiguredAnnouncementService(),
        feedCache: FeedCache = FeedCache(),
        events: any EventSink = MemoryEventSink(),
        taskContext: TaskContext = TaskContext(participantId: UUID())
    ) {
        self.auth = auth
        self.me = me
        self.cleaner = cleaner
        self.drafts = drafts
        self.mode = mode
        self.announcements = announcements
        self.feedCache = feedCache
        self.events = events
        self.taskContext = taskContext
    }
}

#if DEBUG
/// Drives the publish flow without taps so `screenshot.sh` can capture each state.
public enum AnnouncementAutopilot: String, Sendable {
    case composeOK, composeValidation, reviewOK, reviewSuccess, reviewError, reviewOffline, audienceOK

    var prefill: AnnouncementDraft {
        switch self {
        case .composeValidation:
            AnnouncementDraft(title: "", body: "Ab Freitag öffnen alle Filialen um 8 Uhr.", language: .de)
        case .audienceOK:
            AnnouncementDraft(
                title: "Früher Start am Freitag", body: "Ab Freitag öffnen alle Filialen um 8 Uhr.", language: .de,
                audience: AudienceSelection(everyone: false, regions: ["IT"], roles: ["Manager"]))
        default:
            AnnouncementDraft(
                title: "Früher Start am Freitag",
                body: "Ab Freitag öffnen alle Filialen um 8 Uhr. Bitte plant die Frühschicht entsprechend.",
                language: .de)
        }
    }
}
#endif
