import Foundation
import Testing
@testable import Core

@Suite("FR-VAC-002 business dates")
struct CalendarDayTests {
    @Test("FR-VAC-002: ISO round trip and ordering")
    func isoRoundTrip() throws {
        let day = try #require(CalendarDay(iso: "2026-11-23"))
        #expect(day.iso == "2026-11-23")
        #expect(day < CalendarDay(year: 2026, month: 12, day: 1))
        #expect(CalendarDay(iso: "2026-13-01") == nil)
        #expect(CalendarDay(iso: "nonsense") == nil)
    }

    @Test("FR-VAC-002: adding days across the 2026-10-25 clock change never shifts a date")
    func dstSafe() {
        let friday = CalendarDay(year: 2026, month: 10, day: 23)
        #expect(friday.addingDays(2) == CalendarDay(year: 2026, month: 10, day: 25))
        #expect(friday.addingDays(5) == CalendarDay(year: 2026, month: 10, day: 28))
        #expect(CalendarDay(year: 2026, month: 12, day: 31).addingDays(1) == CalendarDay(year: 2027, month: 1, day: 1))
    }

    @Test("FR-VAC-002: a date built from an instant uses the Zurich calendar day")
    func zurichDay() throws {
        // 2026-11-22 23:30 UTC is already 2026-11-23 in Zurich (UTC+1).
        let instant = try #require(ISO8601DateFormatter().date(from: "2026-11-22T23:30:00Z"))
        #expect(CalendarDay(date: instant).iso == "2026-11-23")
    }
}

@MainActor
@Suite("FR-VAC-002 experiment events")
struct VacationTaskFlowTests {
    @Test("EXP-003: confirm events of the vacation flow report the request action")
    func confirmAction() async throws {
        let sink = MemoryEventSink()
        let flow = TaskFlow(
            taskId: "T-VAC-REQ", feature: "vac", mode: .classic, context: TaskContext(participantId: UUID()),
            sink: sink, confirmAction: .request)
        flow.start()
        flow.confirmShown()
        flow.confirmAccepted()
        flow.complete(outcomeValid: true)
        try await Task.sleep(for: .milliseconds(50))
        let events = await sink.events
        #expect(events.map(\.event) == [.taskStarted, .confirmShown, .confirmAccepted, .taskCompleted])
        #expect(events.filter { $0.event == .confirmShown || $0.event == .confirmAccepted }.allSatisfy { $0.action == .request })
        #expect(events.allSatisfy { $0.taskId == "T-VAC-REQ" && $0.feature == "vac" })
    }
}

