import Core
import Foundation
import Testing
@testable import Features

#if DEBUG
private func day(_ iso: String) -> CalendarDay { CalendarDay(iso: iso)! }

private let fixtureBalance = VacationBalance(year: 2026, entitlement: 25, carriedOver: 0, approved: 5, pending: 0, remaining: 20)

private func review(counted: Int = 3, after: Int? = 17, remaining: Int = 20) -> VacationReview {
    VacationReview(
        countedDays: counted, perYear: [2026: counted], excluded: [], remaining: remaining, remainingAfter: after,
        balanceYear: 2026, approver: "Maria Keller")
}

/// Scriptable service: records calls, fails on demand.
private actor FakeVacation: VacationService {
    var calls: [String] = []
    var tokens: [String] = []
    var balanceResult: Result<VacationBalance, VacationError> = .success(fixtureBalance)
    var requestsResult: Result<[VacationRequestSummary], VacationError> = .success([])
    var holidaysResult: Result<VacationHolidays, VacationError> = .success(
        VacationHolidays(year: 2026, canton: "ZH", items: [VacationHoliday(day: day("2026-11-11"), name: "Fixture Day ZH")]))
    var proposeResults: [Result<VacationProposal, VacationError>] = []
    var submitErrors: [VacationError] = []
    var requestResult: Result<VacationRequestSummary, VacationError> = .success(
        VacationRequestSummary(
            id: "r1", status: .pending, start: day("2026-11-23"), end: day("2026-11-25"), countedDays: 3,
            approver: "Maria Keller"))
    var cancelErrors: [VacationError] = []
    var cancelTokens: [String] = []
    var inboxResult: Result<[VacationRequestSummary], VacationError> = .success([])
    var confirmDecisionErrors: [VacationError] = []
    var decideErrors: [VacationError] = []
    var decisions: [(decision: VacationDecision, reason: String?, token: String)] = []
    var coverageResult: Result<[CoverageDay], VacationError> = .success([])
    var coverageCalls: [(CalendarDay?, CalendarDay?)] = []
    var minted = 0

    func set(balance result: Result<VacationBalance, VacationError>) { balanceResult = result }
    func set(requests result: Result<[VacationRequestSummary], VacationError>) { requestsResult = result }
    func set(holidays result: Result<VacationHolidays, VacationError>) { holidaysResult = result }
    func queue(propose results: [Result<VacationProposal, VacationError>]) { proposeResults = results }
    func failSubmit(_ errors: [VacationError]) { submitErrors = errors }
    func set(request result: Result<VacationRequestSummary, VacationError>) { requestResult = result }
    func failCancel(_ errors: [VacationError]) { cancelErrors = errors }
    func set(inbox result: Result<[VacationRequestSummary], VacationError>) { inboxResult = result }
    func set(coverage result: Result<[CoverageDay], VacationError>) { coverageResult = result }
    func failConfirmDecision(_ errors: [VacationError]) { confirmDecisionErrors = errors }
    func failDecide(_ errors: [VacationError]) { decideErrors = errors }

    func balance(accessToken: String) throws -> VacationBalance {
        calls.append("balance")
        return try balanceResult.get()
    }
    func requests(accessToken: String) throws -> [VacationRequestSummary] {
        calls.append("requests")
        return try requestsResult.get()
    }
    func holidays(year: Int, accessToken: String) throws -> VacationHolidays {
        calls.append("holidays")
        return try holidaysResult.get()
    }
    func propose(start: CalendarDay, end: CalendarDay, accessToken: String) throws -> VacationProposal {
        calls.append("propose")
        if !proposeResults.isEmpty { return try proposeResults.removeFirst().get() }
        return VacationProposal(id: "p-\(start.iso)-\(end.iso)", start: start, end: end, review: review())
    }
    func confirm(_ proposal: VacationProposal, accessToken: String) -> String {
        calls.append("confirm")
        minted += 1
        return "token-\(minted)"
    }
    func submit(start: CalendarDay, end: CalendarDay, confirmationToken: String, accessToken: String) throws
        -> VacationRequestSummary
    {
        calls.append("submit")
        tokens.append(confirmationToken)
        if !submitErrors.isEmpty { throw submitErrors.removeFirst() }
        return VacationRequestSummary(
            id: "r1", status: .pending, start: start, end: end, countedDays: 3, approver: "Maria Keller")
    }
}

extension FakeVacation {
    func request(id: String, accessToken: String) throws -> VacationRequestSummary {
        calls.append("request")
        return try requestResult.get()
    }
    func confirmCancel(id: String, accessToken: String) -> String {
        calls.append("confirmCancel")
        minted += 1
        return "cancel-token-\(minted)"
    }
    func cancel(id: String, confirmationToken: String, accessToken: String) throws -> VacationRequestSummary {
        calls.append("cancel")
        cancelTokens.append(confirmationToken)
        if !cancelErrors.isEmpty { throw cancelErrors.removeFirst() }
        guard case let .success(current) = requestResult else { throw VacationError.notFound }
        let done = VacationRequestSummary(
            id: current.id, status: .cancelled, start: current.start, end: current.end,
            countedDays: current.countedDays, approver: current.approver)
        requestResult = .success(done)
        return done
    }
}

