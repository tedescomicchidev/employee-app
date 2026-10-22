import Foundation

/// REST adapter for FR-BRF-001/002/005. Sends the user's bearer token; never logs bodies or tokens, and
/// never keeps a response: the week is held in memory by the screen that asked for it (PRIV-003).
public struct URLSessionBriefingService: BriefingService {
    private let baseURL: URL
    private let session: URLSession
    private let weekTimeout: TimeInterval

    /// `weekTimeout`: Work IQ takes 40-60 s, so the request waits longer than the usual 30 s.
    public init(baseURL: URL, session: URLSession = .shared, weekTimeout: TimeInterval = 90) {
        self.baseURL = baseURL
        self.session = session
        self.weekTimeout = weekTimeout
    }

    // MARK: Wire types

    private struct StatusResponse: Decodable { let optedIn: Bool
        enum CodingKeys: String, CodingKey { case optedIn = "opted_in" }
    }
    struct EventResponse: Decodable {
        let id: String, title: String, start: String, end: String
        let allDay: Bool, location: String, online: Bool, attendeeCount: Int
        let conflictsWith: [String]
        enum CodingKeys: String, CodingKey {
            case id, title, start, end, location, online
            case allDay = "all_day", attendeeCount = "attendee_count", conflictsWith = "conflicts_with"
        }
    }
    struct FreeResponse: Decodable { let start: String, end: String, minutes: Int }
    struct DayResponse: Decodable {
        let date: String
        let events: [EventResponse]
        let freeBlocks: [FreeResponse]
        enum CodingKeys: String, CodingKey { case date, events, freeBlocks = "free_blocks" }
    }
    struct WeekResponse: Decodable {
        let weekStart: String, weekEnd: String
        let eventCount: Int, conflictCount: Int
        let missingDays: [String]
        let days: [DayResponse]
        enum CodingKeys: String, CodingKey {
            case days
            case weekStart = "week_start", weekEnd = "week_end", eventCount = "event_count"
            case conflictCount = "conflict_count", missingDays = "missing_days"
        }
    }
    private struct ProposalBody: Encodable {
        struct Payload: Encodable { let enabled: Bool }
        let type = "briefing"
        let payload: Payload
    }
    private struct ProposalResponse: Decodable {
        let proposalId: String
        enum CodingKeys: String, CodingKey { case proposalId = "proposal_id" }
    }
    private struct ConfirmBody: Encodable {
        let type = "briefing"
        let proposalId: String
        enum CodingKeys: String, CodingKey { case type, proposalId = "proposal_id" }
    }
    private struct TokenResponse: Decodable {
        let confirmationToken: String
        enum CodingKeys: String, CodingKey { case confirmationToken = "confirmation_token" }
    }
    private struct OptInBody: Encodable {
        let enabled: Bool
        let confirmationToken: String
        enum CodingKeys: String, CodingKey { case enabled, confirmationToken = "confirmation_token" }
    }
    private struct ErrorBody: Decodable { let code: String? }

    // MARK: BriefingService

    public func status(accessToken: String) async throws -> BriefingStatus {
        let r: StatusResponse = try await send("GET", "v1/briefing/status", Optional<ProposalBody>.none, accessToken)
        return BriefingStatus(optedIn: r.optedIn)
    }

    public func week(accessToken: String) async throws -> BriefingWeek {
        let r: WeekResponse = try await send(
            "GET", "v1/briefing/week", Optional<ProposalBody>.none, accessToken, timeout: weekTimeout)
        return try Self.week(r)
    }

    public func proposeOptIn(enabled: Bool, accessToken: String) async throws -> BriefingOptInProposal {
        let r: ProposalResponse = try await send(
            "POST", "v1/proposals", ProposalBody(payload: .init(enabled: enabled)), accessToken)
        return BriefingOptInProposal(id: r.proposalId, enabled: enabled)
    }

    public func confirmOptIn(_ proposal: BriefingOptInProposal, accessToken: String) async throws -> String {
        let r: TokenResponse = try await send(
            "POST", "v1/confirmations", ConfirmBody(proposalId: proposal.id), accessToken)
        return r.confirmationToken
    }

