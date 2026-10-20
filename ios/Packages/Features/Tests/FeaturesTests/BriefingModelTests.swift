import Core
import Foundation
import Testing
@testable import Features

#if DEBUG
private func day(_ iso: String) -> CalendarDay { CalendarDay(iso: iso)! }

/// Scriptable service: records the order of calls and fails on demand.
private actor FakeBriefing: BriefingService {
    var calls: [String] = []
    var optedIn: Bool
    var weekResult: Result<BriefingWeek, BriefingError> = .success(StubBriefingService.week(.ok))
    var setError: BriefingError?
    var statusError: BriefingError?
    /// A week that does not answer until released (Work IQ taking its time).
    var holdWeek = false
    private var release: CheckedContinuation<Void, Never>?

    init(optedIn: Bool = true) { self.optedIn = optedIn }

    func set(week result: Result<BriefingWeek, BriefingError>) { weekResult = result }
    func set(setError error: BriefingError?) { setError = error }
    func set(statusError error: BriefingError?) { statusError = error }
    func hold() { holdWeek = true }
    func letGo() { holdWeek = false; release?.resume(); release = nil }

    func status(accessToken: String) throws -> BriefingStatus {
        calls.append("status")
        if let statusError { throw statusError }
        return BriefingStatus(optedIn: optedIn)
    }

    func week(accessToken: String) async throws -> BriefingWeek {
        calls.append("week")
        if holdWeek { await withCheckedContinuation { release = $0 } }
        try Task.checkCancellation()
        return try weekResult.get()
    }

    func proposeOptIn(enabled: Bool, accessToken: String) throws -> BriefingOptInProposal {
        calls.append("propose:\(enabled)")
        return BriefingOptInProposal(id: "p-1", enabled: enabled)
    }

    func confirmOptIn(_ proposal: BriefingOptInProposal, accessToken: String) -> String {
        calls.append("confirm")
        return "token-1"
    }

    func setOptIn(enabled: Bool, confirmationToken: String, accessToken: String) throws -> BriefingStatus {
        calls.append("set:\(enabled):\(confirmationToken)")
        if let setError { throw setError }
        optedIn = enabled
        return BriefingStatus(optedIn: enabled)
    }
}

@MainActor
private struct Rig {
    let service: FakeBriefing
    let centre: StubNotificationCentre
    let sink = MemoryEventSink()
    let model: BriefingModel
    let reauth = Counter()

    final class Counter { var count = 0 }

    init(_ service: FakeBriefing, authorization: NotificationAuthorization = .allowed, slowAfter: Duration = .seconds(60)) {
        self.service = service
        let centre = StubNotificationCentre(authorization)
        self.centre = centre
        let sink = sink, reauth = reauth
        model = BriefingModel(
            service: service, accessToken: { "access-token" }, onReauthNeeded: { reauth.count += 1 },
            reminder: BriefingReminder(centre: centre), reminderTitle: { "Your week is ready" },
            makeFlow: {
                TaskFlow(
                    taskId: "T-BRF-VIEW", feature: "brf", mode: .classic, context: TaskContext(participantId: UUID()),
                    sink: sink, confirmAction: .optIn)
            }, stillWorkingAfter: slowAfter)
    }

    func events() async -> [ExperimentEvent] {
        try? await Task.sleep(for: .milliseconds(30))
        return await sink.events
    }
}

@MainActor
@Suite("FR-BRF-001/002/005 briefing model")
struct BriefingModelTests {
    @Test("FR-BRF-001.1: off by default shows the opt-in screen and never calls Work IQ")
    func offByDefault() async {
        let service = FakeBriefing(optedIn: false)
        let rig = Rig(service)
        await rig.model.begin()
        #expect(rig.model.state == .optIn(.ready))
        #expect(await service.calls == ["status"])  // no week read before the opt-in
        let events = await rig.events()
        #expect(events.map(\.event) == [.taskStarted, .confirmShown])
        #expect(events.allSatisfy { $0.taskId == "T-BRF-VIEW" && $0.feature == "brf" })
    }

    @Test("FR-BRF-002: an opted-in user's week is read and shown, and the flow completes")
    func content() async {
        let service = FakeBriefing()
        let rig = Rig(service)
        await rig.model.begin()
        let week = try? #require(rig.model.week)
        #expect(week?.eventCount == 6 && week?.conflictCount == 1)
        #expect(await service.calls == ["status", "week"])
        let names = await rig.events().map(\.event)
        #expect(names == [.taskStarted, .taskCompleted])
        #expect(await rig.centre.pendingIdentifiers() == [BriefingReminder.identifier])  // FR-BRF-003.1
    }

