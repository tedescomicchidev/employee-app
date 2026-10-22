import Foundation
import Testing
import UserNotifications
@testable import Core

private let weekBody = """
{"week_start":"2026-10-19","week_end":"2026-10-25","timezone":"Europe/Zurich","event_count":2,"conflict_count":1,
 "partial":true,"missing_days":["2026-10-22"],
 "days":[
  {"date":"2026-10-19","events":[
    {"id":"e1","title":"Team standup","start":"2026-10-19T09:00:00+02:00","end":"2026-10-19T09:30:00+02:00",
     "all_day":false,"location":"Room 4","online":true,"attendee_count":6,"conflicts_with":["e2"]},
    {"id":"e2","title":"Budget review","start":"2026-10-19T09:15:00+02:00","end":"2026-10-19T10:15:00+02:00",
     "all_day":false,"location":"","online":false,"attendee_count":3,"conflicts_with":["e1"]}],
   "free_blocks":[{"start":"2026-10-19T10:15:00+02:00","end":"2026-10-19T18:00:00+02:00","minutes":465}]},
  {"date":"2026-10-22","events":[],"free_blocks":[]}]}
"""

/// Its own canned responder: the vacation suite has one with a static answer, and suites run in parallel.
private final class BriefingCannedURLProtocol: URLProtocol, @unchecked Sendable {
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

@Suite("FR-BRF-001/002/005 REST mapping", .serialized)
struct BriefingRESTTests {
    private func service(_ status: Int, _ body: String) -> URLSessionBriefingService {
        BriefingCannedURLProtocol.response = (status, body)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BriefingCannedURLProtocol.self]
        return URLSessionBriefingService(
            baseURL: URL(string: "https://api.example.test")!, session: URLSession(configuration: configuration))
    }

    @Test("FR-BRF-002: the week is decoded as api/ sent it, and a missing day is named")
    func week() async throws {
        let week = try await service(200, weekBody).week(accessToken: "t")
        #expect(week.eventCount == 2 && week.conflictCount == 1)
        #expect(week.start.iso == "2026-10-19" && week.end.iso == "2026-10-25")
        let monday = try #require(week.days.first)
        #expect(monday.events.map(\.title) == ["Team standup", "Budget review"])
        #expect(monday.events[0].hasConflict && monday.events[0].conflictsWith == ["e2"])
        #expect(monday.events[0].online && monday.events[0].attendeeCount == 6)
        #expect(monday.freeBlocks.first?.minutes == 465)
        // 09:00 at +02:00 is 07:00 UTC: an instant, shown in Zurich time by the views.
        #expect(monday.events[0].start == ISO8601DateFormatter().date(from: "2026-10-19T07:00:00Z"))
        #expect(week.isPartial && week.missingDays.map(\.day.iso) == ["2026-10-22"])
        #expect(!week.isEmpty)
    }

    @Test("FR-BRF-005.2: no events is an empty briefing, not an error")
    func empty() async throws {
        let body = #"{"week_start":"2026-10-19","week_end":"2026-10-25","event_count":0,"conflict_count":0,"partial":false,"missing_days":[],"days":[{"date":"2026-10-19","events":[],"free_blocks":[]}]}"#
        let week = try await service(200, body).week(accessToken: "t")
        #expect(week.isEmpty && !week.isPartial)
    }