extension FakeVacation {
    func coverage(start: CalendarDay?, end: CalendarDay?, accessToken: String) throws -> [CoverageDay] {
        calls.append("coverage")
        coverageCalls.append((start, end))
        return try coverageResult.get()
    }
    func inbox(accessToken: String) throws -> [VacationRequestSummary] {
        calls.append("inbox")
        return try inboxResult.get()
    }
    func confirmDecision(id: String, decision: VacationDecision, reason: String?, accessToken: String) throws -> String {
        calls.append("confirmDecision")
        if !confirmDecisionErrors.isEmpty { throw confirmDecisionErrors.removeFirst() }
        minted += 1
        return "decision-token-\(minted)"
    }
    func decide(
        id: String, decision: VacationDecision, reason: String?, confirmationToken: String, accessToken: String
    ) throws -> VacationRequestSummary {
        calls.append("decide")
        decisions.append((decision, reason, confirmationToken))
        if !decideErrors.isEmpty { throw decideErrors.removeFirst() }
        guard case let .success(current) = requestResult else { throw VacationError.notFound }
        let done = VacationRequestSummary(
            id: current.id, status: decision == .approve ? .approved : .rejected, start: current.start,
            end: current.end, countedDays: current.countedDays, approver: current.approver,
            ownerName: current.ownerName, decidedAt: fixtureNow, reason: reason)
        requestResult = .success(done)
        return done
    }
}

@MainActor
private func access(
    token: @escaping @Sendable () async throws -> String = { "bearer" }, reauth: @escaping @MainActor () -> Void = {}
) -> VacationAccess {
    VacationAccess(accessToken: token, onReauthNeeded: reauth)
}

@MainActor
private func flow(_ task: String, _ sink: MemoryEventSink) -> TaskFlow {
    TaskFlow(
        taskId: task, feature: "vac", mode: .classic, context: TaskContext(participantId: UUID()), sink: sink,
        confirmAction: .request)
}

private let fixtureNow = Date(timeIntervalSince1970: 1_792_387_200)  // 2026-10-19 08:00 Europe/Zurich

@MainActor
private func overview(
    _ service: FakeVacation, sink: MemoryEventSink = MemoryEventSink(), cache: VacationCache = VacationCache(),
    token: @escaping @Sendable () async throws -> String = { "bearer" }, reauth: @escaping @MainActor () -> Void = {}
) -> VacationOverviewModel {
    VacationOverviewModel(
        service: service, access: access(token: token, reauth: reauth), cache: cache, userKey: "u1",
        makeFlow: { flow("T-VAC-BAL", sink) }, now: { fixtureNow })
}

@MainActor
private func request(
    _ service: FakeVacation, sink: MemoryEventSink = MemoryEventSink(),
    token: @escaping @Sendable () async throws -> String = { "bearer" }, reauth: @escaping @MainActor () -> Void = {}
) -> VacationRequestModel {
    VacationRequestModel(
        service: service, access: access(token: token, reauth: reauth), flow: flow("T-VAC-REQ", sink),
        today: day("2026-10-19"))
}

private func flush() async throws { try await Task.sleep(for: .milliseconds(50)) }

@MainActor
@Suite("FR-VAC-001 overview")
struct VacationOverviewModelTests {
    @Test("FR-VAC-001.1: the five numbers and requests are shown as the API sent them")
    func loads() async {
        let service = FakeVacation()
        let model = overview(service)
        await model.begin()
        #expect(model.state == .content(fixtureBalance, requests: []))
        #expect(model.balance?.remaining == 20 && model.canRequest)
        #expect(await service.calls.sorted() == ["balance", "requests"])
    }

    @Test("FR-VAC-001.2: a refresh reflects the last write without any manual step")
    func refreshShowsChange() async {
        let service = FakeVacation()
        let model = overview(service)
        await model.begin()
        await service.set(balance: .success(VacationBalance(year: 2026, entitlement: 25, carriedOver: 0, approved: 5, pending: 3, remaining: 17)))
        await model.refresh()
        #expect(model.balance?.pending == 3 && model.balance?.remaining == 17)
    }

    @Test("T-VAC-BAL: started on open, completed once the numbers came from the API")
    func events() async throws {
        let sink = MemoryEventSink()
        let model = overview(FakeVacation(), sink: sink)
        await model.begin()
        try await flush()
        let events = await sink.events
        #expect(events.map(\.event) == [.taskStarted, .taskCompleted])
        #expect(events.allSatisfy { $0.taskId == "T-VAC-BAL" && $0.feature == "vac" })
        #expect(events.last?.outcomeValid == true)
    }

    @Test("NFR-007: offline shows the cached overview with its as-of time, request disabled, no completion")
    func offlineUsesCache() async throws {
        let cache = VacationCache()
        let sink = MemoryEventSink()
        let service = FakeVacation()
        let model = overview(service, sink: sink, cache: cache)
        await model.begin()  // fills the cache
        await service.set(balance: .failure(.offline))
        let offline = overview(service, sink: sink, cache: cache)
        await offline.begin()
        #expect(offline.offlineAsOf == fixtureNow)
        #expect(offline.balance == fixtureBalance)
        #expect(!offline.canRequest)
        try await flush()
        let errors = await sink.events.filter { $0.event == .taskError }
        #expect(errors.count == 1 && errors.first?.code == "OFFLINE" && errors.first?.recovered == true)
    }

    @Test("NFR-007: offline without a cache is an error state, not an empty balance")
    func offlineWithoutCache() async {
        let service = FakeVacation()
        await service.set(balance: .failure(.offline))
        let model = overview(service)
        await model.begin()
        #expect(model.state == .error(code: "OFFLINE", correlationId: nil))
        #expect(!model.canRequest)
    }

    @Test("FR-VAC-001: an API failure is an error state with the correlation id; a retry recovers")
    func errorThenRetry() async {
        let service = FakeVacation()
        await service.set(balance: .failure(.failed(code: "INTERNAL", correlationId: "c1")))
        let model = overview(service)
        await model.begin()
        #expect(model.state == .error(code: "INTERNAL", correlationId: "c1"))
        await service.set(balance: .success(fixtureBalance))
        await model.refresh()
        #expect(model.balance == fixtureBalance)
    }