    public func setOptIn(enabled: Bool, confirmationToken: String, accessToken: String) async throws -> BriefingStatus {
        let r: StatusResponse = try await send(
            "POST", "v1/briefing/opt-in", OptInBody(enabled: enabled, confirmationToken: confirmationToken), accessToken)
        return BriefingStatus(optedIn: r.optedIn)
    }

    // MARK: Decoding

    static func week(_ r: WeekResponse) throws -> BriefingWeek {
        let invalid = BriefingError.failed(code: nil, correlationId: nil)
        guard let start = CalendarDay(iso: r.weekStart), let end = CalendarDay(iso: r.weekEnd) else { throw invalid }
        let missing = Set(r.missingDays.compactMap(CalendarDay.init(iso:)))
        var days: [BriefingDay] = []
        for raw in r.days {
            guard let day = CalendarDay(iso: raw.date) else { throw invalid }
            let events = try raw.events.map { e -> BriefingEvent in
                guard let from = URLSessionAnnouncementService.parseDate(e.start),
                      let to = URLSessionAnnouncementService.parseDate(e.end)
                else { throw invalid }
                return BriefingEvent(
                    id: e.id, title: e.title, start: from, end: to, allDay: e.allDay, location: e.location,
                    online: e.online, attendeeCount: e.attendeeCount, conflictsWith: e.conflictsWith)
            }
            let free = try raw.freeBlocks.map { b -> BriefingFreeBlock in
                guard let from = URLSessionAnnouncementService.parseDate(b.start),
                      let to = URLSessionAnnouncementService.parseDate(b.end)
                else { throw invalid }
                return BriefingFreeBlock(start: from, end: to, minutes: b.minutes)
            }
            days.append(BriefingDay(day: day, events: events, freeBlocks: free, missing: missing.contains(day)))
        }
        return BriefingWeek(
            start: start, end: end, days: days, eventCount: r.eventCount, conflictCount: r.conflictCount)
    }

    static func map(status: Int, code: String?, correlationId: String?) -> BriefingError {
        switch (status, code) {
        case (401, _): return .unauthenticated
        case (403, "NOT_OPTED_IN"): return .notOptedIn
        case (403, "NOT_PROVISIONED"): return .notProvisioned
        case (403, "CONSENT_REQUIRED"): return .consentRequired
        case (403, "NO_LICENCE"), (403, _): return .noLicence
        case (503, "WORKIQ_UNAVAILABLE"), (502, _), (503, _), (504, _): return .workIQUnavailable
        case (_, "CONFIRMATION_REQUIRED"), (_, "INVALID_CONFIRMATION"): return .invalidConfirmation
        default: return .failed(code: code, correlationId: correlationId)
        }
    }

    // MARK: Transport

    private func send<Body: Encodable, Response: Decodable>(
        _ method: String, _ path: String, _ body: Body?, _ accessToken: String, timeout: TimeInterval = 30
    ) async throws -> Response {
        var root = baseURL.absoluteString
        while root.hasSuffix("/") { root.removeLast() }
        guard let url = URL(string: "\(root)/\(path)") else {
            throw BriefingError.failed(code: nil, correlationId: nil)
        }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = method
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        TaskRun.tag(&request)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch let error as URLError where error.code == .timedOut {
            throw BriefingError.timedOut  // slow, not offline: Work IQ answers can take a minute
        } catch let error as URLError where Self.offlineCodes.contains(error.code) {
            throw BriefingError.offline
        } catch {
            throw BriefingError.failed(code: nil, correlationId: nil)
        }
        guard let http = response as? HTTPURLResponse else {
            throw BriefingError.failed(code: nil, correlationId: nil)
        }
        if (200..<300).contains(http.statusCode) {
            guard let decoded = try? JSONDecoder().decode(Response.self, from: data) else {
                throw BriefingError.failed(code: nil, correlationId: nil)
            }
            return decoded
        }
        let error = try? JSONDecoder().decode(ErrorBody.self, from: data)
        throw Self.map(
            status: http.statusCode, code: error?.code, correlationId: http.value(forHTTPHeaderField: "X-Correlation-Id"))
    }

    private static let offlineCodes: Set<URLError.Code> = [
        .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost, .dataNotAllowed,
    ]
}