    @Test("FR-BRF-001.2: Turn on proposes, mints the token from the tap, writes, then reads")
    func turnOn() async {
        let service = FakeBriefing(optedIn: false)
        let rig = Rig(service, authorization: .allowed)
        await rig.model.begin()
        await rig.model.turnOn()
        #expect(await service.calls == ["status", "propose:true", "confirm", "set:true:token-1", "week"])
        #expect(rig.model.week != nil)
        let events = await rig.events().map(\.event)
        #expect(events == [.taskStarted, .confirmShown, .confirmAccepted, .taskCompleted])
    }

    @Test("FR-BRF-003.1: right after opt-in the reminder is asked for once, in context")
    func reminderAsk() async {
        let service = FakeBriefing(optedIn: false)
        let rig = Rig(service, authorization: .notDetermined)
        await rig.model.begin()
        await rig.model.turnOn()
        #expect(rig.model.reminderOffer == .ask)
        #expect(await service.calls.contains("week") == false)  // nothing is read until the ask is answered
        #expect(await rig.centre.pendingIdentifiers().isEmpty)
        await rig.model.allowReminder()
        #expect(rig.model.reminderOffer == .none && rig.model.reminderScheduled)
        #expect(await rig.centre.pendingIdentifiers() == [BriefingReminder.identifier])
        #expect(rig.model.week != nil)
    }

    @Test("FR-BRF-003.1: declining the reminder still shows the week, with nothing scheduled")
    func reminderSkip() async {
        let rig = Rig(FakeBriefing(optedIn: false), authorization: .notDetermined)
        await rig.model.begin()
        await rig.model.turnOn()
        await rig.model.skipReminder()
        #expect(rig.model.week != nil && !rig.model.reminderScheduled)
        #expect(await rig.centre.pendingIdentifiers().isEmpty)
    }

    @Test("FR-BRF-001: a failed or offline opt-in stays on the opt-in screen with a retry")
    func turnOnFails() async {
        let service = FakeBriefing(optedIn: false)
        await service.set(setError: .failed(code: "INTERNAL", correlationId: nil))
        let rig = Rig(service)
        await rig.model.begin()
        await rig.model.turnOn()
        #expect(rig.model.state == .optIn(.failed(code: "INTERNAL")))
        await service.set(setError: .offline)
        await rig.model.turnOn()
        #expect(rig.model.state == .optIn(.offline))
        await service.set(setError: nil)
        await rig.model.turnOn()
        #expect(rig.model.week != nil)
    }

    @Test("FR-BRF-001: 'Not now' leaves the briefing off, and it can be reconsidered")
    func notNow() async {
        let rig = Rig(FakeBriefing(optedIn: false))
        await rig.model.begin()
        rig.model.notNow()
        #expect(rig.model.declined)
        rig.model.reconsider()
        #expect(!rig.model.declined)
        let names = await rig.events().map(\.event)
        #expect(names.contains(.confirmRejected) && names.last == .taskAbandoned)
    }

    @Test("FR-BRF-005.1: each Work IQ failure has its own message and shows no briefing", arguments: [
        (BriefingError.workIQUnavailable, BriefingModel.Problem.unavailable),
        (.noLicence, .noLicence),
        (.consentRequired, .consentRequired),
        (.offline, .offline),
        (.timedOut, .timedOut),
        (.notProvisioned, .notProvisioned),
    ])
    func problems(error: BriefingError, problem: BriefingModel.Problem) async {
        let service = FakeBriefing()
        await service.set(week: .failure(error))
        let rig = Rig(service)
        await rig.model.begin()
        #expect(rig.model.state == .problem(problem))
        #expect(rig.model.week == nil)
        let events = await rig.events()
        #expect(events.last?.event == .taskError && events.last?.code == error.code)
    }

    @Test("FR-BRF-005.1: a lost session opens the sign-in prompt")
    func signedOut() async {
        let service = FakeBriefing()
        await service.set(week: .failure(.unauthenticated))
        let rig = Rig(service)
        await rig.model.begin()
        #expect(rig.model.state == .problem(.signedOut))
    }

    @Test("FR-BRF-001: a week answered NOT_OPTED_IN (turned off elsewhere) goes back to the opt-in screen")
    func turnedOffElsewhere() async {
        let service = FakeBriefing()
        await service.set(week: .failure(.notOptedIn))
        let rig = Rig(service)
        await rig.model.begin()
        #expect(rig.model.state == .optIn(.ready))
    }

    @Test("FR-BRF-005.2: an empty week is a briefing, not an error")
    func emptyWeek() async {
        let service = FakeBriefing()
        await service.set(week: .success(StubBriefingService.week(.empty)))
        let rig = Rig(service)
        await rig.model.begin()
        #expect(rig.model.week?.isEmpty == true)
        #expect(await rig.events().map(\.event) == [.taskStarted, .taskCompleted])  // a defined empty state counts
    }