    @Test("FR-VAC-001: an account without an employee record gets its own state")
    func notProvisioned() async {
        let service = FakeVacation()
        await service.set(balance: .failure(.notProvisioned))
        let model = overview(service)
        await model.begin()
        #expect(model.state == .notProvisioned)
    }

    @Test("FR-VAC-001: the next request is the earliest pending or approved one that has not ended")
    func nextRequest() async {
        let service = FakeVacation()
        let past = VacationRequestSummary(id: "a", status: .approved, start: day("2026-06-01"), end: day("2026-06-30"), countedDays: 22, approver: "M")
        let later = VacationRequestSummary(id: "b", status: .pending, start: day("2026-12-28"), end: day("2027-01-05"), countedDays: 6, approver: "M")
        let sooner = VacationRequestSummary(id: "c", status: .approved, start: day("2026-11-09"), end: day("2026-11-12"), countedDays: 3, approver: "M")
        let cancelled = VacationRequestSummary(id: "d", status: .cancelled, start: day("2026-10-26"), end: day("2026-10-27"), countedDays: 2, approver: "M")
        await service.set(requests: .success([past, later, sooner, cancelled]))
        let model = overview(service)
        await model.begin()
        #expect(model.next(today: day("2026-10-19"))?.id == "c")
        #expect(model.next(today: day("2027-02-01")) == nil)
    }

    @Test("FR-AUTH-005: a lost session opens the re-sign-in sheet instead of showing data")
    func reauth() async {
        var reauthCalls = 0
        let model = overview(FakeVacation(), token: { throw AuthError.interactionRequired }, reauth: { reauthCalls += 1 })
        await model.begin()
        #expect(reauthCalls == 1)
        #expect(model.balance == nil)
    }
}

@MainActor
@Suite("FR-VAC-006 holidays")
struct HolidaysModelTests {
    private func model(_ service: FakeVacation) -> HolidaysModel {
        HolidaysModel(service: service, access: access(), year: 2026)
    }

    @Test("FR-VAC-006.3: the user's own canton list is shown with the confirmation flag")
    func content() async {
        let service = FakeVacation()
        await service.set(holidays: .success(VacationHolidays(
            year: 2026, canton: "TI", items: [VacationHoliday(day: day("2026-11-12"), name: "Fixture Day TI")], needsConfirmation: true)))
        let model = model(service)
        await model.load()
        guard case let .content(holidays) = model.state else { Issue.record("expected content"); return }
        #expect(holidays.canton == "TI" && holidays.needsConfirmation && holidays.items.count == 1)
    }

    @Test("FR-VAC-006: empty, missing canton, offline and error each have their own state")
    func states() async {
        let service = FakeVacation()
        let model = model(service)
        await service.set(holidays: .success(VacationHolidays(year: 2026, canton: "ZH", items: [])))
        await model.load()
        #expect(model.state == .empty(VacationHolidays(year: 2026, canton: "ZH", items: [])))
        await service.set(holidays: .failure(.cantonMissing))
        await model.load()
        #expect(model.state == .cantonMissing)
        await service.set(holidays: .failure(.offline))
        await model.load()
        #expect(model.state == .offline)
        await service.set(holidays: .failure(.failed(code: "INTERNAL", correlationId: "c9")))
        await model.load()
        #expect(model.state == .error(code: "INTERNAL", correlationId: "c9"))
    }
}

@MainActor
@Suite("FR-VAC-002 request flow")
struct VacationRequestModelTests {
    /// One dry run for the whole range (the calendar's two taps would each trigger one).
    private func pick(_ model: VacationRequestModel, _ from: String, _ to: String) async {
        model.setDates(start: day(from), end: day(to))
        await model.waitForCheck()
    }

    @Test("FR-VAC-002: two taps pick a range; the API's dry run decides if it is valid")
    func rangeAndCheck() async {
        let service = FakeVacation()
        let model = request(service)
        await model.begin()
        model.select(day("2026-11-23"))
        model.select(day("2026-11-25"))
        await model.waitForCheck()
        #expect(model.start == day("2026-11-23") && model.end == day("2026-11-25"))
        guard case let .valid(proposal) = model.check else { Issue.record("expected valid"); return }
        #expect(proposal.review.countedDays == 3 && proposal.review.remainingAfter == 17)
        #expect(model.canContinue)
    }

    @Test("FR-VAC-002: a second tap before the first day starts a new range; a third tap restarts")
    func selectionRules() async {
        let model = request(FakeVacation())
        model.select(day("2026-11-25"))
        model.select(day("2026-11-23"))
        #expect(model.start == day("2026-11-23") && model.end == day("2026-11-23"))
        model.select(day("2026-11-27"))
        #expect(model.end == day("2026-11-27"))
        model.select(day("2026-12-01"))
        #expect(model.start == day("2026-12-01") && model.end == day("2026-12-01"))
        await model.waitForCheck()
    }

    @Test("FR-VAC-006: the picker marks the holidays of the work canton")
    func holidayMarkers() async {
        let model = request(FakeVacation())
        await model.begin()
        #expect(model.holidayDays.contains(day("2026-11-11")))
    }

    @Test("FR-VAC-006: a failed holiday load does not block the request")
    func holidaysFailed() async {
        let service = FakeVacation()
        await service.set(holidays: .failure(.failed(code: nil, correlationId: nil)))
        let model = request(service)
        await model.begin()
        #expect(model.holidays == .failed)
        await pick(model, "2026-11-23", "2026-11-25")
        #expect(model.canContinue)
    }

