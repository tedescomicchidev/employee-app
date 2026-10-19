import Foundation

/// REST adapter for FR-VAC-001/002/006. Sends the user's bearer token; never logs bodies or tokens.
public struct URLSessionVacationService: VacationService {
    private let baseURL: URL
    private let session: URLSession

    public init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    // MARK: Wire types

    private struct BalanceResponse: Decodable {
        let year: Int, entitlement: Int, approved: Int, pending: Int, remaining: Int
        let carriedOver: Int
        enum CodingKeys: String, CodingKey {
            case year, entitlement, approved, pending, remaining
            case carriedOver = "carried_over"
        }
    }
    private struct ExcludedResponse: Decodable {
        let date: String, kind: String
        let names: [String: String]?
    }
    private struct ReviewResponse: Decodable {
        let countedDays: Int
        let perYear: [String: Int]
        let excluded: [ExcludedResponse]
        let remaining: Int
        let remainingAfter: Int?
        let balanceYear: Int
        let approver: String?
        enum CodingKeys: String, CodingKey {
            case excluded, remaining, approver
            case countedDays = "counted_days", perYear = "per_year"
            case remainingAfter = "remaining_after", balanceYear = "balance_year"
        }
    }
    private struct ProposalResponse: Decodable {
        let proposalId: String
        let review: ReviewResponse
        enum CodingKeys: String, CodingKey { case review, proposalId = "proposal_id" }
    }
    private struct TokenResponse: Decodable {
        let confirmationToken: String
        enum CodingKeys: String, CodingKey { case confirmationToken = "confirmation_token" }
    }
    private struct RequestResponse: Decodable {
        let id: String, status: String, start: String, end: String, approver: String
        let countedDays: Int
        enum CodingKeys: String, CodingKey {
            case id, status, start, end, approver
            case countedDays = "counted_days"
        }
    }
    private struct RequestsResponse: Decodable { let items: [RequestResponse] }
    private struct HolidayResponse: Decodable { let date: String, name: String }
    private struct HolidaysResponse: Decodable {
        let year: Int
        let canton: String?
        let status: String?
        let holidays: [HolidayResponse]
    }
    private struct ConflictResponse: Decodable { let start: String, end: String }
    private struct ViolationResponse: Decodable {
        let code: String
        let remaining: Int?
        let requested: Int?
        let start: String?
        let end: String?
        let conflicts: [ConflictResponse]?
    }
    private struct ErrorBody: Decodable {
        let code: String?
        let violations: [ViolationResponse]?
        let review: ReviewResponse?
    }
    private struct DatesBody: Encodable {
        let start: String, end: String
    }
    private struct ProposalBody: Encodable {
        let type = "vacation"
        let payload: DatesBody
    }
    private struct ConfirmBody: Encodable {
        let type = "vacation"
        let proposalId: String
        enum CodingKeys: String, CodingKey { case type, proposalId = "proposal_id" }
    }
    private struct SubmitBody: Encodable {
        let start: String, end: String, confirmationToken: String
        enum CodingKeys: String, CodingKey { case start, end, confirmationToken = "confirmation_token" }
    }
    private struct Empty: Codable {}

    // MARK: VacationService

    public func balance(accessToken: String) async throws -> VacationBalance {
        let r: BalanceResponse = try await send("GET", "v1/vacation/balance", Optional<Empty>.none, accessToken)
        return VacationBalance(
            year: r.year, entitlement: r.entitlement, carriedOver: r.carriedOver, approved: r.approved,
            pending: r.pending, remaining: r.remaining)
    }

    public func requests(accessToken: String) async throws -> [VacationRequestSummary] {
        let r: RequestsResponse = try await send("GET", "v1/vacation/requests", Optional<Empty>.none, accessToken)
        return try r.items.map(Self.summary)
    }

    public func holidays(year: Int, accessToken: String) async throws -> VacationHolidays {
        let r: HolidaysResponse = try await send(
            "GET", "v1/vacation/holidays?year=\(year)&lang=\(Self.languageCode)", Optional<Empty>.none, accessToken)
        let items = try r.holidays.map { raw -> VacationHoliday in
            guard let day = CalendarDay(iso: raw.date) else { throw VacationError.failed(code: nil, correlationId: nil) }
            return VacationHoliday(day: day, name: raw.name)
        }
        return VacationHolidays(
            year: r.year, canton: r.canton, items: items, needsConfirmation: r.status == "HUMAN_CONFIRMATION_REQUIRED")
    }

    public func propose(start: CalendarDay, end: CalendarDay, accessToken: String) async throws -> VacationProposal {
        let r: ProposalResponse = try await send(
            "POST", "v1/proposals",
            ProposalBody(payload: DatesBody(start: start.iso, end: end.iso)), accessToken)
        return VacationProposal(id: r.proposalId, start: start, end: end, review: Self.review(r.review))
    }