    @Test("FR-BRF-005.3: a partial week is labelled and names the missing days")
    func partialWeek() async {
        let service = FakeBriefing()
        await service.set(week: .success(StubBriefingService.week(.partial)))
        let rig = Rig(service)
        await rig.model.begin()
        let week = rig.model.week
        #expect(week?.isPartial == true && week?.missingDays.map(\.day.iso) == ["2026-10-22", "2026-10-23"])
        #expect(week?.missingDays.allSatisfy { $0.events.isEmpty && $0.freeBlocks.isEmpty } == true)
    }

    @Test("PRIV-003: offline never falls back to an older calendar")
    func noStaleContent() async {
        let service = FakeBriefing()
        let rig = Rig(service)
        await rig.model.begin()
        #expect(rig.model.week != nil)
        await service.set(week: .failure(.offline))
        await rig.model.refresh()
        #expect(rig.model.week == nil)
        #expect(rig.model.state == .problem(.offline))
    }

    @Test("Long wait (40-60 s): a slow read says it is still working, and Stop ends the wait without content")
    func slowRead() async throws {
        let service = FakeBriefing()
        await service.hold()
        let rig = Rig(service, slowAfter: .milliseconds(30))
        let reading = Task { await rig.model.begin() }
        try await Task.sleep(for: .milliseconds(120))
        #expect(rig.model.state == .reading(stillWorking: true))
        rig.model.stopReading()
        #expect(rig.model.state == .problem(.stopped))
        await service.letGo()
        await reading.value
        #expect(rig.model.week == nil)  // the answer that came after Stop is not shown
        #expect(rig.model.state == .problem(.stopped))
    }
}

@MainActor
@Suite("FR-BRF-001.4 / FR-BRF-003.3 settings")
struct BriefingSettingsTests {
    private func make(_ service: FakeBriefing, authorization: NotificationAuthorization = .allowed)
        -> (BriefingSettingsModel, StubNotificationCentre)
    {
        let centre = StubNotificationCentre(authorization)
        let model = BriefingSettingsModel(
            service: service, accessToken: { "t" }, onReauthNeeded: {},
            reminder: BriefingReminder(centre: centre), reminderTitle: { "Your week is ready" })
        return (model, centre)
    }

    @Test("FR-BRF-001.4: the current state is shown")
    func state() async {
        let (on, _) = make(FakeBriefing(optedIn: true))
        await on.load()
        #expect(on.optedIn == true)
        let (off, _) = make(FakeBriefing(optedIn: false))
        await off.load()
        #expect(off.optedIn == false)
    }

    @Test("FR-BRF-001.3: turning off asks first, then removes the reminder at once")
    func turnOff() async {
        let service = FakeBriefing(optedIn: true)
        let (model, centre) = make(service)
        await model.load()
        await BriefingReminder(centre: centre).schedule(title: "x")
        model.request(false)
        #expect(model.pending == false)
        #expect(await service.calls == ["status"])  // nothing is written before the confirmation
        model.confirm()
        await model.waitUntilIdle()
        #expect(await service.calls == ["status", "propose:false", "confirm", "set:false:token-1"])
        #expect(model.optedIn == false)
        #expect(await centre.pendingIdentifiers().isEmpty)  // FR-BRF-003.3
    }

    @Test("FR-BRF-001.2: cancelling the alert changes nothing")
    func cancel() async {
        let service = FakeBriefing(optedIn: false)
        let (model, _) = make(service)
        await model.load()
        model.request(true)
        model.cancelPending()
        model.confirm()
        await model.waitUntilIdle()
        #expect(await service.calls == ["status"] && model.optedIn == false)
    }

    @Test("FR-BRF-003.1: turning on from Settings asks for notifications in context and schedules")
    func turnOn() async {
        let (model, centre) = make(FakeBriefing(optedIn: false), authorization: .notDetermined)
        await model.load()
        model.request(true)
        model.confirm()
        await model.waitUntilIdle()
        #expect(model.optedIn == true && model.reminder == .scheduled)
        #expect(await centre.pendingIdentifiers() == [BriefingReminder.identifier])
    }

    @Test("FR-BRF-003: notifications turned off in iOS are shown, not hidden")
    func denied() async {
        let (model, _) = make(FakeBriefing(optedIn: true), authorization: .denied)
        await model.load()
        #expect(model.reminder == .denied)
    }

    @Test("FR-BRF-001: offline disables the toggle instead of guessing the state")
    func offline() async {
        let service = FakeBriefing()
        await service.set(statusError: .offline)
        let (model, _) = make(service)
        await model.load()
        #expect(model.state == .unavailable(offline: true) && model.optedIn == nil)
        model.request(true)
        #expect(model.pending == nil)
    }

