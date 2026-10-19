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
    public let vacation: any VacationService
    public let vacationCache: VacationCache
    /// Business "now"; fixed in screenshot and UI-test runs so dates in the fixtures stay in the future.
    public let clock: @Sendable () -> Date
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
    /// Screenshots: open the vacation request flow (or the holidays list) at launch and drive it.
    public var vacationAutopilot: VacationAutopilot?
    /// Screenshots and UI tests: start on the vacation tab.
    public var startOnVacation = false
    #endif

    public init(
        auth: any AuthService,
        me: any MeService,
        cleaner: SessionCleaner = SessionCleaner(),
        drafts: DraftStore = DraftStore(),
        mode: ModeStore,
        announcements: any AnnouncementService = UnconfiguredAnnouncementService(),
        feedCache: FeedCache = FeedCache(),
        vacation: any VacationService = UnconfiguredVacationService(),
        vacationCache: VacationCache = VacationCache(),
        clock: @escaping @Sendable () -> Date = { Date() },
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
        self.vacation = vacation
        self.vacationCache = vacationCache
        self.clock = clock
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

#if DEBUG
/// Drives the vacation flow without taps so `screenshot.sh` can capture each state (FR-VAC-001/002/006).
public enum VacationAutopilot: String, Sendable {
    case requestOK, requestOverlap, reviewOK, reviewInsufficient, reviewSuccess, holidays, mine, detail, cancelDialog

    /// The dates the autopilot selects, as ISO strings.
    var range: (String, String)? {
        switch self {
        case .requestOK, .reviewOK, .reviewSuccess: ("2026-12-28", "2027-01-05")
        case .requestOverlap: ("2026-11-11", "2026-11-13")
        case .reviewInsufficient: ("2026-11-23", "2026-12-11")
        case .holidays, .mine, .detail, .cancelDialog: nil
        }
    }
}
#endif
