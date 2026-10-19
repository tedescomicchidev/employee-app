import Foundation

/// REST adapter for FR-ANN-001/002/003. Sends the user's bearer token; never logs bodies or tokens.
public struct URLSessionAnnouncementService: AnnouncementService {
    private let baseURL: URL
    private let session: URLSession

    public init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    /// `"all"` or `{regions, stores, roles}`, exactly what `api/` hashes for the confirmation token.
    private enum AudienceBody: Codable {
        case all
        case rule(regions: [String], stores: [String], roles: [String])

        init(_ selection: AudienceSelection) {
            self = selection.everyone
                ? .all
                : .rule(regions: selection.values(.region), stores: selection.values(.store),
                        roles: selection.values(.role))
        }

        private enum Keys: String, CodingKey { case regions, stores, roles }

        init(from decoder: Decoder) throws {
            if let single = try? decoder.singleValueContainer().decode(String.self), single == "all" {
                self = .all
                return
            }
            let c = try decoder.container(keyedBy: Keys.self)
            self = .rule(
                regions: try c.decodeIfPresent([String].self, forKey: .regions) ?? [],
                stores: try c.decodeIfPresent([String].self, forKey: .stores) ?? [],
                roles: try c.decodeIfPresent([String].self, forKey: .roles) ?? [])
        }

        func encode(to encoder: Encoder) throws {
            switch self {
            case .all:
                var c = encoder.singleValueContainer()
                try c.encode("all")
            case let .rule(regions, stores, roles):
                var c = encoder.container(keyedBy: Keys.self)
                try c.encode(regions, forKey: .regions)
                try c.encode(stores, forKey: .stores)
                try c.encode(roles, forKey: .roles)
            }
        }

        var selection: AudienceSelection {
            switch self {
            case .all: .all
            case let .rule(regions, stores, roles):
                AudienceSelection(everyone: false, regions: Set(regions), stores: Set(stores), roles: Set(roles))
            }
        }
    }

    private struct DraftBody: Codable {
        let title: String, body: String, language: String, audience: AudienceBody
        init(_ draft: AnnouncementDraft) {
            title = draft.title; body = draft.body; language = draft.language.rawValue
            audience = AudienceBody(draft.audience)
        }
    }
    private struct ProposalResponse: Decodable {
        let proposalId: String
        let payload: DraftBody
        let recipientCount: Int
        enum CodingKeys: String, CodingKey {
            case payload
            case proposalId = "proposal_id"
            case recipientCount = "recipient_count"
        }
    }
    private struct TokenResponse: Decodable {
        let confirmationToken: String
        enum CodingKeys: String, CodingKey { case confirmationToken = "confirmation_token" }
    }
    private struct PublishResponse: Decodable {
        let id: String
        let recipientCount: Int
        enum CodingKeys: String, CodingKey { case id, recipientCount = "recipient_count" }
    }
    private struct ItemResponse: Decodable {
        let id: String, title: String, body: String, language: String, author: String
        let publishedAt: String
        let read: Bool?
        let audience: AudienceBody
        enum CodingKeys: String, CodingKey {
            case id, title, body, language, author, read, audience
            case publishedAt = "published_at"
        }
    }
    private struct ListResponse: Decodable { let items: [ItemResponse] }
    private struct OptionsResponse: Decodable { let regions: [String], stores: [String], roles: [String] }
    private struct CountResponse: Decodable {
        let recipientCount: Int
        enum CodingKeys: String, CodingKey { case recipientCount = "recipient_count" }
    }
    private struct Empty: Codable {}
    private struct ErrorBody: Decodable {
        let code: String?
        let field: String?
    }

    public func propose(_ draft: AnnouncementDraft, accessToken: String) async throws -> AnnouncementProposal {
        let response: ProposalResponse = try await send(
            "POST", "v1/proposals", ["payload": DraftBody(draft)], accessToken: accessToken)
        return AnnouncementProposal(
            id: response.proposalId, draft: draft, recipientCount: response.recipientCount)
    }

