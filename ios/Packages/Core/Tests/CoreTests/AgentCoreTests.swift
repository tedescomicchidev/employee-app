import Foundation
import Testing
@testable import Core

/// Plays one canned HTTP response per request path; records requests.
private final class Canned: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requests: [URLRequest] = []
    nonisolated(unsafe) static var status = 200
    nonisolated(unsafe) static var headers: [String: String] = [:]
    nonisolated(unsafe) static var body = Data()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var copy = request
        if let stream = request.httpBodyStream {
            stream.open()
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let n = stream.read(&buffer, maxLength: buffer.count)
                if n <= 0 { break }
                data.append(buffer, count: n)
            }
            stream.close()
            copy.httpBody = data
        }
        Self.requests.append(copy)
        let response = HTTPURLResponse(
            url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: Self.headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private func service(status: Int = 200, body: String = "", headers: [String: String] = [:]) -> URLSessionAgentService {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [Canned.self]
    Canned.requests = []
    Canned.status = status
    Canned.headers = headers
    Canned.body = Data(body.utf8)
    return URLSessionAgentService(baseURL: URL(string: "https://api.test")!, session: URLSession(configuration: config))
}

private func collect(_ stream: AsyncThrowingStream<AgentEvent, Error>) async throws -> [AgentEvent] {
    var events: [AgentEvent] = []
    for try await event in stream { events.append(event) }
    return events
}

/// The request's JSON body as a dictionary (a helper, because `#require` cannot nest).
private func jsonBody(_ request: URLRequest) throws -> [String: Any] {
    let data = try #require(request.httpBody)
    return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
}

private let hello = [AgentMessage(role: .user, content: "what's new?")]

@Suite("Agent SSE and transport", .serialized, .timeLimit(.minutes(1)))
struct AgentCoreTests {
    @Test("FR-ANN-003 AGENT: events parse with or without blank separator lines")
    func parser() {
        for withBlank in [true, false] {
            var parser = SSEParser()
            var out: [SSEEvent] = []
            for line in ["event: status", #"data: {"phase":"thinking"}"#, "", "event: delta", #"data: {"text":"Hi"}"#] {
                if withBlank || !line.isEmpty, let event = parser.feed(line: line) { out.append(event) }
            }
            #expect(out == [SSEEvent(name: "status", data: #"{"phase":"thinking"}"#), SSEEvent(name: "delta", data: #"{"text":"Hi"}"#)])
        }
        var parser = SSEParser()
        #expect(parser.feed(line: ": keep-alive") == nil)
        #expect(parser.feed(line: "id: 4") == nil)
    }

    @Test("FR-ANN-003 AGENT: every device event decodes; unknown events and phases are ignored")
    func decoding() throws {
        func decode(_ name: String, _ data: String) throws -> URLSessionAgentService.Decoded {
            try URLSessionAgentService.decode(SSEEvent(name: name, data: data))
        }
        #expect(try decode("status", #"{"phase":"warming"}"#) == .event(.status(.warming)))
        #expect(try decode("status", #"{"phase":"tool","name":"get_balance"}"#) == .event(.status(.tool("get_balance"))))
        #expect(try decode("status", #"{"phase":"later"}"#) == .ignored)
        #expect(try decode("tool", #"{"name":"get_balance","ok":false}"#) == .event(.toolFinished(AgentToolCall(name: "get_balance", ok: false))))
        #expect(try decode("delta", #"{"text":"Zürich"}"#) == .event(.delta("Zürich")))
        #expect(try decode("future", "{}") == .ignored)
        #expect(throws: AgentError.unavailable) { try decode("error", #"{"code":"AGENT_UNAVAILABLE"}"#) }
        #expect(throws: AgentError.self) { try decode("final", "not json") }
        let final = try decode("final", """
        {"reply":{"kind":"options","text":"Pick","proposal_id":null,"reason":null,
         "options":[{"proposal_id":"p1","start":"2026-12-24","end":"2027-01-04"},{"proposal_id":"bad","start":"x","end":"y"}],
         "sources":[{"announcement_id":"a1","title":"T"}]},
         "tool_calls":[{"name":"propose_vacation_request","ok":true}]}
        """)
        guard case let .event(.final(result)) = final else { Issue.record("not final"); return }
        #expect(result.reply.kind == .options && result.reply.options.count == 1)  // an unreadable option is dropped
        #expect(result.reply.options[0].start == CalendarDay(year: 2026, month: 12, day: 24))
        #expect(result.reply.sources == [AgentSource(announcementId: "a1", title: "T")])
        #expect(result.toolCalls == [AgentToolCall(name: "propose_vacation_request", ok: true)])
        // A kind this app does not know is a plain message, never a write result.
        guard case let .event(.final(unknown)) = try decode("final", #"{"reply":{"kind":"teleport","text":"x"}}"#) else { return }
        #expect(unknown.reply.kind == .message && !unknown.reply.kind.isWriteResult)
    }

    @Test("FR-ANN-001 AGENT: a streamed turn is sent with the history, bearer token and confirmation")
    func streamedTurn() async throws {
        let body = """
        event: status
        data: {"phase":"thinking"}

        event: delta
        data: {"text":"Two"}

        event: final
        data: {"reply":{"kind":"message","text":"Two"},"tool_calls":[]}

        """
        let agent = service(body: body)
        let confirmation = AgentConfirmation(proposalId: "p1", token: "tok-tok-tok-tok-tok-tok")
        let events = try await collect(agent.turn(.comms, messages: hello, confirmation: confirmation, accessToken: "T"))
        #expect(events == [
            .status(.thinking), .delta("Two"),
            .final(AgentTurnResult(reply: AgentReply(kind: .message, text: "Two"), toolCalls: [])),
        ])
        let request = try #require(Canned.requests.first)
        #expect(request.url?.path == "/v1/agent/comms/turns" && request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer T")
        #expect(request.value(forHTTPHeaderField: "Accept") == "text/event-stream")
        let sent = try jsonBody(request)
        #expect((sent["messages"] as? [[String: String]]) == [["role": "user", "content": "what's new?"]])
        #expect((sent["confirmation"] as? [String: String]) == ["proposal_id": "p1", "confirmation_token": "tok-tok-tok-tok-tok-tok"])
    }

    @Test("EXP-005: a turn carries the task run id of the caller")
    func runId() async throws {
        let id = UUID()
        let agent = service(body: "event: final\ndata: {\"reply\":{\"kind\":\"message\",\"text\":\"x\"}}\n")
        _ = try await TaskRun.$current.withValue(id) {
            try await collect(agent.turn(.vacation, messages: hello, confirmation: nil, accessToken: "T"))
        }
        #expect(Canned.requests.first?.value(forHTTPHeaderField: "X-Task-Run-Id") == id.uuidString)
        #expect(Canned.requests.first?.url?.path == "/v1/agent/vacation/turns")
    }

    @Test("A stream that ends without final or error is interrupted; an error event is unavailable")
    func failures() async throws {
        let cut = service(body: "event: status\ndata: {\"phase\":\"thinking\"}\n")
        await #expect(throws: AgentError.interrupted) {
            try await collect(cut.turn(.comms, messages: hello, confirmation: nil, accessToken: "T"))
        }
        let failed = service(body: "event: error\ndata: {\"code\":\"AGENT_UNAVAILABLE\",\"message\":\"x\"}\n")
        await #expect(throws: AgentError.unavailable) {
            try await collect(failed.turn(.comms, messages: hello, confirmation: nil, accessToken: "T"))
        }
    }

    @Test("Status codes before the stream map to errors, Retry-After included")
    func statusMapping() async throws {
        let cases: [(Int, String, [String: String], AgentError)] = [
            (401, #"{"code":"UNAUTHENTICATED"}"#, [:], .unauthenticated),
            (403, #"{"code":"AGENT_UNAVAILABLE"}"#, [:], .forbidden),
            (404, #"{"code":"NOT_FOUND"}"#, [:], .notFound),
            (413, #"{"code":"PAYLOAD_TOO_LARGE"}"#, [:], .tooLong),
            (429, #"{"code":"RATE_LIMITED"}"#, ["Retry-After": "30"], .rateLimited(retryAfter: 30)),
            (503, #"{"code":"AGENT_NOT_CONFIGURED"}"#, [:], .unavailable),
        ]
        for (status, body, headers, expected) in cases {
            let agent = service(status: status, body: body, headers: headers)
            await #expect(throws: expected) {
                try await collect(agent.turn(.comms, messages: hello, confirmation: nil, accessToken: "T"))
            }
        }
    }

    @Test("FR-AUTH-006: confirm posts the proposal type and returns only the token")
    func confirm() async throws {
        let agent = service(body: #"{"confirmation_token":"abc","expires_at":"2026-10-19T06:05:00Z"}"#)
        let token = try await agent.confirm(proposalId: "p9", kind: .vacationCancel, accessToken: "T")
        #expect(token == "abc")
        let request = try #require(Canned.requests.first)
        #expect(request.url?.path == "/v1/confirmations")
        let sent = try jsonBody(request)
        #expect(sent as? [String: String] == ["type": "vacation_cancel", "proposal_id": "p9"])
        let invalid = service(status: 409, body: #"{"code":"INVALID_CONFIRMATION"}"#)
        await #expect(throws: AgentError.invalidConfirmation) {
            try await invalid.confirm(proposalId: "p9", kind: .vacation, accessToken: "T")
        }
    }

    @Test("A-13: the card is read from the stored proposal (announcement, vacation, decision)")
    func cards() async throws {
        let announcement = service(body: """
        {"proposal_id":"p1","type":"announcement","recipient_count":47,"expires_at":"2026-10-19T06:05:00Z",
         "payload":{"title":"Früher Start","body":"8 Uhr","language":"de","audience":{"regions":["TI"],"stores":[],"roles":[]}}}
        """)
        let card = try await announcement.proposal(id: "p1", accessToken: "T")
        #expect(Canned.requests.first?.url?.path == "/v1/proposals/p1")
        guard case let .announcement(draft, count) = card.content else { Issue.record("not an announcement"); return }
        #expect(count == 47 && draft.title == "Früher Start" && draft.audience.values(.region) == ["TI"])

        let vacation = service(body: """
        {"proposal_id":"p2","type":"vacation","expires_at":"2026-10-19T06:05:00Z",
         "payload":{"start":"2026-12-24","end":"2027-01-04"},
         "review":{"counted_days":6,"per_year":{"2026":3,"2027":3},"excluded":[],"remaining":14,
                   "remaining_after":8,"balance_year":2026,"approver":"Sarah Keller"}}
        """)
        guard case let .vacation(start, _, review) = try await vacation.proposal(id: "p2", accessToken: "T").content else {
            Issue.record("not a vacation card"); return
        }
        #expect(start == CalendarDay(year: 2026, month: 12, day: 24) && review.countedDays == 6 && review.remainingAfter == 8)

        let decision = service(body: """
        {"proposal_id":"p3","type":"vacation_decision","expires_at":"2026-10-19T06:05:00Z",
         "payload":{"request_id":"r9","decision":"approve"},
         "request":{"id":"r9","status":"pending","start":"2026-11-09","end":"2026-11-12","counted_days":4,
                    "approver":"Sarah Keller","owner_name":"Marco Rossi","created_at":"2026-10-01T06:00:00Z"}}
        """)
        guard case let .vacationDecision(kind, reason, request) = try await decision.proposal(id: "p3", accessToken: "T").content else {
            Issue.record("not a decision card"); return
        }
        #expect(kind == .approve && reason == nil && request.ownerName == "Marco Rossi" && request.countedDays == 4)

        let broken = service(body: #"{"proposal_id":"p4","type":"vacation","expires_at":"2026-10-19T06:05:00Z","payload":{}}"#)
        await #expect(throws: AgentError.self) { try await broken.proposal(id: "p4", accessToken: "T") }
        let missing = service(status: 404, body: #"{"code":"NOT_FOUND"}"#)
        await #expect(throws: AgentError.notFound) { try await missing.proposal(id: "p4", accessToken: "T") }
    }

    @Test("EXP-001 AGENT: the agent_turn event holds timings and a count, no content field")
    func agentTurnEvent() async throws {
        let sink = MemoryEventSink()
        let flow = await TaskFlow(
            taskId: "T-VAC-BAL", feature: "vac", mode: .agent, context: TaskContext(participantId: UUID()), sink: sink)
        await flow.start()
        await flow.agentTurn(firstTokenMs: 900, totalMs: 4200, toolCalls: 2)
        await flow.complete(outcomeValid: true, messageCount: 3)
        try await Task.sleep(for: .milliseconds(50))
        let events = await sink.events
        #expect(events.map(\.event) == [.taskStarted, .agentTurn, .taskCompleted])
        let json = try JSONEncoder().encode(events[1])
        let object = try #require(JSONSerialization.jsonObject(with: json) as? [String: Any])
        #expect(object["latency_first_token_ms"] as? Int == 900 && object["tool_calls"] as? Int == 2)
        #expect(object["mode"] as? String == "agent")
        #expect(events[2].messageCount == 3)
    }
}

@Suite("Agent stub", .timeLimit(.minutes(1)))
struct StubAgentTests {
    @Test("Scripted turns play in order, then the last repeats; what the app sent is recorded")
    func scripted() async throws {
        let stub = StubAgentService(script: AgentStubScenario.annError.script)
        await #expect(throws: AgentError.unavailable) {
            try await collect(stub.turn(.comms, messages: hello, confirmation: nil, accessToken: "T"))
        }
        let second = try await collect(stub.turn(.comms, messages: hello, confirmation: nil, accessToken: "T"))
        guard case let .final(result) = try #require(second.last) else { Issue.record("no final"); return }
        #expect(result.reply.kind == .message && result.reply.sources.count == 2)
        #expect(stub.turns.count == 2 && stub.turns[0].feature == .comms)
    }

    @Test("Every scenario is well formed: a final or a failure, grounded ids, text equal to its deltas")
    func scenarios() async throws {
        for scenario in AgentStubScenario.allCases {
            let script = scenario.script
            let stub = StubAgentService(script: script)
            for turn in script.turns {
                var streamed = ""
                var final: AgentTurnResult?
                var seen = 0
                do {
                    let stream = stub.turn(scenario.feature, messages: hello, confirmation: nil, accessToken: "T")
                    for try await event in stream {
                        seen += 1
                        if case let .delta(text) = event { streamed += text }
                        if case let .final(result) = event { final = result; break }
                        // A turn that hangs on purpose (stop button, cold start, a write in flight) never
                        // ends by itself: read what it scripted, then let go of it.
                        if turn.ending == .hang, seen == turn.events.count { break }
                    }
                } catch {
                    #expect(turn.ending != .finish, "\(scenario) failed without scripting it")
                    continue
                }
                guard let final else {
                    #expect(turn.ending == .hang, "\(scenario) ended without a final")
                    continue
                }
                #expect(streamed == final.reply.text, "\(scenario)")
                if let id = final.reply.proposalId { #expect(script.cards[id] != nil, "\(scenario) \(id)") }
                for option in final.reply.options { #expect(script.cards[option.proposalId] != nil, "\(scenario)") }
                #expect(final.reply.kind != .refusal || final.reply.reason != nil, "\(scenario)")
            }
        }
    }

    @Test("FR-AUTH-006: confirm mints a token only when the script allows it; cards expire in the future")
    func confirmAndCards() async throws {
        let stub = StubAgentService(script: AgentStubScenario.annDraft.script, ttl: 300, now: { Date(timeIntervalSince1970: 1_000) })
        let card = try await stub.proposal(id: "p-ann-1", accessToken: "T")
        #expect(card.expiresAt == Date(timeIntervalSince1970: 1_300))
        #expect(try await stub.confirm(proposalId: "p-ann-1", kind: .announcement, accessToken: "T").hasPrefix("stub-confirmation-token-"))
        #expect(stub.confirmedProposals == ["p-ann-1"])
        await #expect(throws: AgentError.notFound) { try await stub.proposal(id: "unknown", accessToken: "T") }
        let expired = StubAgentService(script: AgentStubScenario.annExpired.script)
        await #expect(throws: AgentError.invalidConfirmation) {
            try await expired.confirm(proposalId: "p-ann-1", kind: .announcement, accessToken: "T")
        }
    }
}