    @Test("FR-BRF-005.1: each failure has its own error", arguments: [
        (403, #"{"code":"NOT_OPTED_IN"}"#, BriefingError.notOptedIn),
        (403, #"{"code":"CONSENT_REQUIRED"}"#, BriefingError.consentRequired),
        (403, #"{"code":"NO_LICENCE"}"#, BriefingError.noLicence),
        (403, #"{"code":"NOT_PROVISIONED"}"#, BriefingError.notProvisioned),
        (503, #"{"code":"WORKIQ_UNAVAILABLE"}"#, BriefingError.workIQUnavailable),
        (401, #"{"code":"UNAUTHENTICATED"}"#, BriefingError.unauthenticated),
        (409, #"{"code":"INVALID_CONFIRMATION"}"#, BriefingError.invalidConfirmation),
    ])
    func errors(status: Int, body: String, expected: BriefingError) async {
        await #expect(throws: expected) { _ = try await service(status, body).week(accessToken: "t") }
    }

    @Test("FR-BRF-005.1: an unknown failure keeps its code for the details line")
    func unknown() async {
        await #expect(throws: BriefingError.failed(code: "X", correlationId: nil)) {
            _ = try await service(500, #"{"code":"X"}"#).week(accessToken: "t")
        }
    }

    @Test("FR-BRF-001: status and the opt-in write")
    func optIn() async throws {
        let on = service(200, #"{"opted_in":true,"opted_in_at":"2026-10-19T06:00:00+00:00"}"#)
        #expect(try await on.status(accessToken: "t") == BriefingStatus(optedIn: true))
        #expect(try await on.setOptIn(enabled: true, confirmationToken: "c", accessToken: "t").optedIn)
        let proposal = try await service(200, #"{"proposal_id":"p-1","type":"briefing"}"#)
            .proposeOptIn(enabled: true, accessToken: "t")
        #expect(proposal == BriefingOptInProposal(id: "p-1", enabled: true))
        let token = try await service(200, #"{"confirmation_token":"tok","expires_at":"x"}"#)
            .confirmOptIn(proposal, accessToken: "t")
        #expect(token == "tok")
    }

    @Test("FR-BRF-005: a service that is down is not reported as offline")
    func timeout() {
        #expect(BriefingError.timedOut.code == "TIMEOUT")
        #expect(BriefingError.noLicence.code == "NO_LICENCE")
        #expect(BriefingError.consentRequired.code == "CONSENT_REQUIRED")
    }
}

/// A notification centre that records what was scheduled.
private actor FakeCentre: NotificationCentre {
    var state: NotificationAuthorization
    var scheduled: [(identifier: String, title: String)] = []
    var cancelled: [String] = []

    init(_ state: NotificationAuthorization) { self.state = state }

    func authorization() async -> NotificationAuthorization { state }
    func requestAuthorization() async -> Bool {
        if state == .notDetermined { state = .allowed }
        return state == .allowed
    }
    func scheduleWeekly(identifier: String, title: String) async throws {
        scheduled.removeAll { $0.identifier == identifier }
        scheduled.append((identifier, title))
    }
    func cancel(identifiers: [String]) async {
        cancelled += identifiers
        scheduled.removeAll { identifiers.contains($0.identifier) }
    }
    func pendingIdentifiers() async -> [String] { scheduled.map(\.identifier) }
}

@Suite("FR-BRF-003 Monday reminder")
struct BriefingReminderTests {
    @Test("FR-BRF-003.1: a weekly trigger on Monday 07:00 in Zurich, text only")
    func trigger() throws {
        let trigger = BriefingReminder.trigger()
        #expect(trigger.repeats)
        #expect(trigger.dateComponents.weekday == 2)
        #expect(trigger.dateComponents.hour == 7 && trigger.dateComponents.minute == 0)
        #expect(trigger.dateComponents.timeZone?.identifier == "Europe/Zurich")
        let request = BriefingReminder.request(title: "Your week is ready")
        #expect(request.identifier == BriefingReminder.identifier)
        #expect(request.content.title == "Your week is ready")
        #expect(request.content.body.isEmpty && request.content.subtitle.isEmpty)
        // No calendar content can be in it: the only payload is the route.
        #expect(request.content.userInfo as? [String: String] == ["route": "briefing"])
    }

    @Test("FR-BRF-003.1: it stays 07:00 local time across the 2026-10-25 clock change")
    func daylightSavingTime() throws {
        let trigger = BriefingReminder.trigger()
        let calendar = Calendar.zurich
        let formatter = ISO8601DateFormatter()
        let before = try #require(formatter.date(from: "2026-10-19T08:00:00Z"))
        let first = try #require(calendar.nextDate(
            after: before, matching: trigger.dateComponents, matchingPolicy: .nextTime))
        let second = try #require(calendar.nextDate(
            after: first, matching: trigger.dateComponents, matchingPolicy: .nextTime))
        func local(_ date: Date) -> DateComponents {
            calendar.dateComponents([.weekday, .hour, .minute, .day, .month], from: date)
        }
        #expect(local(first).day == 26 && local(first).month == 10)  // the Monday after the change
        #expect(local(first).hour == 7 && local(first).weekday == 2)
        #expect(local(second).day == 2 && local(second).month == 11 && local(second).hour == 7)
        // 07:00 CET is 06:00 UTC, and a week before it was 07:00 CEST = 05:00 UTC.
        #expect(formatter.string(from: first) == "2026-10-26T06:00:00Z")
        let summer = try #require(calendar.nextDate(
            after: formatter.date(from: "2026-10-12T08:00:00Z")!, matching: trigger.dateComponents, matchingPolicy: .nextTime))
        #expect(formatter.string(from: summer) == "2026-10-19T05:00:00Z")
    }

    @Test("FR-BRF-003.1: scheduled when allowed, replacing the pending one; nothing when denied")
    func schedule() async {
        let allowed = FakeCentre(.allowed)
        let reminder = BriefingReminder(centre: allowed)
        #expect(await reminder.schedule(title: "A"))
        #expect(await reminder.schedule(title: "B"))
        #expect(await allowed.scheduled.map(\.title) == ["B"])  // never two
        #expect(await reminder.isScheduled())
        let denied = FakeCentre(.denied)
        #expect(await BriefingReminder(centre: denied).schedule(title: "A") == false)
        #expect(await denied.scheduled.isEmpty)
    }

    @Test("FR-BRF-003.3: cancel removes the pending reminder")
    func cancel() async {
        let centre = FakeCentre(.allowed)
        let reminder = BriefingReminder(centre: centre)
        await reminder.schedule(title: "A")
        await reminder.cancel()
        #expect(await reminder.isScheduled() == false)
        #expect(await centre.cancelled.contains(BriefingReminder.identifier))
    }

    @Test("FR-BRF-003: the first ask comes from the app, once")
    func ask() async {
        let centre = FakeCentre(.notDetermined)
        let reminder = BriefingReminder(centre: centre)
        #expect(await reminder.authorization() == .notDetermined)
        #expect(await reminder.requestAuthorization())
        #expect(await reminder.authorization() == .allowed)
    }
}

@Suite("FR-BRF AGENT decoding")
struct BriefingAgentDecodingTests {
    @Test("FR-BRF-002 AGENT: a summary carries the count of events it left out")
    func summary() throws {
        let data = #"{"reply":{"kind":"summary","text":"6 events","omitted_count":2},"tool_calls":[{"name":"get_my_week","ok":true}]}"#
        let decoded = try URLSessionAgentService.decode(SSEEvent(name: "final", data: data))
        guard case let .event(.final(result)) = decoded else { Issue.record("not final"); return }
        #expect(result.reply.kind == .summary && result.reply.omittedCount == 2)
        #expect(result.toolCalls == [AgentToolCall(name: "get_my_week", ok: true)])
    }

    @Test("FR-BRF-001 AGENT: an opted-in reply is a write result")
    func optedIn() {
        #expect(AgentReplyKind.optedIn.isWriteResult && !AgentReplyKind.summary.isWriteResult)
        #expect(AgentReplyKind(rawValue: "opted_in") == .optedIn)
    }

    @Test("FR-BRF-004 AGENT: a refusal keeps the other-calendar reason")
    func refusal() throws {
        let data = #"{"reply":{"kind":"refusal","text":"Only your own calendar.","reason":"other_users_data"},"tool_calls":[]}"#
        let decoded = try URLSessionAgentService.decode(SSEEvent(name: "final", data: data))
        guard case let .event(.final(result)) = decoded else { Issue.record("not final"); return }
        #expect(result.reply.kind == .refusal && result.reply.reason == "other_users_data")
    }
}