    @Test("FR-VAC-002.2: every failing code is kept in the API's order and Continue stays off")
    func violations() async {
        let service = FakeVacation()
        let list = [VacationViolation(code: "PAST_DATE"), VacationViolation(code: "BLACKOUT"), VacationViolation(code: "OVERLAP")]
        await service.queue(propose: [.failure(.rules(list, review: nil))])
        let model = request(service)
        await pick(model, "2026-10-12", "2026-12-16")
        #expect(model.check == .violations(list, review: nil))
        #expect(!model.canContinue)
    }

    @Test("FR-VAC-002.2: only INSUFFICIENT_BALANCE leads to a blocked review that cannot be submitted")
    func blockedReview() async {
        let service = FakeVacation()
        let violation = VacationViolation(code: "INSUFFICIENT_BALANCE", remaining: 3, requested: 5)
        let shown = review(counted: 5, after: nil, remaining: 3)
        await service.queue(propose: [.failure(.rules([violation], review: shown))])
        let model = request(service)
        await pick(model, "2026-11-23", "2026-11-27")
        #expect(model.canContinue)
        model.goToReview()
        #expect(model.phase == .blocked(shown, [violation]))
        await model.submit()
        #expect(await !service.calls.contains("submit"))
        model.backToPicking()
        #expect(model.phase == .picking)
    }

    @Test("FR-VAC-002: a missing canton, no approver and offline each have their own check state")
    func otherChecks() async {
        let service = FakeVacation()
        let model = request(service)
        for (error, expected) in [(VacationError.cantonMissing, VacationRequestModel.Check.cantonMissing),
                                  (.noApprover, .noApprover), (.offline, .offline),
                                  (.failed(code: "X", correlationId: nil), .failed)] {
            await service.queue(propose: [.failure(error)])
            model.select(day("2026-11-23"))
            await model.waitForCheck()
            #expect(model.check == expected)
            #expect(!model.canContinue)
            model.select(day("2026-11-24"))  // restart for the next case
            await model.waitForCheck()
        }
    }

    @Test("FR-VAC-002.1/.3: review then submit mints one token and ends in success with the approver")
    func happyPath() async throws {
        let sink = MemoryEventSink()
        let service = FakeVacation()
        let model = request(service, sink: sink)
        await model.begin()
        await pick(model, "2026-11-23", "2026-11-25")
        model.goToReview()
        guard case let .reviewing(proposal) = model.phase else { Issue.record("expected review"); return }
        #expect(proposal.review.approver == "Maria Keller")
        await model.submit()
        guard case let .submitted(done) = model.phase else { Issue.record("expected success"); return }
        #expect(done.status == .pending && done.approver == "Maria Keller")
        #expect(await service.calls.filter { ["confirm", "submit"].contains($0) } == ["confirm", "submit"])
        try await flush()
        let events = await sink.events
        #expect(events.map(\.event).filter { $0 != .taskError } == [.taskStarted, .confirmShown, .confirmAccepted, .taskCompleted])
        #expect(events.filter { $0.action != nil }.allSatisfy { $0.action == .request })
    }

    @Test("FR-VAC-002.4: a retry after a failed submit replays the same token, no second mint")
    func retryReplaysToken() async {
        let service = FakeVacation()
        await service.failSubmit([.failed(code: "INTERNAL", correlationId: "c1")])
        let model = request(service)
        await pick(model, "2026-11-23", "2026-11-25")
        model.goToReview()
        await model.submit()
        #expect(model.failure == .failed(code: "INTERNAL", correlationId: "c1"))
        await model.retry()
        #expect(await service.tokens == ["token-1", "token-1"])
        #expect(await service.calls.filter { $0 == "confirm" }.count == 1)
        if case .submitted = model.phase {} else { Issue.record("expected success after the retry") }
    }

    @Test("NFR-007: offline on submit keeps the review and the dates, and nothing claims success")
    func offlineSubmit() async {
        let service = FakeVacation()
        await service.failSubmit([.offline])
        let model = request(service)
        await pick(model, "2026-11-23", "2026-11-25")
        model.goToReview()
        await model.submit()
        #expect(model.failure == .offline)
        if case .reviewing = model.phase {} else { Issue.record("expected to stay on review") }
        #expect(model.start == day("2026-11-23"))
    }

    @Test("FR-AUTH-006: an expired confirmation is re-minted on the next try")
    func expiredConfirmation() async {
        let service = FakeVacation()
        await service.failSubmit([.invalidConfirmation])
        let model = request(service)
        await pick(model, "2026-11-23", "2026-11-25")
        model.goToReview()
        await model.submit()
        #expect(model.failure == .invalidConfirmation)
        await model.retry()
        #expect(await service.tokens == ["token-1", "token-2"])
    }

    @Test("FR-VAC-002.2: a rule broken between review and write sends the user back to the dates")
    func writeTimeRules() async {
        let service = FakeVacation()
        let overlap = VacationViolation(code: "OVERLAP", conflicts: [DayRange(start: day("2026-11-24"), end: day("2026-11-24"))])
        await service.failSubmit([.rules([overlap], review: nil)])
        let model = request(service)
        await pick(model, "2026-11-23", "2026-11-25")
        model.goToReview()
        await model.submit()
        #expect(model.phase == .picking)
        #expect(model.check == .violations([overlap], review: nil))
    }

    @Test("T-VAC-REQ: leaving the review reports the abandon with the last state; backing out is a rejection")
    func abandonAndReject() async throws {
        let sink = MemoryEventSink()
        let model = request(FakeVacation(), sink: sink)
        await model.begin()
        await pick(model, "2026-11-23", "2026-11-25")
        model.goToReview()
        model.backToPicking()
        model.goToReview()
        model.leave()
        try await flush()
        let events = await sink.events
        #expect(events.map(\.event).contains(.confirmRejected))
        #expect(events.last?.event == .taskAbandoned && events.last?.lastState == "review")
    }

