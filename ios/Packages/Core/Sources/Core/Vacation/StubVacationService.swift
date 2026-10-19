#if DEBUG
import Foundation

public enum VacationStubScenario: String, Sendable, CaseIterable {
    /// 25 days free, no requests (test-cases: "emp2 with 25 remaining").
    case ok
    /// Mockup numbers: 25 + 3 carried - 11 approved - 4 pending = 13, one pending request.
    case populated
    case loading, offline, error, cantonMissing, submitFails, submitOffline
}

/// Stub for UI tests and screenshots (DEBUG only). It mirrors the API's rules on the fixture data of
/// docs/product/test-cases.md so flows are testable offline; `api/` stays the only real authority.
public actor StubVacationService: VacationService {
    public private(set) var submitCalls = 0
    public private(set) var proposeCalls = 0
    private let scenario: VacationStubScenario
    private var existing: [VacationRequestSummary]
    private let carriedOver: Int
    private var approved: Int
    private var pending: Int

    /// Frozen "today" of the fixtures: Monday 2026-10-19.
    public static let today = CalendarDay(year: 2026, month: 10, day: 19)

    public init(scenario: VacationStubScenario = .ok) {
        self.scenario = scenario
        if scenario == .populated {
            carriedOver = 3
            approved = 11
            pending = 4
            existing = [
                VacationRequestSummary(
                    id: "r1", status: .pending, start: CalendarDay(year: 2026, month: 11, day: 9),
                    end: CalendarDay(year: 2026, month: 11, day: 12), countedDays: 4, approver: "Marco Rossi")
            ]
        } else {
            carriedOver = 0
            approved = 0
            pending = 0
            existing = []
        }
    }

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