/// Answers every request with a canned response so the REST mapping can be tested without a server.
final class CannedURLProtocol: URLProtocol, @unchecked Sendable {
    // Test-only global; the suite below is serialized, so there is no concurrent access.
    nonisolated(unsafe) static var response: (status: Int, body: String) = (200, "{}")

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let http = HTTPURLResponse(
            url: request.url!, statusCode: Self.response.status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(Self.response.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Suite("FR-VAC-001/002/006 REST mapping", .serialized)
struct VacationRESTTests {
    private func service(_ status: Int, _ body: String) -> URLSessionVacationService {
        CannedURLProtocol.response = (status, body)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CannedURLProtocol.self]
        return URLSessionVacationService(
            baseURL: URL(string: "https://api.example.test")!, session: URLSession(configuration: configuration))
    }

    @Test("FR-VAC-001: the five numbers are decoded as sent")
    func balance() async throws {
        let body = #"{"year":2026,"entitlement":25,"carried_over":3,"approved":11,"pending":4,"remaining":13}"#
        let balance = try await service(200, body).balance(accessToken: "t")
        #expect(balance == VacationBalance(year: 2026, entitlement: 25, carriedOver: 3, approved: 11, pending: 4, remaining: 13))
    }

    @Test("FR-VAC-007.1: status, decision date and rejection reason are decoded")
    func history() async throws {
        let body = """
        {"items":[{"id":"a","status":"rejected","start":"2026-03-02","end":"2026-03-04","counted_days":3,
        "approver":"Maria Keller","owner_name":"Anna Meier","decided_at":"2026-02-20T09:00:00+00:00",
        "reason":"Inventory week","per_year":{"2026":3},"excluded":[]},
        {"id":"b","status":"pending","start":"2026-12-28","end":"2026-12-30","counted_days":3,
        "approver":"Maria Keller","decided_at":null,"reason":null}]}
        """
        let items = try await service(200, body).requests(accessToken: "t")
        #expect(items.map(\.status) == [.rejected, .pending])
        #expect(items[0].reason == "Inventory week" && items[0].ownerName == "Anna Meier")
        #expect(items[0].decidedAt == Date(timeIntervalSince1970: 1_771_578_000))
        #expect(items[1].decidedAt == nil && items[1].reason == nil)
    }

    @Test("FR-VAC-002.2: every failing code arrives in order, with the blocked review")
    func rules() async throws {
        let body = """
        {"code":"PAST_DATE","message":"x","codes":["PAST_DATE","INSUFFICIENT_BALANCE"],
         "violations":[{"code":"PAST_DATE","today":"2026-10-19"},
                       {"code":"INSUFFICIENT_BALANCE","remaining":3,"requested":5,"year":2026}],
         "review":{"counted_days":5,"per_year":{"2026":5},"excluded":[],"remaining":3,"balance_year":2026}}
        """
        do {
            _ = try await service(422, body).propose(
                start: CalendarDay(year: 2026, month: 10, day: 12), end: CalendarDay(year: 2026, month: 10, day: 16),
                accessToken: "t")
            Issue.record("expected a rule error")
        } catch let VacationError.rules(violations, review) {
            #expect(violations.map(\.code) == ["PAST_DATE", "INSUFFICIENT_BALANCE"])
            #expect(violations.last?.requested == 5 && violations.last?.remaining == 3)
            #expect(review?.countedDays == 5 && review?.remaining == 3)
            #expect(VacationError.rules(violations, review: review).code == "PAST_DATE")
        }
    }

    @Test("FR-VAC-002.2: overlap and blackout carry the conflicting dates")
    func ranges() async throws {
        let body = """
        {"code":"BLACKOUT","codes":["BLACKOUT","OVERLAP"],
         "violations":[{"code":"BLACKOUT","start":"2026-12-14","end":"2026-12-24"},
                       {"code":"OVERLAP","conflicts":[{"start":"2026-11-02","end":"2026-11-06"}]}]}
        """
        do {
            _ = try await service(422, body).propose(
                start: CalendarDay(year: 2026, month: 12, day: 21), end: CalendarDay(year: 2026, month: 12, day: 23),
                accessToken: "t")
            Issue.record("expected a rule error")
        } catch let VacationError.rules(violations, review) {
            #expect(violations[0].range == DayRange(start: CalendarDay(year: 2026, month: 12, day: 14), end: CalendarDay(year: 2026, month: 12, day: 24)))
            #expect(violations[1].conflicts == [DayRange(start: CalendarDay(year: 2026, month: 11, day: 2), end: CalendarDay(year: 2026, month: 11, day: 6))])
            #expect(review == nil)
        }
    }

    @Test("FR-VAC-006: holidays and the confirmation flag are decoded")
    func holidays() async throws {
        let body = """
        {"year":2026,"canton":"TI","status":"HUMAN_CONFIRMATION_REQUIRED",
         "holidays":[{"canton":"TI","date":"2026-11-12","name":"Fixture Day TI","names":{"en":"Fixture Day TI"},"full_day":true}]}
        """
        let result = try await service(200, body).holidays(year: 2026, accessToken: "t")
        #expect(result.canton == "TI" && result.needsConfirmation)
        #expect(result.items == [VacationHoliday(day: CalendarDay(year: 2026, month: 11, day: 12), name: "Fixture Day TI")])
    }

    @Test("FR-VAC-006: a missing canton and the other error codes map to their own cases")
    func errorCodes() async {
        func error(_ status: Int, _ code: String) async -> VacationError? {
            do {
                _ = try await service(status, #"{"code":"\#(code)","message":"x"}"#).holidays(year: 2026, accessToken: "t")
                return nil
            } catch { return error as? VacationError }
        }
        #expect(await error(422, "CANTON_MISSING") == .cantonMissing)
        #expect(await error(422, "NO_APPROVER") == .noApprover)
        #expect(await error(403, "NOT_PROVISIONED") == .notProvisioned)
        #expect(await error(403, "FORBIDDEN") == .forbidden)
        #expect(await error(401, "UNAUTHENTICATED") == .unauthenticated)
        #expect(await error(409, "INVALID_CONFIRMATION") == .invalidConfirmation)
        #expect(await error(500, "INTERNAL") == .failed(code: "INTERNAL", correlationId: nil))
    }
}

@Suite("NFR-007 vacation cache")
struct VacationCacheTests {
    private let snapshot = VacationSnapshot(
        userKey: "u1", fetchedAt: Date(timeIntervalSince1970: 1_000),
        balance: VacationBalance(year: 2026, entitlement: 25, carriedOver: 0, approved: 5, pending: 0, remaining: 20),
        requests: [])

    @Test("FR-VAC-001: another account never sees a stored overview, and sign-out clears it")
    func perUser() async {
        let cache = VacationCache()
        await cache.save(snapshot)
        #expect(await cache.load(userKey: "u1") == snapshot)
        #expect(await cache.load(userKey: "u2") == nil)
        await cache.clear()
        #expect(await cache.load(userKey: "u1") == nil)
    }
}