    @Test("FR-VAC-002: text entry sets the same range as the calendar")
    func textEntry() async {
        let service = FakeVacation()
        let model = request(service)
        model.toggleTextEntry()
        #expect(model.usesTextEntry && model.start == day("2026-10-19"))
        model.setDates(start: day("2026-11-23"), end: day("2026-11-25"))
        await model.waitForCheck()
        #expect(model.canContinue)
    }
}

@Suite("DE/FR/IT/EN vacation strings")
struct VacationStringsTests {
    private func catalog() throws -> [String: [String: Any]] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Sources/Features/Resources/Localizable.xcstrings")
        let json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        return try #require(json["strings"] as? [String: [String: Any]])
    }

    @Test("FR-VAC-001/002/006: every vac.* key is translated into de, fr, it and en")
    func complete() throws {
        let strings = try catalog().filter { $0.key.hasPrefix("vac.") }
        #expect(strings.count > 60)
        for (key, entry) in strings {
            let locs = try #require(entry["localizations"] as? [String: Any], "\(key)")
            #expect(Set(locs.keys) == ["de", "fr", "it", "en"], "\(key)")
        }
    }

    @Test("FR-VAC-002: plural forms resolve per language")
    func plurals() {
        func text(_ key: StaticString, _ count: Int, _ language: String) -> String {
            String(localized: LocalizedStringResource(
                key, defaultValue: "\(count)", locale: Locale(identifier: language), bundle: L10n.bundle))
        }
        #expect(text("vac.workdays", 1, "de") == "1 Arbeitstag")
        #expect(text("vac.workdays", 6, "de") == "6 Arbeitstage")
        #expect(text("vac.workdays", 1, "fr") == "1 jour ouvré")
        #expect(text("vac.workdays", 6, "it") == "6 giorni lavorativi")
        #expect(text("vac.days", 1, "en") == "1 day")
        #expect(text("vac.days", 13, "en") == "13 days")
    }
}
#endif

@MainActor
@Suite("FR-VAC-003 cancel")
struct RequestDetailModelTests {
    private func detail(_ service: FakeVacation, seed: VacationRequestSummary? = nil, changed: @escaping @MainActor () -> Void = {})
        -> RequestDetailModel
    {
        RequestDetailModel(id: "r1", seed: seed, service: service, access: access(), onChanged: changed)
    }

    @Test("FR-VAC-003.1: confirming cancels once, shows cancelled and tells the list to refresh")
    func cancels() async {
        let service = FakeVacation()
        var changed = 0
        let model = detail(service, changed: { changed += 1 })
        await model.load()
        #expect(model.canCancel)
        model.askToCancel()
        #expect(model.isConfirmingCancel)
        await model.confirmCancel()
        #expect(model.request?.status == .cancelled && !model.canCancel && changed == 1)
        #expect(await service.calls == ["request", "confirmCancel", "cancel"])
    }

    @Test("FR-VAC-003.3: a failed attempt keeps the token, so the retry is the same idempotent call")
    func retryReusesToken() async {
        let service = FakeVacation()
        await service.failCancel([.failed(code: "INTERNAL", correlationId: nil)])
        let model = detail(service)
        await model.load()
        await model.confirmCancel()
        #expect(model.notice == .cancelFailed && model.request?.status == .pending)
        await model.confirmCancel()
        #expect(model.request?.status == .cancelled && model.notice == nil)
        #expect(await service.cancelTokens == ["cancel-token-1", "cancel-token-1"])
        #expect(await service.calls.filter { $0 == "confirmCancel" }.count == 1)
    }

    @Test("FR-VAC-003.2: a request that was decided meanwhile says so and offers no cancel")
    func invalidState() async {
        let service = FakeVacation()
        let model = detail(service)
        await model.load()
        let decided = VacationRequestSummary(
            id: "r1", status: .approved, start: day("2026-11-23"), end: day("2026-11-25"), countedDays: 3,
            approver: "Maria Keller")
        await service.failCancel([.invalidState])
        await service.set(request: .success(decided))
        await model.confirmCancel()
        #expect(model.notice == .alreadyDecided && model.request?.status == .approved && !model.canCancel)
    }

    @Test("FR-VAC-003: only a pending request can be cancelled")
    func onlyPending() async {
        let service = FakeVacation()
        await service.set(request: .success(VacationRequestSummary(
            id: "r1", status: .rejected, start: day("2026-11-23"), end: day("2026-11-25"), countedDays: 3,
            approver: "Maria Keller", reason: "Inventory week")))
        let model = detail(service)
        await model.load()
        model.askToCancel()
        #expect(!model.canCancel && !model.isConfirmingCancel)
    }

    @Test("FR-VAC-003 (OFF): offline keeps the seed visible with the cancel disabled")
    func offline() async {
        let service = FakeVacation()
        await service.set(request: .failure(.offline))
        let seed = VacationRequestSummary(
            id: "r1", status: .pending, start: day("2026-11-23"), end: day("2026-11-25"), countedDays: 3,
            approver: "Maria Keller")
        let model = detail(service, seed: seed)
        await model.load()
        #expect(model.isOffline && model.request == seed && !model.canCancel)
    }

    @Test("FR-VAC-003 (403/404): someone else's request is not found")
    func notFound() async {
        let service = FakeVacation()
        await service.set(request: .failure(.notFound))
        let model = detail(service)
        await model.load()
        #expect(model.state == .notFound)
    }
}