    public func confirm(_ proposal: AnnouncementProposal, accessToken: String) async throws -> String {
        let response: TokenResponse = try await send(
            "POST", "v1/confirmations", ["proposal_id": proposal.id], accessToken: accessToken)
        return response.confirmationToken
    }

    public func publish(
        _ draft: AnnouncementDraft, confirmationToken: String, accessToken: String
    ) async throws -> PublishedAnnouncement {
        struct Body: Encodable { let payload: DraftBody; let confirmationToken: String
            enum CodingKeys: String, CodingKey { case payload, confirmationToken = "confirmation_token" }
        }
        let response: PublishResponse = try await send(
            "POST", "v1/announcements",
            Body(payload: DraftBody(draft), confirmationToken: confirmationToken), accessToken: accessToken)
        return PublishedAnnouncement(id: response.id, recipientCount: response.recipientCount)
    }

    public func list(accessToken: String) async throws -> [AnnouncementItem] {
        let response: ListResponse = try await send(
            "GET", "v1/announcements", Optional<Empty>.none, accessToken: accessToken)
        return try response.items.map { raw in
            guard let language = ContentLanguage(rawValue: raw.language),
                  let date = Self.parseDate(raw.publishedAt)
            else { throw AnnouncementError.failed(code: nil, correlationId: nil) }
            return AnnouncementItem(
                id: raw.id, title: raw.title, body: raw.body, language: language, author: raw.author,
                publishedAt: date, read: raw.read ?? false, audience: raw.audience.selection)
        }
    }

    public func markRead(id: String, accessToken: String) async throws {
        let _: Empty = try await send(
            "POST", "v1/announcements/\(id)/read", Optional<Empty>.none, accessToken: accessToken)
    }

    public func audienceOptions(accessToken: String) async throws -> AudienceOptions {
        let response: OptionsResponse = try await send(
            "GET", "v1/audience/options", Optional<Empty>.none, accessToken: accessToken)
        return AudienceOptions(regions: response.regions, stores: response.stores, roles: response.roles)
    }

    public func recipientCount(for audience: AudienceSelection, accessToken: String) async throws -> Int {
        let response: CountResponse = try await send(
            "POST", "v1/audience/resolve", ["audience": AudienceBody(audience)], accessToken: accessToken)
        return response.recipientCount
    }

    static func parseDate(_ text: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        return withFraction.date(from: text) ?? plain.date(from: text)
    }

    private func send<Body: Encodable, Response: Decodable>(
        _ method: String, _ path: String, _ body: Body?, accessToken: String
    ) async throws -> Response {
        var request = URLRequest(url: baseURL.appending(path: path))
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
        } catch let error as URLError where Self.offlineCodes.contains(error.code) {
            throw AnnouncementError.offline
        } catch {
            throw AnnouncementError.failed(code: nil, correlationId: nil)
        }
        guard let http = response as? HTTPURLResponse else {
            throw AnnouncementError.failed(code: nil, correlationId: nil)
        }
        if (200..<300).contains(http.statusCode) {
            guard let decoded = try? JSONDecoder().decode(Response.self, from: data) else {
                throw AnnouncementError.failed(code: nil, correlationId: nil)
            }
            return decoded
        }
        let error = try? JSONDecoder().decode(ErrorBody.self, from: data)
        throw Self.map(status: http.statusCode, error: error,
                       correlationId: http.value(forHTTPHeaderField: "X-Correlation-Id"))
    }

    private static func map(status: Int, error: ErrorBody?, correlationId: String?) -> AnnouncementError {
        switch (status, error?.code) {
        case (401, _): .unauthenticated
        case (403, "FORBIDDEN"): .forbidden
        case (404, _): .notFound
        case (422, "EMPTY_AUDIENCE"): .emptyAudience
        case (422, "VALIDATION_ERROR"): .validation(error?.field.flatMap(DraftField.init) ?? .payload)
        case (_, "CONFIRMATION_REQUIRED"), (_, "INVALID_CONFIRMATION"): .invalidConfirmation
        default: .failed(code: error?.code, correlationId: correlationId)
        }
    }

    private static let offlineCodes: Set<URLError.Code> = [
        .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost, .timedOut, .dataNotAllowed,
    ]
}