    public func confirm(_ proposal: VacationProposal, accessToken: String) async throws -> String {
        let r: TokenResponse = try await send(
            "POST", "v1/confirmations", ConfirmBody(proposalId: proposal.id), accessToken)
        return r.confirmationToken
    }

    public func submit(
        start: CalendarDay, end: CalendarDay, confirmationToken: String, accessToken: String
    ) async throws -> VacationRequestSummary {
        let r: RequestResponse = try await send(
            "POST", "v1/vacation/requests",
            SubmitBody(start: start.iso, end: end.iso, confirmationToken: confirmationToken), accessToken)
        return try Self.summary(r)
    }

    // MARK: Mapping

    private static var languageCode: String {
        let code = Locale.current.language.languageCode?.identifier ?? "de"
        return ["de", "fr", "it", "en"].contains(code) ? code : "de"
    }

    /// Holiday names arrive in every language where the seed has one; show the UI language.
    private static func localized(_ names: [String: String]) -> String? {
        names[languageCode] ?? names["de"] ?? names["en"] ?? names.values.first
    }

    private static func summary(_ r: RequestResponse) throws -> VacationRequestSummary {
        guard let status = VacationStatus(rawValue: r.status), let start = CalendarDay(iso: r.start),
              let end = CalendarDay(iso: r.end)
        else { throw VacationError.failed(code: nil, correlationId: nil) }
        return VacationRequestSummary(
            id: r.id, status: status, start: start, end: end, countedDays: r.countedDays, approver: r.approver)
    }

    private static func review(_ r: ReviewResponse) -> VacationReview {
        VacationReview(
            countedDays: r.countedDays,
            perYear: Dictionary(uniqueKeysWithValues: r.perYear.compactMap { key, value in Int(key).map { ($0, value) } }),
            excluded: r.excluded.compactMap { raw in
                guard let day = CalendarDay(iso: raw.date), let kind = ExcludedDay.Kind(rawValue: raw.kind) else { return nil }
                return ExcludedDay(day: day, kind: kind, name: raw.names.flatMap(localized))
            },
            remaining: r.remaining, remainingAfter: r.remainingAfter, balanceYear: r.balanceYear, approver: r.approver)
    }

    private static func range(_ start: String?, _ end: String?) -> DayRange? {
        guard let start = start.flatMap(CalendarDay.init(iso:)), let end = end.flatMap(CalendarDay.init(iso:)) else { return nil }
        return DayRange(start: start, end: end)
    }

    private static func violation(_ v: ViolationResponse) -> VacationViolation {
        VacationViolation(
            code: v.code, remaining: v.remaining, requested: v.requested, range: range(v.start, v.end),
            conflicts: (v.conflicts ?? []).compactMap { range($0.start, $0.end) })
    }

    private static func map(status: Int, error: ErrorBody?, correlationId: String?) -> VacationError {
        switch (status, error?.code) {
        case (401, _): return .unauthenticated
        case (403, "NOT_PROVISIONED"): return .notProvisioned
        case (403, _): return .forbidden
        case (422, "CANTON_MISSING"): return .cantonMissing
        case (422, "NO_APPROVER"): return .noApprover
        case (422, "VALIDATION_ERROR"): return .validation
        case (422, _) where error?.violations != nil:
            return .rules((error?.violations ?? []).map(violation), review: error?.review.map(review))
        case (_, "CONFIRMATION_REQUIRED"), (_, "INVALID_CONFIRMATION"): return .invalidConfirmation
        default: return .failed(code: error?.code, correlationId: correlationId)
        }
    }

    // MARK: Transport

    private func send<Body: Encodable, Response: Decodable>(
        _ method: String, _ path: String, _ body: Body?, _ accessToken: String
    ) async throws -> Response {
        var root = baseURL.absoluteString
        while root.hasSuffix("/") { root.removeLast() }
        guard let url = URL(string: "\(root)/\(path)") else {
            throw VacationError.failed(code: nil, correlationId: nil)
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where Self.offlineCodes.contains(error.code) {
            throw VacationError.offline
        } catch {
            throw VacationError.failed(code: nil, correlationId: nil)
        }
        guard let http = response as? HTTPURLResponse else { throw VacationError.failed(code: nil, correlationId: nil) }
        if (200..<300).contains(http.statusCode) {
            guard let decoded = try? JSONDecoder().decode(Response.self, from: data) else {
                throw VacationError.failed(code: nil, correlationId: nil)
            }
            return decoded
        }
        let error = try? JSONDecoder().decode(ErrorBody.self, from: data)
        throw Self.map(status: http.statusCode, error: error, correlationId: http.value(forHTTPHeaderField: "X-Correlation-Id"))
    }

    private static let offlineCodes: Set<URLError.Code> = [
        .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost, .timedOut, .dataNotAllowed,
    ]
}