private let waiting = VacationRequestSummary(
    id: "r1", status: .pending, start: day("2026-11-09"), end: day("2026-11-12"), countedDays: 4,
    approver: "Marco Rossi", ownerName: "Lena Meier",
    ownerBalance: VacationBalance(year: 2026, entitlement: 25, carriedOver: 3, approved: 11, pending: 4, remaining: 13))

@MainActor
private func approver(
    _ service: FakeVacation, sink: MemoryEventSink = MemoryEventSink(), changed: @escaping @MainActor () -> Void = {}
) -> (RequestDetailModel, TaskFlow) {
    let task = TaskFlow(
        taskId: "T-VAC-APR", feature: "vac", mode: .classic, context: TaskContext(participantId: UUID()), sink: sink,
        confirmAction: .decide)
    task.start()
    let model = RequestDetailModel(
        id: "r1", role: .approver, seed: waiting, service: service, access: access(), flow: { task },
        onChanged: changed)
    return (model, task)
}

@MainActor
@Suite("FR-VAC-004 decide")
struct DecisionModelTests {
    @Test("FR-VAC-004.1: approve after one confirmation; T-VAC-APR reports shown, accepted, completed")
    func approves() async throws {
        let service = FakeVacation()
        await service.set(request: .success(waiting))
        let sink = MemoryEventSink()
        var changed = 0
        let (model, _) = approver(service, sink: sink, changed: { changed += 1 })
        await model.load()
        #expect(model.canDecide)
        model.askToApprove()
        #expect(model.isConfirmingApprove)
        await model.confirmApprove()
        #expect(model.request?.status == .approved && model.notice == .decided(.approved) && !model.canDecide)
        #expect(await service.calls == ["request", "coverage", "confirmDecision", "decide"] && changed == 1)
        try await flush()
        let events = await sink.events
        #expect(events.map(\.event) == [.taskStarted, .confirmShown, .confirmAccepted, .taskCompleted])
        #expect(events.allSatisfy { $0.taskId == "T-VAC-APR" })
        #expect(events[1].action == .decide && events.last?.outcomeValid == true)
    }

    @Test("FR-VAC-004.1: reject sends the trimmed reason; an empty one is no reason")
    func rejectsWithReason() async {
        let service = FakeVacation()
        await service.set(request: .success(waiting))
        let (model, _) = approver(service)
        await model.load()
        model.askToReject()
        model.reason = "  Inventory week \n"
        await model.confirmReject()
        #expect(model.request?.status == .rejected && model.notice == .decided(.rejected))
        #expect(await service.decisions.first?.reason == "Inventory week")

        let other = FakeVacation()
        await other.set(request: .success(waiting))
        let (second, _) = approver(other)
        await second.load()
        second.askToReject()
        second.reason = "   "
        await second.confirmReject()
        #expect(await other.decisions.first?.reason == nil)
    }

    @Test("FR-VAC-004.1: a reason over 500 characters cannot be sent")
    func reasonLimit() async {
        let service = FakeVacation()
        await service.set(request: .success(waiting))
        let (model, _) = approver(service)
        await model.load()
        model.askToReject()
        model.reason = String(repeating: "x", count: 501)
        #expect(model.reasonTooLong)
        await model.confirmReject()
        #expect(await service.decisions.isEmpty && model.request?.status == .pending)
        model.reason = String(repeating: "x", count: 500)
        #expect(!model.reasonTooLong)
    }

    @Test("FR-VAC-004.2: a rule broken since submission is shown, the request stays pending, the error is reported")
    func revalidation() async throws {
        let service = FakeVacation()
        await service.set(request: .success(waiting))
        await service.failConfirmDecision([.rules([VacationViolation(code: "BLACKOUT")], review: nil)])
        let sink = MemoryEventSink()
        let (model, task) = approver(service, sink: sink)
        await model.load()
        model.askToApprove()
        await model.confirmApprove()
        #expect(model.notice == .blocked(VacationViolation(code: "BLACKOUT")))
        #expect(model.request?.status == .pending && model.canDecide && !task.isFinished)
        try await flush()
        let errors = await sink.events.filter { $0.event == .taskError }
        #expect(errors.map(\.code) == ["BLACKOUT"] && errors.first?.recovered == false)
    }

    @Test("FR-VAC-004.3: decided meanwhile says so, reloads the final state and offers no action")
    func alreadyDecided() async {
        let service = FakeVacation()
        await service.set(request: .success(waiting))
        let (model, _) = approver(service)
        await model.load()
        let decided = VacationRequestSummary(
            id: "r1", status: .approved, start: day("2026-11-09"), end: day("2026-11-12"), countedDays: 4,
            approver: "Marco Rossi", ownerName: "Lena Meier", decidedAt: fixtureNow)
        await service.failConfirmDecision([.invalidState])
        await service.set(request: .success(decided))
        model.askToApprove()
        await model.confirmApprove()
        #expect(model.notice == .alreadyDecided && model.request?.status == .approved && !model.canDecide)
    }

    @Test("FR-VAC-004.3: a failed decision retries with the same token, a changed reason mints a new one")
    func tokenReuse() async {
        let service = FakeVacation()
        await service.set(request: .success(waiting))
        await service.failDecide([.failed(code: "INTERNAL", correlationId: nil)])
        let (model, _) = approver(service)
        await model.load()
        model.askToReject()
        model.reason = "Inventory week"
        await model.confirmReject()
        #expect(model.notice == .decisionFailed && model.request?.status == .pending)
        model.askToReject()
        model.reason = "Inventory week"
        await model.confirmReject()
        let tokens = await service.decisions.map(\.token)
        #expect(tokens == ["decision-token-1", "decision-token-1"])
        #expect(await service.calls.filter { $0 == "confirmDecision" }.count == 1)
    }

