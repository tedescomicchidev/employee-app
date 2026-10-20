import Foundation

/// REST + SSE adapter for the agent gateway (docs/architecture/agent-turn-contract.md).
/// Sends the user's bearer token; never logs bodies, replies or tokens.
public struct URLSessionAgentService: AgentService {
    private let baseURL: URL
    private let session: URLSession

    public init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    // MARK: Wire types

    private struct TurnBody: Encodable {
        struct Confirmation: Encodable {
            let proposalId: String
            let confirmationToken: String
            enum CodingKeys: String, CodingKey {
                case proposalId = "proposal_id", confirmationToken = "confirmation_token"
            }
        }
        let messages: [AgentMessage]
        let confirmation: Confirmation?
    }

    private struct StatusData: Decodable { let phase: String, name: String? }
    private struct ToolData: Decodable { let name: String, ok: Bool }
    private struct DeltaData: Decodable { let text: String }
    private struct FinalData: Decodable {
        struct Option: Decodable {
            let proposalId: String, start: String, end: String
            enum CodingKeys: String, CodingKey { case proposalId = "proposal_id", start, end }
        }
        struct Source: Decodable {
            let announcementId: String, title: String?
            enum CodingKeys: String, CodingKey { case announcementId = "announcement_id", title }
        }
        struct Reply: Decodable {
            let kind: String
            let text: String?
            let proposalId: String?
            let options: [Option]?
            let reason: String?
            let sources: [Source]?
            let omittedCount: Int?
            enum CodingKeys: String, CodingKey {
                case kind, text, options, reason, sources, proposalId = "proposal_id"
                case omittedCount = "omitted_count"
            }
        }
        let reply: Reply
        let toolCalls: [ToolData]?
        enum CodingKeys: String, CodingKey { case reply, toolCalls = "tool_calls" }

        var result: AgentTurnResult {
            AgentTurnResult(
                reply: AgentReply(
                    kind: AgentReplyKind(rawValue: reply.kind) ?? .message, text: reply.text ?? "",
                    proposalId: reply.proposalId,
                    options: (reply.options ?? []).compactMap { raw in
                        guard let start = CalendarDay(iso: raw.start), let end = CalendarDay(iso: raw.end) else { return nil }
                        return AgentOption(proposalId: raw.proposalId, start: start, end: end)
                    },
                    reason: reply.reason,
                    sources: (reply.sources ?? []).map { AgentSource(announcementId: $0.announcementId, title: $0.title ?? "") },
                    omittedCount: reply.omittedCount),
                toolCalls: (toolCalls ?? []).map { AgentToolCall(name: $0.name, ok: $0.ok) })
        }
    }

    private struct CardPayload: Decodable {
        let title: String?, body: String?, language: String?
        let audience: URLSessionAnnouncementService.AudienceBody?
        let start: String?, end: String?
        let decision: String?, reason: String?
        let enabled: Bool?
    }
    private struct CardResponse: Decodable {
        let proposalId: String
        let type: String
        let payload: CardPayload
        let recipientCount: Int?
        let review: URLSessionVacationService.ReviewResponse?
        let request: URLSessionVacationService.RequestResponse?
        let expiresAt: String
        enum CodingKeys: String, CodingKey {
            case type, payload, review, request
            case proposalId = "proposal_id", recipientCount = "recipient_count", expiresAt = "expires_at"
        }
    }
    private struct TokenResponse: Decodable {
        let confirmationToken: String
        enum CodingKeys: String, CodingKey { case confirmationToken = "confirmation_token" }
    }
    private struct ErrorBody: Decodable { let code: String? }

    // MARK: AgentService