    @Test("FR-BRF-001: a failed change keeps the old state and says so")
    func failed() async {
        let service = FakeBriefing(optedIn: false)
        await service.set(setError: .failed(code: "INTERNAL", correlationId: nil))
        let (model, _) = make(service)
        await model.load()
        model.request(true)
        model.confirm()
        await model.waitUntilIdle()
        #expect(model.optedIn == false && model.failedCode == "INTERNAL")
    }
}

@MainActor
@Suite("FR-BRF-003 notification tap and sign-out")
struct BriefingNotificationTests {
    @Test("FR-BRF-003.2: a tap before the screen exists is delivered once it attaches")
    func coldStartTap() {
        let router = BriefingTapRouter()
        router.receive(identifier: BriefingReminder.identifier)
        router.receive(identifier: "something.else")  // not ours
        var opened = 0
        router.attach { opened += 1 }
        #expect(opened == 1)
        router.receive(identifier: BriefingReminder.identifier)
        #expect(opened == 2)
    }

    @Test("FR-BRF-003.2: each tap asks the app to open the briefing again")
    func openRequests() async {
        let stub = StubAuthService(scenario: .employee, signedIn: true)
        let model = AppModel(auth: stub, me: stub, cleaner: SessionCleaner())
        #expect(model.briefingOpenRequests == 0)
        model.openBriefing()
        model.openBriefing()
        #expect(model.briefingOpenRequests == 2)
    }

    @Test("FR-BRF-003.3: sign-out removes the pending reminder")
    func signOut() async {
        let stub = StubAuthService(scenario: .employee, signedIn: true)
        let centre = StubNotificationCentre(.allowed)
        let reminder = BriefingReminder(centre: centre)
        let environment = AppEnvironment(
            auth: stub, me: stub, mode: ModeStore(), briefingReminder: reminder)
        await environment.registerSessionCleanup()
        await reminder.schedule(title: "Your week is ready")
        #expect(await reminder.isScheduled())
        await environment.cleaner.clearAll()
        #expect(await reminder.isScheduled() == false)
    }

    @Test("FR-BRF-003.1: the Week tab is there for every role")
    func weekTab() {
        for roles in [[Role.employee], [.manager, .employee]] {
            let session = Session(oid: "o", displayName: "N", upn: "n@example.test", roles: Set(roles), tenantID: "t")
            #expect(AppTab.tabs(for: session).contains(.week))
        }
    }
}

@Suite("FR-BRF AGENT presentation")
struct BriefingAgentPresentationTests {
    @Test("FR-BRF-001 AGENT: the opt-in card names what is accessed, from the stored proposal")
    func card() {
        let on = AgentCardPresenter.present(.briefing(enabled: true))
        #expect(on.lines.count == 3)  // access, through, stored
        let off = AgentCardPresenter.present(.briefing(enabled: false))
        #expect(on.title != off.title && on.confirmTitle != off.confirmTitle)
        #expect(AgentCardPresenter.successText(.briefing(enabled: true)) != AgentCardPresenter.successText(.briefing(enabled: false)))
    }

    @Test("FR-BRF-002 AGENT: the briefing tools are one task, T-BRF-VIEW, in the brf feature")
    func task() {
        for tool in ["get_briefing_status", "get_my_week", "propose_briefing_optin", "set_briefing_optin"] {
            #expect(AgentTask.resolve(toolNames: [tool], feature: .briefing) == .briefingView)
        }
        #expect(AgentTask.resolve(toolNames: ["get_my_week"], feature: .vacation) == nil)
        #expect(AgentTask.briefingView.taskId == "T-BRF-VIEW" && AgentTask.briefingView.feature == "brf")
        #expect(AgentTask.briefingView.confirmAction == .optIn)
    }

    @Test("FR-BRF-002 AGENT: only a summary backed by a read week completes the task")
    func completion() {
        let read = [AgentToolCall(name: "get_my_week", ok: true)]
        let summary = AgentReply(kind: .summary, text: "6 events", omittedCount: 0)
        #expect(AgentTask.briefingView.isCompleted(by: summary, toolCalls: read))
        #expect(!AgentTask.briefingView.isCompleted(by: summary, toolCalls: []))
        #expect(!AgentTask.briefingView.isCompleted(by: summary, toolCalls: [AgentToolCall(name: "get_my_week", ok: false)]))
        #expect(!AgentTask.briefingView.isCompleted(by: AgentReply(kind: .message, text: "x"), toolCalls: read))
        let offer = AgentReply(kind: .proposal, text: "Turn on?", proposalId: "p")
        #expect(!AgentTask.briefingView.isCompleted(by: offer, toolCalls: read))
    }
}
#endif
