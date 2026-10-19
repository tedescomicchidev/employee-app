#if DEBUG
import Foundation

public enum VacationStubScenario: String, Sendable, CaseIterable {
    /// 25 days free, no requests (test-cases: "emp2 with 25 remaining").
    case ok
    /// Mockup numbers: 25 + 3 carried - 11 approved - 4 pending = 13, one pending request.
    case populated
    /// The "My requests" mockup: one pending, two approved, one rejected with a reason (FR-VAC-007).
    case history
    /// A pending request whose cancel fails on the server (error state of the cancel dialog).
    case cancelFails
    /// The manager's inbox with three waiting requests (FR-VAC-004 mockups).
    case manager
    case managerEmpty
    /// The first request was decided meanwhile: deciding returns `INVALID_STATE`.
    case managerDecided
    /// Approving now breaks a rule (blackout added after submission): the request stays pending.
    case managerBlocked
    case managerForbidden
    case decideFails
    /// The team coverage mockup: 6 direct reports, three weeks (FR-VAC-005).
    case team
    case teamEmpty
    case loading, offline, error, cantonMissing, submitFails, submitOffline
}

/// Stub for UI tests and screenshots (DEBUG only). It mirrors the API's rules on the fixture data of
/// docs/product/test-cases.md so flows are testable offline; `api/` stays the only real authority.
public actor StubVacationService: VacationService {
    public private(set) var submitCalls = 0
    public private(set) var proposeCalls = 0
    private let scenario: VacationStubScenario
    private var existing: [VacationRequestSummary]
    private var waiting: [VacationRequestSummary] = []
    private var decidedMeanwhile = false
    private let carriedOver: Int
    private var approved: Int
    private var pending: Int

    /// Frozen "today" of the fixtures: Monday 2026-10-19.
    public static let today = CalendarDay(year: 2026, month: 10, day: 19)

    public init(scenario: VacationStubScenario = .ok) {
        self.scenario = scenario
        if scenario == .populated || scenario == .history || scenario == .cancelFails {
            carriedOver = 3
            approved = 11
            pending = 4
            existing = [
                VacationRequestSummary(
                    id: "r1", status: .pending, start: CalendarDay(year: 2026, month: 11, day: 9),
                    end: CalendarDay(year: 2026, month: 11, day: 12), countedDays: 4, approver: "Marco Rossi",
                    submittedAt: Self.decided(10, 12))
            ]
            if scenario == .history { existing += Self.decidedHistory }
        } else {
            carriedOver = 0
            approved = 0
            pending = 0
            existing = []
        }
        switch scenario {
        case .manager, .managerDecided, .managerBlocked, .decideFails, .team: waiting = Self.managerInbox
        default: break
        }
    }

    private static let leaBalance = VacationBalance(
        year: 2026, entitlement: 25, carriedOver: 3, approved: 11, pending: 4, remaining: 13)

    /// What the API returns for a manager: waiting requests ordered by start date.
    private static let managerInbox: [VacationRequestSummary] = [
        VacationRequestSummary(
            id: "m1", status: .pending, start: CalendarDay(year: 2026, month: 11, day: 9),
            end: CalendarDay(year: 2026, month: 11, day: 12), countedDays: 4, approver: "Marco Rossi",
            ownerName: "Lena Meier", submittedAt: decided(10, 12), ownerBalance: leaBalance),
        VacationRequestSummary(
            id: "m2", status: .pending, start: CalendarDay(year: 2026, month: 11, day: 16),
            end: CalendarDay(year: 2026, month: 11, day: 20), countedDays: 5, approver: "Marco Rossi",
            ownerName: "Anna Keller", submittedAt: decided(10, 14), ownerBalance: leaBalance),
        VacationRequestSummary(
            id: "m3", status: .pending, start: CalendarDay(year: 2026, month: 11, day: 26),
            end: CalendarDay(year: 2026, month: 11, day: 27), countedDays: 2, approver: "Marco Rossi",
            ownerName: "Jonas Brunner", submittedAt: decided(10, 15), ownerBalance: leaBalance),
    ]

    private static func decided(_ month: Int, _ day: Int, hour: Int = 9, minute: Int = 0) -> Date {
        Calendar.zurich.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))
            ?? Date()
    }

    private static let decidedHistory: [VacationRequestSummary] = [
        VacationRequestSummary(
            id: "h1", status: .approved, start: CalendarDay(year: 2026, month: 7, day: 13),
            end: CalendarDay(year: 2026, month: 7, day: 24), countedDays: 10, approver: "Marco Rossi",
            decidedAt: decided(6, 2)),
        VacationRequestSummary(
            id: "h2", status: .approved, start: CalendarDay(year: 2026, month: 9, day: 18),
            end: CalendarDay(year: 2026, month: 9, day: 18), countedDays: 1, approver: "Marco Rossi",
            decidedAt: decided(9, 9)),
        VacationRequestSummary(
            id: "h3", status: .rejected, start: CalendarDay(year: 2026, month: 10, day: 5),
            end: CalendarDay(year: 2026, month: 10, day: 9), countedDays: 5, approver: "Marco Rossi",
            decidedAt: decided(9, 22), reason: "Team-Engpass in KW 41"),
    ]

    /// What the "populated" scenario last fetched, to seed the offline overview.
    public static func populatedSnapshot(userKey: String, fetchedAt: Date) -> VacationSnapshot {
        VacationSnapshot(
            userKey: userKey, fetchedAt: fetchedAt,
            balance: VacationBalance(year: today.year, entitlement: 25, carriedOver: 3, approved: 11, pending: 4, remaining: 13),
            requests: [
                VacationRequestSummary(
                    id: "r1", status: .pending, start: CalendarDay(year: 2026, month: 11, day: 9),
                    end: CalendarDay(year: 2026, month: 11, day: 12), countedDays: 4, approver: "Marco Rossi")
            ])
    }

    private var balanceNow: VacationBalance {
        VacationBalance(
            year: Self.today.year, entitlement: 25, carriedOver: carriedOver, approved: approved,
            pending: pending, remaining: 25 + carriedOver - approved - pending)
    }

    public func balance(accessToken: String) async throws -> VacationBalance {
        try await gate()
        return balanceNow
    }

    public func requests(accessToken: String) async throws -> [VacationRequestSummary] {
        try await gate()
        return existing
    }

    public func holidays(year: Int, accessToken: String) async throws -> VacationHolidays {
        try await gate()
        if scenario == .cantonMissing { throw VacationError.cantonMissing }
        return VacationHolidays(
            year: year, canton: "ZH", items: Self.holidayTable.filter { $0.day.year == year },
            needsConfirmation: true)
    }

    public func propose(start: CalendarDay, end: CalendarDay, accessToken: String) async throws -> VacationProposal {
        try await gate()
        proposeCalls += 1
        if scenario == .cantonMissing { throw VacationError.cantonMissing }
        let (counted, perYear, excluded) = Self.count(start, end)
        let after = balanceNow.remaining - (perYear[start.year] ?? 0)
        let review = VacationReview(
            countedDays: counted, perYear: perYear, excluded: excluded, remaining: balanceNow.remaining,
            remainingAfter: after, balanceYear: start.year, approver: "Marco Rossi")
        let violations = rules(start, end, counted: end < start ? nil : counted)
        if !violations.isEmpty { throw VacationError.rules(violations, review: end < start ? nil : review) }
        return VacationProposal(id: "stub-proposal", start: start, end: end, review: review)
    }

    public func confirm(_ proposal: VacationProposal, accessToken: String) async throws -> String { "stub-token" }

    public func submit(
        start: CalendarDay, end: CalendarDay, confirmationToken: String, accessToken: String
    ) async throws -> VacationRequestSummary {
        submitCalls += 1
        switch scenario {
        case .submitFails: throw VacationError.failed(code: "INTERNAL", correlationId: "stub-corr-1234")
        case .offline, .submitOffline: throw VacationError.offline
        default: break
        }
        // Idempotent on the token: a replay returns the stored request.
        if let stored = existing.first(where: { $0.id == "stub-\(confirmationToken)" }) { return stored }
        let (counted, _, _) = Self.count(start, end)
        let request = VacationRequestSummary(
            id: "stub-\(confirmationToken)", status: .pending, start: start, end: end, countedDays: counted,
            approver: "Marco Rossi")
        existing.append(request)
        pending += counted
        return request
    }

    public func request(id: String, accessToken: String) async throws -> VacationRequestSummary {
        try await gate()
        if let found = existing.first(where: { $0.id == id }) { return found }
        guard let found = waiting.first(where: { $0.id == id }) ?? Self.managerInbox.first(where: { $0.id == id })
        else { throw VacationError.notFound }
        if decidedMeanwhile {
            return Self.copy(found, status: .approved, decidedAt: Self.decided(10, 17, hour: 16, minute: 58))
        }
        return found
    }

    public func coverage(start: CalendarDay?, end: CalendarDay?, accessToken: String) async throws -> [CoverageDay] {
        try await gate()
        if scenario == .managerForbidden { throw VacationError.forbidden }
        let first = start ?? Self.today
        let last = end ?? first.addingDays(27)
        let absences: [CoverageAbsence] = scenario == .teamEmpty ? [] : Self.teamAbsences
        var days: [CoverageDay] = []
        var day = first
        while day <= last, days.count < 100 {
            if Calendar.zurich.component(.weekday, from: day.date()) % 7 > 1 {
                let out = absences.filter { $0.start <= day && day <= $0.end }
                days.append(CoverageDay(day: day, present: 6 - Set(out.map(\.name)).count, total: 6, absent: out))
            }
            day = day.addingDays(1)
        }
        return days
    }

    /// Mockup data: Lena (pending) and Tim (approved) in week 46, Anna in 47, Jonas Thu and Fri in 48.
    private static let teamAbsences: [CoverageAbsence] = [
        CoverageAbsence(
            requestId: "m1", name: "Lena Meier", status: .pending, start: CalendarDay(year: 2026, month: 11, day: 9),
            end: CalendarDay(year: 2026, month: 11, day: 12)),
        CoverageAbsence(
            requestId: "t1", name: "Tim Berger", status: .approved, start: CalendarDay(year: 2026, month: 11, day: 11),
            end: CalendarDay(year: 2026, month: 11, day: 13)),
        CoverageAbsence(
            requestId: "m2", name: "Anna Keller", status: .pending, start: CalendarDay(year: 2026, month: 11, day: 16),
            end: CalendarDay(year: 2026, month: 11, day: 20)),
        CoverageAbsence(
            requestId: "m3", name: "Jonas Brunner", status: .pending, start: CalendarDay(year: 2026, month: 11, day: 26),
            end: CalendarDay(year: 2026, month: 11, day: 27)),
    ]

    public func inbox(accessToken: String) async throws -> [VacationRequestSummary] {
        try await gate()
        if scenario == .managerForbidden { throw VacationError.forbidden }
        return waiting
    }

    public func confirmDecision(
        id: String, decision: VacationDecision, reason: String?, accessToken: String
    ) async throws -> String {
        try await gate()
        guard waiting.contains(where: { $0.id == id }) else { throw VacationError.notFound }
        switch scenario {
        case .managerDecided:
            decidedMeanwhile = true
            throw VacationError.invalidState
        case .managerBlocked where decision == .approve:
            throw VacationError.rules(
                [VacationViolation(
                    code: "BLACKOUT",
                    range: DayRange(
                        start: CalendarDay(year: 2026, month: 11, day: 10),
                        end: CalendarDay(year: 2026, month: 11, day: 13)))],
                review: nil)
        case .decideFails: throw VacationError.failed(code: "INTERNAL", correlationId: "stub-corr-3456")
        default: return "stub-decision-\(id)"
        }
    }

    public func decide(
        id: String, decision: VacationDecision, reason: String?, confirmationToken: String, accessToken: String
    ) async throws -> VacationRequestSummary {
        try await gate()
        guard let index = waiting.firstIndex(where: { $0.id == id }) else {
            // Idempotent on the token: the already stored decision.
            if let done = existing.first(where: { $0.id == id }) { return done }
            throw VacationError.notFound
        }
        let current = waiting.remove(at: index)
        let decided = Self.copy(
            current, status: decision == .approve ? .approved : .rejected, decidedAt: Self.fixtureNow,
            reason: decision == .reject ? reason : nil)
        existing.append(decided)
        return decided
    }

    private static func copy(
        _ r: VacationRequestSummary, status: VacationStatus, decidedAt: Date, reason: String? = nil
    ) -> VacationRequestSummary {
        VacationRequestSummary(
            id: r.id, status: status, start: r.start, end: r.end, countedDays: r.countedDays,
            approver: r.approver, ownerName: r.ownerName, decidedAt: decidedAt, reason: reason,
            submittedAt: r.submittedAt, ownerBalance: r.ownerBalance)
    }

    public func confirmCancel(id: String, accessToken: String) async throws -> String {
        try await gate()
        if scenario == .cancelFails { throw VacationError.failed(code: "INTERNAL", correlationId: "stub-corr-9012") }
        guard let found = existing.first(where: { $0.id == id }) else { throw VacationError.notFound }
        if found.status != .pending { throw VacationError.invalidState }
        return "stub-cancel-\(id)"
    }

    public func cancel(id: String, confirmationToken: String, accessToken: String) async throws
        -> VacationRequestSummary
    {
        try await gate()
        guard let index = existing.firstIndex(where: { $0.id == id }) else { throw VacationError.notFound }
        let current = existing[index]
        if current.status == .cancelled { return current }  // idempotent on the token
        if current.status != .pending { throw VacationError.invalidState }
        let cancelled = VacationRequestSummary(
            id: current.id, status: .cancelled, start: current.start, end: current.end,
            countedDays: current.countedDays, approver: current.approver, decidedAt: Self.fixtureNow)
        existing[index] = cancelled
        pending -= current.countedDays
        return cancelled
    }

    private static let fixtureNow = Calendar.zurich.date(
        from: DateComponents(year: 2026, month: 10, day: 19, hour: 8)) ?? Date()

    // MARK: Stub rules (fixture data only)

    private func gate() async throws {
        switch scenario {
        case .loading:
            try await Task.sleep(for: .seconds(3600))
        case .offline: throw VacationError.offline
        case .error: throw VacationError.failed(code: "INTERNAL", correlationId: "stub-corr-5678")
        default: break
        }
    }

    private func rules(_ start: CalendarDay, _ end: CalendarDay, counted: Int?) -> [VacationViolation] {
        if end < start { return [VacationViolation(code: "INVALID_RANGE")] }
        var found: [VacationViolation] = []
        if start < Self.today { found.append(VacationViolation(code: "PAST_DATE")) }
        if counted == 0 { found.append(VacationViolation(code: "ZERO_DAYS")) }
        let blackout = DayRange(
            start: CalendarDay(year: 2026, month: 12, day: 14), end: CalendarDay(year: 2026, month: 12, day: 24))
        if start <= blackout.end, blackout.start <= end {
            found.append(VacationViolation(code: "BLACKOUT", range: blackout))
        }
        let clashes = existing.filter { $0.status == .pending || $0.status == .approved }
            .filter { start <= $0.end && $0.start <= end }
        if !clashes.isEmpty {
            found.append(VacationViolation(code: "OVERLAP", conflicts: clashes.map { DayRange(start: $0.start, end: $0.end) }))
        }
        if let counted, counted > balanceNow.remaining {
            found.append(VacationViolation(code: "INSUFFICIENT_BALANCE", remaining: balanceNow.remaining, requested: counted))
        }
        return found
    }

    private static let holidayTable: [VacationHoliday] = [
        VacationHoliday(day: CalendarDay(year: 2026, month: 11, day: 11), name: "Fixture Day ZH"),
        VacationHoliday(day: CalendarDay(year: 2026, month: 12, day: 25), name: "Weihnachtstag"),
        VacationHoliday(day: CalendarDay(year: 2027, month: 1, day: 1), name: "Neujahr"),
    ]

    private static func count(_ start: CalendarDay, _ end: CalendarDay) -> (Int, [Int: Int], [ExcludedDay]) {
        var perYear: [Int: Int] = [:]
        var excluded: [ExcludedDay] = []
        var day = start
        var guardCount = 0
        while day <= end, guardCount < 800 {
            let weekday = Calendar.zurich.component(.weekday, from: day.date())
            if weekday == 1 || weekday == 7 {
                excluded.append(ExcludedDay(day: day, kind: .weekend))
            } else if let holiday = holidayTable.first(where: { $0.day == day }) {
                excluded.append(ExcludedDay(day: day, kind: .holiday, name: holiday.name))
            } else {
                perYear[day.year, default: 0] += 1
            }
            day = day.addingDays(1)
            guardCount += 1
        }
        return (perYear.values.reduce(0, +), perYear, excluded)
    }
}
#endif
