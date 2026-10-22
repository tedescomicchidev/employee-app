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
    /// The weekly briefing (FR-BRF-*): `api/` reads Work IQ on behalf of the user; the app never calls Work IQ.
    public let briefing: any BriefingService
    /// FR-BRF-003: the local Monday 07:00 reminder.
    public let briefingReminder: BriefingReminder
    /// Where a tap on the Monday notification is delivered (the app target installs it as the delegate).
    public let briefingTaps: BriefingTapRouter
    /// Business "now"; fixed in screenshot and UI-test runs so dates in the fixtures stay in the future.
    public let clock: @Sendable () -> Date
    public let events: any EventSink
    public let taskContext: TaskContext
    /// AGENT mode: chat turns, confirm cards and confirmations, always through `api/` (never Foundry).
    public let agent: any AgentService
    public let connectivity: any Connectivity
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
    /// Screenshots and UI tests: start on the manager's approvals tab.
    public var startOnApprovals = false
    /// Screenshots and UI tests: send these messages in the agent chat at launch, then optionally tap confirm.
    public var agentAutopilot: AgentAutopilot?
    /// Screenshots and UI tests: start on the briefing (Week) tab and drive it to this state.
    public var briefingAutopilot: BriefingAutopilot?
    /// Screenshots and UI tests: start on the Week tab (the briefing agent's chat in AGENT mode).
    public var startOnWeek = false
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
        briefing: any BriefingService = UnconfiguredBriefingService(),
        briefingReminder: BriefingReminder = BriefingReminder(),
        briefingTaps: BriefingTapRouter = BriefingTapRouter(),
        clock: @escaping @Sendable () -> Date = { Date() },
        events: any EventSink = MemoryEventSink(),
        taskContext: TaskContext = TaskContext(participantId: UUID()),
        agent: any AgentService = UnconfiguredAgentService(),
        connectivity: any Connectivity = PathConnectivity()
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
        self.briefing = briefing
        self.briefingReminder = briefingReminder
        self.briefingTaps = briefingTaps
        self.clock = clock
        self.events = events
        self.taskContext = taskContext
        self.agent = agent
        self.connectivity = connectivity
    }

    /// What sign-out removes (FR-AUTH-005): unsent drafts, the cached feed and the cached balance and
    /// requests, then whatever the app target owns (scheduled notifications, URL cache, queued events,
    /// agent conversation state, which lives in the chat models and goes with the signed-in screens).
    /// A re-sign-in after expiry does not run these.
    public func registerSessionCleanup(also extra: [SessionCleaner.Hook] = []) async {
        let drafts = drafts, feedCache = feedCache, vacationCache = vacationCache
        let reminder = briefingReminder
        await cleaner.register { await drafts.clear() }
        await cleaner.register { await reminder.cancel() }  // FR-BRF-003.3
        await cleaner.register { await feedCache.clear() }
        await cleaner.register { await vacationCache.clear() }
        for hook in extra { await cleaner.register(hook) }
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
    /// Manager screens: the inbox, a decision, the reject sheet, an approval that fails.
    case inbox, decision, rejectReason, approveConfirmed, team

    /// The dates the autopilot selects, as ISO strings.
    var range: (String, String)? {
        switch self {
        case .requestOK, .reviewOK, .reviewSuccess: ("2026-12-28", "2027-01-05")
        case .requestOverlap: ("2026-11-11", "2026-11-13")
        case .reviewInsufficient: ("2026-11-23", "2026-12-11")
        case .holidays, .mine, .detail, .cancelDialog, .inbox, .decision, .rejectReason, .approveConfirmed, .team: nil
        }
    }
}
#endif

#if DEBUG
/// Drives the agent chat without taps so `screenshot.sh` can capture each state (AGENT UX).
public struct AgentAutopilot: Sendable, Equatable {
    public var messages: [String]
    /// Tap the confirm card after the messages (the last card).
    public var confirm: Bool
    /// Pick the first offered range after the messages.
    public var chooseFirstOption: Bool

    public init(messages: [String], confirm: Bool = false, chooseFirstOption: Bool = false) {
        self.messages = messages
        self.confirm = confirm
        self.chooseFirstOption = chooseFirstOption
    }
}
#endif

#if DEBUG
/// Drives the briefing screens without taps so `screenshot.sh` can capture each state (FR-BRF-*).
public enum BriefingAutopilot: String, Sendable {
    case optIn, consentInProgress, notificationPermission, week, day, settings
}
#endif