    public func turn(
        _ feature: AgentFeature, messages: [AgentMessage], confirmation: AgentConfirmation?,
        accessToken: String
    ) -> AsyncThrowingStream<AgentEvent, Error> {
        // Built here, not in the stream's task, so the caller's task-local run id tags the request (EXP-005).
        let request: URLRequest
        do {
            let body = TurnBody(
                messages: messages,
                confirmation: confirmation.map { .init(proposalId: $0.proposalId, confirmationToken: $0.token) })
            request = try makeRequest(
                "POST", "v1/agent/\(feature.rawValue)/turns", body: JSONEncoder().encode(body),
                accept: "text/event-stream", accessToken: accessToken, timeout: 90)
        } catch {
            return AsyncThrowingStream { $0.finish(throwing: AgentError.failed(code: nil, correlationId: nil)) }
        }
        let session = session
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else { throw AgentError.interrupted }
                    guard http.statusCode == 200 else {
                        var data = Data()
                        for try await byte in bytes { data.append(byte); if data.count > 4096 { break } }
                        throw Self.map(
                            status: http.statusCode, body: data,
                            retryAfter: http.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init),
                            correlationId: http.value(forHTTPHeaderField: "X-Correlation-Id"))
                    }
                    var parser = SSEParser()
                    for try await line in bytes.lines {
                        guard let event = parser.feed(line: line) else { continue }
                        switch try Self.decode(event) {
                        case let .event(event):
                            continuation.yield(event)
                            if case .final = event { continuation.finish(); return }
                        case .ignored: continue
                        }
                    }
                    throw AgentError.interrupted
                } catch is CancellationError {
                    continuation.finish()
                } catch let error as AgentError {
                    continuation.finish(throwing: error)
                } catch let error as URLError where error.code == .cancelled {
                    continuation.finish()
                } catch let error as URLError where error.code == .timedOut {
                    continuation.finish(throwing: AgentError.unavailable)  // slow, not offline
                } catch let error as URLError where Self.offlineCodes.contains(error.code) {
                    continuation.finish(throwing: AgentError.offline)
                } catch {
                    continuation.finish(throwing: AgentError.failed(code: nil, correlationId: nil))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func proposal(id: String, accessToken: String) async throws -> AgentProposalCard {
        let card: CardResponse = try await send("GET", "v1/proposals/\(id)", body: nil, accessToken: accessToken)
        return try Self.card(card)
    }

    public func confirm(proposalId: String, kind: AgentProposalKind, accessToken: String) async throws -> String {
        let body = try JSONEncoder().encode(["type": kind.rawValue, "proposal_id": proposalId])
        let token: TokenResponse = try await send("POST", "v1/confirmations", body: body, accessToken: accessToken)
        return token.confirmationToken
    }

    // MARK: Decoding

    enum Decoded: Equatable {
        case event(AgentEvent)
        case ignored
    }

    /// Package-visible for the parser tests.
    static func decode(_ event: SSEEvent) throws -> Decoded {
        let data = Data(event.data.utf8)
        let decoder = JSONDecoder()
        do {
            switch event.name {
            case "status":
                let status = try decoder.decode(StatusData.self, from: data)
                switch status.phase {
                case "warming": return .event(.status(.warming))
                case "thinking": return .event(.status(.thinking))
                case "tool": return .event(.status(.tool(status.name ?? "")))
                default: return .ignored
                }
            case "tool":
                let tool = try decoder.decode(ToolData.self, from: data)
                return .event(.toolFinished(AgentToolCall(name: tool.name, ok: tool.ok)))
            case "delta":
                return .event(.delta(try decoder.decode(DeltaData.self, from: data).text))
            case "final":
                return .event(.final(try decoder.decode(FinalData.self, from: data).result))
            case "error":
                throw AgentError.unavailable
            default:
                return .ignored  // a newer api may add events; this app ignores what it does not know
            }
        } catch let error as AgentError {
            throw error
        } catch {
            throw AgentError.failed(code: nil, correlationId: nil)
        }
    }

    private static func card(_ r: CardResponse) throws -> AgentProposalCard {
        let invalid = AgentError.failed(code: nil, correlationId: nil)
        guard let kind = AgentProposalKind(rawValue: r.type),
              let expires = URLSessionAnnouncementService.parseDate(r.expiresAt)
        else { throw invalid }
        let content: AgentProposalCard.Content
        switch kind {
        case .announcement:
            guard let title = r.payload.title, let body = r.payload.body, let audience = r.payload.audience,
                  let language = r.payload.language.flatMap(ContentLanguage.init(rawValue:)),
                  let count = r.recipientCount
            else { throw invalid }
            content = .announcement(
                AnnouncementDraft(title: title, body: body, language: language, audience: audience.selection),
                recipientCount: count)
        case .vacation:
            guard let start = r.payload.start.flatMap(CalendarDay.init(iso:)),
                  let end = r.payload.end.flatMap(CalendarDay.init(iso:)), let review = r.review
            else { throw invalid }
            content = .vacation(start: start, end: end, review: URLSessionVacationService.review(review))
        case .vacationCancel:
            guard let request = r.request else { throw invalid }
            content = .vacationCancel(try URLSessionVacationService.summary(request))
        case .vacationDecision:
            guard let request = r.request, let raw = r.payload.decision,
                  let decision = VacationDecision(rawValue: raw)
            else { throw invalid }
            content = .vacationDecision(
                decision: decision, reason: r.payload.reason, request: try URLSessionVacationService.summary(request))
        case .briefing:
            guard let enabled = r.payload.enabled else { throw invalid }
            content = .briefing(enabled: enabled)
        }
        return AgentProposalCard(id: r.proposalId, kind: kind, content: content, expiresAt: expires)
    }

    // MARK: Transport

    private func makeRequest(
        _ method: String, _ path: String, body: Data?, accept: String, accessToken: String, timeout: TimeInterval = 60
    ) throws -> URLRequest {
        var root = baseURL.absoluteString
        while root.hasSuffix("/") { root.removeLast() }
        guard let url = URL(string: "\(root)/\(path)") else { throw AgentError.failed(code: nil, correlationId: nil) }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = method
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        TaskRun.tag(&request)
        request.setValue(accept, forHTTPHeaderField: "Accept")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }
        return request
    }

    private func send<Response: Decodable>(
        _ method: String, _ path: String, body: Data?, accessToken: String
    ) async throws -> Response {
        let request = try makeRequest(method, path, body: body, accept: "application/json", accessToken: accessToken)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .timedOut {
            throw AgentError.unavailable  // slow, not offline
        } catch let error as URLError where Self.offlineCodes.contains(error.code) {
            throw AgentError.offline
        } catch {
            throw AgentError.failed(code: nil, correlationId: nil)
        }
        guard let http = response as? HTTPURLResponse else { throw AgentError.failed(code: nil, correlationId: nil) }
        if (200..<300).contains(http.statusCode) {
            guard let decoded = try? JSONDecoder().decode(Response.self, from: data) else {
                throw AgentError.failed(code: nil, correlationId: nil)
            }
            return decoded
        }
        throw Self.map(
            status: http.statusCode, body: data, retryAfter: nil,
            correlationId: http.value(forHTTPHeaderField: "X-Correlation-Id"))
    }

    static func map(status: Int, body: Data, retryAfter: Int?, correlationId: String?) -> AgentError {
        let code = (try? JSONDecoder().decode(ErrorBody.self, from: body))?.code
        switch (status, code) {
        case (401, _): return .unauthenticated
        case (403, _): return .forbidden
        case (404, _): return .notFound
        case (413, _): return .tooLong
        case (429, _): return .rateLimited(retryAfter: retryAfter)
        case (_, "CONFIRMATION_REQUIRED"), (_, "INVALID_CONFIRMATION"): return .invalidConfirmation
        case (502, _), (503, _): return .unavailable
        default: return .failed(code: code, correlationId: correlationId)
        }
    }

    private static let offlineCodes: Set<URLError.Code> = [
        .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost, .dataNotAllowed,
    ]
}