    @Test("FR-VAC-004.5: FORBIDDEN is shown as such and nothing changes")
    func forbidden() async {
        let service = FakeVacation()
        await service.set(request: .success(waiting))
        await service.failConfirmDecision([.forbidden])
        let (model, _) = approver(service)
        await model.load()
        model.askToApprove()
        await model.confirmApprove()
        #expect(model.notice == .forbidden && model.request?.status == .pending)
    }

    @Test("FR-VAC-004 (OFF): offline keeps the request visible with Approve and Reject disabled")
    func offline() async {
        let service = FakeVacation()
        await service.set(request: .failure(.offline))
        let (model, _) = approver(service)
        await model.load()
        model.askToApprove()
        #expect(model.isOffline && !model.canDecide && !model.isConfirmingApprove && model.request == waiting)
    }

    @Test("EXP-003: dismissing the approve dialog or the reject sheet reports confirm_rejected once")
    func dismissals() async throws {
        let service = FakeVacation()
        await service.set(request: .success(waiting))
        let sink = MemoryEventSink()
        let (model, _) = approver(service, sink: sink)
        await model.load()
        model.askToApprove()
        model.dismissApprove()
        model.askToReject()
        model.dismissReject()
        model.dismissReject()  // swipe-down after the button: no second event
        try await flush()
        let names = await sink.events.map(\.event)
        #expect(names == [.taskStarted, .confirmShown, .confirmRejected, .confirmShown, .confirmRejected])
        #expect(await service.decisions.isEmpty)
    }

    @Test("A11Y: a decision is not possible for the owner's own detail")
    func ownerCannotDecide() async {
        let service = FakeVacation()
        let model = RequestDetailModel(id: "r1", seed: waiting, service: service, access: access())
        await model.load()
        model.askToApprove()
        #expect(!model.canDecide && !model.isConfirmingApprove)
    }
}

@MainActor
@Suite("FR-VAC-004 inbox")
struct ManagerInboxModelTests {
    private func inbox(_ service: FakeVacation, sink: MemoryEventSink = MemoryEventSink()) -> ManagerInboxModel {
        ManagerInboxModel(
            service: service, access: access(),
            makeFlow: {
                TaskFlow(
                    taskId: "T-VAC-APR", feature: "vac", mode: .classic, context: TaskContext(participantId: UUID()),
                    sink: sink, confirmAction: .decide)
            }, now: { fixtureNow })
    }

    @Test("FR-VAC-004.1: the waiting requests and their count (the badge)")
    func loads() async {
        let service = FakeVacation()
        await service.set(inbox: .success([waiting]))
        let model = inbox(service)
        await model.begin()
        #expect(model.items == [waiting] && model.count == 1)
    }

    @Test("FR-VAC-004 (E): nothing waiting is an empty list with no badge")
    func empty() async {
        let model = inbox(FakeVacation())
        await model.begin()
        #expect(model.state == .content([]) && model.count == 0)
    }

    @Test("FR-VAC-004 (403): a non-manager gets the forbidden state")
    func forbidden() async {
        let service = FakeVacation()
        await service.set(inbox: .failure(.forbidden))
        let model = inbox(service)
        await model.begin()
        #expect(model.state == .forbidden && model.count == 0)
    }

    @Test("FR-VAC-004 (OFF): offline keeps the last list with an as-of time; no list at all is an error")
    func offline() async {
        let service = FakeVacation()
        await service.set(inbox: .success([waiting]))
        let model = inbox(service)
        await model.begin()
        await service.set(inbox: .failure(.offline))
        await model.refresh()
        #expect(model.items == [waiting] && model.offlineAsOf == fixtureNow)

        let cold = FakeVacation()
        await cold.set(inbox: .failure(.offline))
        let first = inbox(cold)
        await first.begin()
        #expect(first.state == .error(code: "OFFLINE", correlationId: nil))
    }

    @Test("T-VAC-APR: opening the inbox starts the flow; a finished flow is replaced for the next decision")
    func flowLifecycle() async throws {
        let sink = MemoryEventSink()
        let model = inbox(FakeVacation(), sink: sink)
        await model.begin()
        let first = model.currentFlow()
        #expect(first === model.currentFlow())
        first?.complete(outcomeValid: true)
        let second = model.currentFlow()
        #expect(second !== first && second?.isFinished == false)
        try await flush()
        let names = await sink.events.map(\.event)
        #expect(names == [.taskStarted, .taskCompleted, .taskStarted])
    }
}

private func absence(_ id: String, _ name: String, _ status: VacationStatus, _ start: String, _ end: String)
    -> CoverageAbsence
{
    CoverageAbsence(requestId: id, name: name, status: status, start: day(start), end: day(end))
}

private func coverageDay(_ iso: String, present: Int = 6, absent: [CoverageAbsence] = []) -> CoverageDay {
    CoverageDay(day: day(iso), present: present, total: 6, absent: absent)
}

@MainActor
private func team(_ service: FakeVacation, sink: MemoryEventSink = MemoryEventSink()) -> TeamCoverageModel {
    TeamCoverageModel(
        service: service, access: access(), today: day("2026-10-19"),
        makeFlow: {
            TaskFlow(
                taskId: "T-VAC-COV", feature: "vac", mode: .classic, context: TaskContext(participantId: UUID()),
                sink: sink)
        }, now: { fixtureNow })
}

@MainActor
@Suite("FR-VAC-005 team coverage")
struct TeamCoverageModelTests {
    private let lena = absence("a", "Lena Meier", .pending, "2026-11-09", "2026-11-12")
    private let tim = absence("b", "Tim Berger", .approved, "2026-11-11", "2026-11-13")

