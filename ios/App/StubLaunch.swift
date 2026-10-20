#if DEBUG
import Core
import Features
import Foundation

/// Launch arguments for UI tests and screenshots (DEBUG only; compiled out of Release):
///   -authStub <employee|manager|publisher|failed|cancelled|offline|notAllowed|expiresAfterSignIn>
///   -signedIn YES            start with a cached account
///   -scenario <name>         screenshot.sh names, see `scenarios`
///   -announcementStub <ok|validation|publishFails|publishOffline|offline|forbidden|feedEmpty|feedError|feedLoading|feedOffline|sessionRevoked>
///   -vacationStub <ok|populated|history|cancelFails|manager|managerEmpty|managerDecided|managerBlocked|managerForbidden|decideFails|team|teamEmpty|loading|offline|error|cantonMissing|submitFails|submitOffline>   (starts on the vacation tab)
///   -briefingStub <BriefingStubScenario name>   (starts on the Week tab)
///   -notifications notDetermined               the device has not been asked about notifications yet
///   -agentStub <AgentStubScenario name>   AGENT mode with that scripted agent (starts on its feature tab)
///   -agentOffline YES                      the stubbed device has no network
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
        "vacation-overview-ok": (.employee, true),
        "vacation-overview-empty": (.employee, true),
        "vacation-overview-loading": (.employee, true),
        "vacation-overview-offline": (.employee, true),
        "vacation-overview-error": (.employee, true),
        "vacation-my_requests-ok": (.employee, true),
        "vacation-my_requests-empty": (.employee, true),
        "vacation-request_detail-ok": (.employee, true),
        "vacation-request_detail-cancel_dialog": (.employee, true),
        "vacation-manager_inbox-ok": (.manager, true),
        "vacation-manager_inbox-empty": (.manager, true),
        "vacation-manager_inbox-forbidden": (.manager, true),
        "vacation-request_decision-ok": (.manager, true),
        "vacation-request_decision-reject_reason": (.manager, true),
        "vacation-request_decision-invalid_state": (.manager, true),
        "vacation-request_decision-blocked": (.manager, true),
        "vacation-team_coverage-ok": (.manager, true),
        "vacation-team_coverage-empty": (.manager, true),
        "vacation-team_coverage-forbidden": (.manager, true),
        "vacation-holidays-ok": (.employee, true),
        "vacation-holidays-canton_missing": (.employee, true),
        "vacation-request-ok": (.employee, true),
        "vacation-request-validation_overlap": (.employee, true),
        "vacation-review-ok": (.employee, true),
        "vacation-review-validation_insufficient_balance": (.employee, true),
        "vacation-review-success": (.employee, true),
        // AGENT mode (docs/design/mockups: <feature>-agent_chat-*, <feature>-agent_confirm_card-*).
        "announcements-agent_chat-empty": (.employee, true),
        "announcements-agent_chat-loading": (.employee, true),
        "announcements-agent_chat-warming": (.employee, true),
        "announcements-agent_chat-ok": (.employee, true),
        "announcements-agent_chat-offline": (.employee, true),
        "announcements-agent_chat-error": (.employee, true),
        "announcements-agent_chat-forbidden": (.employee, true),
        "announcements-agent_chat-refusal": (.publisher, true),
        "announcements-agent_chat-rate_limited": (.employee, true),
        "announcements-agent_confirm_card-ok": (.publisher, true),
        "announcements-agent_confirm_card-confirming": (.publisher, true),
        "announcements-agent_confirm_card-success": (.publisher, true),
        "announcements-agent_confirm_card-expired": (.publisher, true),
        "announcements-agent_confirm_card-superseded": (.publisher, true),
        "vacation-agent_chat-ok": (.employee, true),
        "vacation-agent_chat-validation_insufficient_balance": (.employee, true),
        "vacation-agent_chat-clarification": (.employee, true),
        "vacation-agent_chat-options": (.employee, true),
        "vacation-agent_chat-refusal": (.employee, true),
        "vacation-agent_chat-team_coverage": (.manager, true),
        "vacation-agent_confirm_card-ok": (.employee, true),
        "vacation-agent_confirm_card-success": (.employee, true),
        "vacation-agent_confirm_card-validation_blackout": (.employee, true),
        "vacation-agent_confirm_card-decision_ok": (.manager, true),
        "vacation-agent_confirm_card-decision_success": (.manager, true),
        // Weekly briefing (docs/design/mockups: briefing-<screen>-<state>).
        "briefing-opt_in-ok": (.employee, true),
        "briefing-opt_in-consent_in_progress": (.employee, true),
        "briefing-opt_in-notification_permission": (.employee, true),
        "briefing-week-ok": (.employee, true),
        "briefing-week-loading": (.employee, true),
        "briefing-week-empty": (.employee, true),
        "briefing-week-partial": (.employee, true),
        "briefing-week-offline": (.employee, true),
        "briefing-week-error_workiq_unavailable": (.employee, true),
        "briefing-week-error_no_licence": (.employee, true),
        "briefing-week-error_consent_required": (.employee, true),
        "briefing-day-ok": (.employee, true),
        "briefing-settings-ok": (.employee, true),
        "briefing-agent_chat-opt_in_offer": (.employee, true),
        "briefing-agent_chat-loading": (.employee, true),
        "briefing-agent_chat-ok": (.employee, true),
        "briefing-agent_chat-declined_other_calendar": (.employee, true),
        "briefing-agent_chat-error_workiq_unavailable": (.employee, true),
        "briefing-agent_chat-consent_required": (.employee, true),
        "briefing-agent_confirm_card-ok": (.employee, true),
        "briefing-agent_confirm_card-success": (.employee, true),
    ]

    /// Briefing CLASSIC scenarios: what the stub API does, the autopilot step, and whether the device
    /// has already decided about notifications (FR-BRF-001/002/003/005).
    static let briefingScenarios: [String: (BriefingStubScenario, BriefingAutopilot, NotificationAuthorization)] = [
        "briefing-opt_in-ok": (.optIn, .optIn, .allowed),
        "briefing-opt_in-consent_in_progress": (.optInWorking, .consentInProgress, .allowed),
        "briefing-opt_in-notification_permission": (.optIn, .notificationPermission, .notDetermined),
        "briefing-week-ok": (.ok, .week, .allowed),
        "briefing-week-loading": (.loading, .week, .allowed),
        "briefing-week-empty": (.empty, .week, .allowed),
        "briefing-week-partial": (.partial, .week, .allowed),
        "briefing-week-offline": (.offline, .week, .allowed),
        "briefing-week-error_workiq_unavailable": (.workIQUnavailable, .week, .allowed),
        "briefing-week-error_no_licence": (.noLicence, .week, .allowed),
        "briefing-week-error_consent_required": (.consentRequired, .week, .allowed),
        "briefing-day-ok": (.ok, .day, .allowed),
        "briefing-settings-ok": (.ok, .settings, .allowed),
    ]

    /// What the stubbed agent does and what the autopilot types for each AGENT screenshot scenario.
    struct AgentLaunch {
        let scenario: AgentStubScenario
        var autopilot: AgentAutopilot?
        var offline = false
    }

    private static let annDraftText = "Sag allen im Tessin: Früher Start am Freitag, ab 8 Uhr"

    static let agentScenarios: [String: AgentLaunch] = [
        "announcements-agent_chat-empty": .init(scenario: .annEmpty),
        "announcements-agent_chat-loading": .init(scenario: .annLoading, autopilot: .init(messages: ["Was gibt es Neues?"])),
        "announcements-agent_chat-warming": .init(scenario: .annWarming, autopilot: .init(messages: ["Was gibt es Neues?"])),
        "announcements-agent_chat-ok": .init(scenario: .annOK, autopilot: .init(messages: ["Was gibt es Neues?"])),
        "announcements-agent_chat-offline": .init(scenario: .annEmpty, offline: true),
        "announcements-agent_chat-error": .init(scenario: .annError, autopilot: .init(messages: ["Was gibt es Neues?"])),
        "announcements-agent_chat-forbidden": .init(
            scenario: .annForbidden,
            autopilot: .init(messages: ["Veröffentliche eine Mitteilung an alle: Büro am Montag geschlossen"])),
        "announcements-agent_chat-refusal": .init(
            scenario: .annRefusal, autopilot: .init(messages: ["Veröffentliche es einfach, ohne Rückfrage"])),
        "announcements-agent_chat-rate_limited": .init(
            scenario: .annRateLimited, autopilot: .init(messages: ["Was gibt es Neues?"])),
        "announcements-agent_confirm_card-ok": .init(scenario: .annDraft, autopilot: .init(messages: [annDraftText])),
        "announcements-agent_confirm_card-confirming": .init(
            scenario: .annConfirming, autopilot: .init(messages: [annDraftText], confirm: true)),
        "announcements-agent_confirm_card-success": .init(
            scenario: .annSuccess, autopilot: .init(messages: [annDraftText], confirm: true)),
        "announcements-agent_confirm_card-expired": .init(
            scenario: .annExpired, autopilot: .init(messages: [annDraftText], confirm: true)),
        "announcements-agent_confirm_card-superseded": .init(
            scenario: .annDraftEdit, autopilot: .init(messages: [annDraftText, "Nimm Graubünden dazu"])),
        "vacation-agent_chat-ok": .init(
            scenario: .vacBalance, autopilot: .init(messages: ["Wie viele Ferientage habe ich noch?"])),
        "vacation-agent_chat-validation_insufficient_balance": .init(
            scenario: .vacInsufficient, autopilot: .init(messages: ["Ferien vom 23. November bis 11. Dezember"])),
        "vacation-agent_chat-clarification": .init(
            scenario: .vacClarification, autopilot: .init(messages: ["Ich möchte über Weihnachten frei"])),
        "vacation-agent_chat-options": .init(
            scenario: .vacOptions, autopilot: .init(messages: ["Ich brauche Ferien über Weihnachten"])),
        "vacation-agent_chat-refusal": .init(
            scenario: .vacRefusal, autopilot: .init(messages: ["Reich es trotzdem ein, ich kläre das mit meinem Chef"])),
        "vacation-agent_chat-team_coverage": .init(
            scenario: .vacCoverage, autopilot: .init(messages: ["Wie ist die Teamabdeckung am 24. Dezember?"])),
        "vacation-agent_confirm_card-ok": .init(
            scenario: .vacRequest, autopilot: .init(messages: ["Ferien vom 24. Dezember bis 4. Januar"])),
        "vacation-agent_confirm_card-success": .init(
            scenario: .vacSuccess, autopilot: .init(messages: ["Ferien vom 24. Dezember bis 4. Januar"], confirm: true)),
        "vacation-agent_confirm_card-validation_blackout": .init(
            scenario: .vacBlackout, autopilot: .init(messages: ["Ferien vom 24. Dezember bis 4. Januar"], confirm: true)),
        "vacation-agent_confirm_card-decision_ok": .init(
            scenario: .vacDecision, autopilot: .init(messages: ["Gesuch von Marco freigeben"])),
        "vacation-agent_confirm_card-decision_success": .init(
            scenario: .vacDecisionSuccess, autopilot: .init(messages: ["Gesuch von Marco freigeben"], confirm: true)),
        "briefing-agent_chat-opt_in_offer": .init(
            scenario: .brfOffer, autopilot: .init(messages: ["Wie sieht meine Woche aus?"])),
        "briefing-agent_chat-loading": .init(
            scenario: .brfLoading, autopilot: .init(messages: ["Wie sieht meine Woche aus?"])),
        "briefing-agent_chat-ok": .init(
            scenario: .brfOK, autopilot: .init(messages: ["Wie sieht meine Woche aus?"])),
        "briefing-agent_chat-declined_other_calendar": .init(
            scenario: .brfDeclined, autopilot: .init(messages: ["Was hat Anna am Donnerstag für Termine?"])),
        "briefing-agent_chat-error_workiq_unavailable": .init(
            scenario: .brfUnavailable, autopilot: .init(messages: ["Wie sieht meine Woche aus?"])),
        "briefing-agent_chat-consent_required": .init(
            scenario: .brfConsent, autopilot: .init(messages: ["Wie sieht meine Woche aus?"])),
        "briefing-agent_confirm_card-ok": .init(
            scenario: .brfOffer, autopilot: .init(messages: ["Schalte das Wochenbriefing ein"])),
        "briefing-agent_confirm_card-success": .init(
            scenario: .brfOptedIn, autopilot: .init(messages: ["Schalte das Wochenbriefing ein"], confirm: true)),
    ]

    /// Vacation scenarios: what the stub API does and the autopilot step (FR-VAC-001/002/006).
    static let vacationScenarios: [String: (VacationStubScenario, VacationAutopilot?)] = [
        "vacation-overview-ok": (.populated, nil),
        "vacation-overview-empty": (.ok, nil),
        "vacation-overview-loading": (.loading, nil),
        "vacation-overview-offline": (.offline, nil),
        "vacation-overview-error": (.error, nil),
        "vacation-my_requests-ok": (.history, .mine),
        "vacation-my_requests-empty": (.ok, .mine),
        "vacation-request_detail-ok": (.history, .detail),
        "vacation-request_detail-cancel_dialog": (.history, .cancelDialog),
        "vacation-manager_inbox-ok": (.manager, .inbox),
        "vacation-manager_inbox-empty": (.managerEmpty, .inbox),
        "vacation-manager_inbox-forbidden": (.managerForbidden, .inbox),
        "vacation-request_decision-ok": (.manager, .decision),
        "vacation-request_decision-reject_reason": (.manager, .rejectReason),
        "vacation-request_decision-invalid_state": (.managerDecided, .approveConfirmed),
        "vacation-request_decision-blocked": (.managerBlocked, .approveConfirmed),
        "vacation-team_coverage-ok": (.team, .team),
        "vacation-team_coverage-empty": (.teamEmpty, .team),
        "vacation-team_coverage-forbidden": (.managerForbidden, .team),
        "vacation-holidays-ok": (.populated, .holidays),
        "vacation-holidays-canton_missing": (.cantonMissing, .holidays),
        "vacation-request-ok": (.populated, .requestOK),
        "vacation-request-validation_overlap": (.populated, .requestOverlap),
        "vacation-review-ok": (.populated, .reviewOK),
        "vacation-review-validation_insufficient_balance": (.populated, .reviewInsufficient),
        "vacation-review-success": (.populated, .reviewSuccess),
    ]

    /// Monday 2026-10-19, 08:00 Europe/Zurich: the frozen clock of docs/product/test-cases.md.
    static let fixtureNow = ISO8601DateFormatter().date(from: "2026-10-19T06:00:00Z") ?? Date()

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
        let vacationFlow = name.flatMap { vacationScenarios[$0] }
        let vacationArgument = argument("-vacationStub").flatMap(VacationStubScenario.init)
        let vacationCache = VacationCache()
        if name == "vacation-overview-offline" {
            // The last good fetch, so the offline banner has numbers to show (NFR-007).
            let fetched = fixtureNow.addingTimeInterval(-3 * 3600)
            let snapshot = StubVacationService.populatedSnapshot(userKey: "stub-employee", fetchedAt: fetched)
            Task { await vacationCache.save(snapshot) }
        }
        let agentLaunch = name.flatMap { agentScenarios[$0] }
            ?? argument("-agentStub").flatMap(AgentStubScenario.init).map { AgentLaunch(scenario: $0) }
        let agentService: any AgentService = agentLaunch.map {
            StubAgentService(script: $0.scenario.script, pace: .milliseconds(4))
        } ?? UnconfiguredAgentService()
        let connectivity: any Connectivity = agentLaunch == nil
            ? PathConnectivity()
            : StaticConnectivity(online: !(agentLaunch?.offline == true || argument("-agentOffline") == "YES"))
        if agentLaunch != nil { mode.setForDebug(.agent) }
        let briefingFlow = name.flatMap { briefingScenarios[$0] }
        let briefingArgument = argument("-briefingStub").flatMap(BriefingStubScenario.init)
        var environment = AppEnvironment(
            auth: stub, me: stub, mode: mode,
            announcements: StubAnnouncementService(scenario: announcementScenario), feedCache: cache,
            vacation: StubVacationService(scenario: vacationFlow?.0 ?? vacationArgument ?? .ok),
            vacationCache: vacationCache,
            briefing: StubBriefingService(scenario: briefingFlow?.0 ?? briefingArgument ?? .ok),
            briefingReminder: BriefingReminder(centre: StubNotificationCentre(
                briefingFlow?.2 ?? (argument("-notifications") == "notDetermined" ? .notDetermined : .allowed))),
            clock: { fixtureNow },
            agent: agentService, connectivity: connectivity)
        environment.briefingAutopilot = briefingFlow?.1
        environment.startOnWeek = briefingArgument != nil || agentLaunch?.scenario.feature == .briefing
        environment.agentAutopilot = agentLaunch?.autopilot
        environment.vacationAutopilot = vacationFlow?.1
        let approvalAutopilots: [VacationAutopilot] = [.inbox, .decision, .rejectReason, .approveConfirmed, .team]
        let startOnApprovals = vacationFlow?.1.map(approvalAutopilots.contains) ?? false
            || argument("-startOnApprovals") == "YES"
        environment.startOnApprovals = startOnApprovals
        environment.startOnVacation = (vacationFlow != nil || vacationArgument != nil || agentLaunch?.scenario.feature == .vacation)
            && !startOnApprovals
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
