import Foundation

/// REST adapter for FR-ANN-001. Sends the user's bearer token; never logs bodies or tokens.
public struct URLSessionAnnouncementService: AnnouncementService {
    private let baseURL: URL
    private let session: URLSession

    public init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    private struct DraftBody: Codable {
        let title: String, body: String, language: String, audience: String
        init(_ draft: AnnouncementDraft) {
            title = draft.title; body = draft.body; language = draft.language.rawValue; audience = "all"
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
    private struct ErrorBody: Decodable {
        let code: String?
        let field: String?
    }

    public func propose(_ draft: AnnouncementDraft, accessToken: String) async throws -> AnnouncementProposal {
        let response: ProposalResponse = try await send(
            "v1/proposals", ["payload": DraftBody(draft)], accessToken: accessToken)
        return AnnouncementProposal(
            id: response.proposalId, draft: draft, recipientCount: response.recipientCount)
    }

    public func confirm(_ proposal: AnnouncementProposal, accessToken: String) async throws -> String {
        let response: TokenResponse = try await send(
            "v1/confirmations", ["proposal_id": proposal.id], accessToken: accessToken)
        return response.confirmationToken
    }

    public func publish(
        _ draft: AnnouncementDraft, confirmationToken: String, accessToken: String
    ) async throws -> PublishedAnnouncement {
        struct Body: Encodable { let payload: DraftBody; let confirmationToken: String
            enum CodingKeys: String, CodingKey { case payload, confirmationToken = "confirmation_token" }
        }
        let response: PublishResponse = try await send(
            "v1/announcements", Body(payload: DraftBody(draft), confirmationToken: confirmationToken),
            accessToken: accessToken)
        return PublishedAnnouncement(id: response.id, recipientCount: response.recipientCount)
    }

    private func send<Body: Encodable, Response: Decodable>(
        _ path: String, _ body: Body, accessToken: String
    ) async throws -> Response {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(body)
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
        case (422, "VALIDATION_ERROR"): .validation(error?.field.flatMap(DraftField.init) ?? .payload)
        case (_, "CONFIRMATION_REQUIRED"), (_, "INVALID_CONFIRMATION"): .invalidConfirmation
        default: .failed(code: error?.code, correlationId: correlationId)
        }
    }

    private static let offlineCodes: Set<URLError.Code> = [
        .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost, .timedOut, .dataNotAllowed,
    ]
}