    @Test("FR-VAC-005.1: the default range is the next four weeks, asked of the API as such")
    func defaultRange() async {
        let service = FakeVacation()
        let model = team(service)
        #expect(model.start == day("2026-10-19") && model.end == day("2026-11-15"))
        await model.begin()
        let call = await service.coverageCalls.first
        #expect(call?.0 == day("2026-10-19") && call?.1 == day("2026-11-15"))
    }

    @Test("FR-VAC-005.1: days are grouped per ISO week; each absence is listed once per week")
    func weeks() async {
        let service = FakeVacation()
        await service.set(coverage: .success([
            coverageDay("2026-11-09", present: 5, absent: [lena]),
            coverageDay("2026-11-10", present: 5, absent: [lena]),
            coverageDay("2026-11-11", present: 4, absent: [lena, tim]),
            coverageDay("2026-11-12", present: 4, absent: [lena, tim]),
            coverageDay("2026-11-13", present: 5, absent: [tim]),
            coverageDay("2026-11-16"),
        ]))
        let model = team(service)
        await model.begin()
        #expect(model.weeks.map(\.number) == [46, 47])
        #expect(model.weeks[0].days.count == 5 && model.weeks[0].absences.map(\.name) == ["Lena Meier", "Tim Berger"])
        #expect(model.weeks[1].absences.isEmpty && !model.isEmpty)
    }

    @Test("FR-VAC-005 (E): no absence in the range is the empty state")
    func empty() async {
        let service = FakeVacation()
        await service.set(coverage: .success([coverageDay("2026-11-09"), coverageDay("2026-11-10")]))
        let model = team(service)
        await model.begin()
        #expect(model.isEmpty)
    }

    @Test("FR-VAC-005.1: a chosen range is asked as chosen, capped at the API's 93 days, never reversed")
    func rangeChange() async {
        let service = FakeVacation()
        let model = team(service)
        await model.begin()
        await model.setRange(start: day("2026-11-09"), end: day("2026-11-27"))
        #expect(model.start == day("2026-11-09") && model.end == day("2026-11-27"))
        await model.setRange(start: day("2026-11-09"), end: day("2026-01-01"))
        #expect(model.end == model.start)
        await model.setRange(start: day("2026-11-09"), end: day("2028-01-01"))
        #expect(model.end == day("2026-11-09").addingDays(92))
        #expect(await service.coverageCalls.count == 4)
    }

    @Test("FR-VAC-005.2 (403): a non-manager gets the forbidden state and the error is reported")
    func forbidden() async throws {
        let service = FakeVacation()
        await service.set(coverage: .failure(.forbidden))
        let sink = MemoryEventSink()
        let model = team(service, sink: sink)
        await model.begin()
        #expect(model.state == .forbidden)
        try await flush()
        let events = await sink.events
        #expect(events.map(\.event) == [.taskStarted, .taskError] && events.last?.code == "FORBIDDEN")
    }

    @Test("FR-VAC-005 (OFF): offline keeps the last result with an as-of time; none at all is an error")
    func offline() async {
        let service = FakeVacation()
        await service.set(coverage: .success([coverageDay("2026-11-09", present: 5, absent: [lena])]))
        let model = team(service)
        await model.begin()
        await service.set(coverage: .failure(.offline))
        await model.refresh()
        #expect(model.days.count == 1 && model.offlineAsOf == fixtureNow)

        let cold = FakeVacation()
        await cold.set(coverage: .failure(.offline))
        let first = team(cold)
        await first.begin()
        #expect(first.state == .error(code: "OFFLINE", correlationId: nil))
    }

    @Test("T-VAC-COV: started on open, completed once the API's numbers are shown, taps counted")
    func events() async throws {
        let sink = MemoryEventSink()
        let model = team(FakeVacation(), sink: sink)
        await model.begin()
        try await flush()
        let events = await sink.events
        #expect(events.map(\.event) == [.taskStarted, .taskCompleted])
        #expect(events.allSatisfy { $0.taskId == "T-VAC-COV" && $0.feature == "vac" })
        #expect(events.last?.outcomeValid == true)
    }

    @Test("FR-VAC-005.3: the approver's detail shows the team on the request's days, without the request itself")
    func presenceInDetail() async {
        let service = FakeVacation()
        await service.set(request: .success(waiting))
        await service.set(coverage: .success([
            coverageDay("2026-11-09", present: 5, absent: [absence("r1", "Lena Meier", .pending, "2026-11-09", "2026-11-12")]),
            coverageDay("2026-11-11", present: 4, absent: [
                absence("r1", "Lena Meier", .pending, "2026-11-09", "2026-11-12"), tim,
            ]),
        ]))
        let (model, _) = approver(service)
        await model.load()
        #expect(model.presence.count == 2 && model.otherAbsences.map(\.name) == ["Tim Berger"])
        let call = await service.coverageCalls.first
        #expect(call?.0 == waiting.start && call?.1 == waiting.end)
    }

    @Test("FR-VAC-005.3: no coverage (error) leaves the strip out and the decision possible")
    func presenceFailureIsHarmless() async {
        let service = FakeVacation()
        await service.set(request: .success(waiting))
        await service.set(coverage: .failure(.failed(code: "INTERNAL", correlationId: nil)))
        let (model, _) = approver(service)
        await model.load()
        #expect(model.presence.isEmpty && model.canDecide)
    }

    @Test("FR-VAC-005.2: the owner's own detail never asks for team data")
    func ownerNeverLoadsCoverage() async {
        let service = FakeVacation()
        let model = RequestDetailModel(id: "r1", seed: nil, service: service, access: access())
        await model.load()
        #expect(await service.calls == ["request"] && model.presence.isEmpty)
    }
}
