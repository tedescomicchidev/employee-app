import Core
import Foundation
import Testing
@testable import Features

#if DEBUG
/// A clock the test moves by hand.
private final class TestClock: @unchecked Sendable {  // guarded by `lock`
    private let lock = NSLock()
    private var current = Date(timeIntervalSince1970: 1_800_000_000)
    var now: Date { lock.withLock { current } }
    func advance(_ seconds: TimeInterval) { lock.withLock { current = current.addingTimeInterval(seconds) } }
}

@MainActor
private final class Rig {
    let model: AgentChatModel
    let stub: StubAgentService
    let sink = MemoryEventSink()
    let clock = TestClock()
    var reauthCalls = 0
    var tasks: [AgentTask] = []

    init(_ script: StubAgentScript, feature: AgentFeature = .comms, online: Bool = true, ttl: TimeInterval = 300) {
        let clock = clock
        let stub = StubAgentService(script: script, ttl: ttl, now: { clock.now })
        self.stub = stub
        let sink = sink
        let holder = Holder()
        model = AgentChatModel(
            feature: feature, service: stub, accessToken: { "bearer" },
            onReauthNeeded: { holder.reauth() },
            makeFlow: { task, runId in
                holder.tasks.append(task)
                return TaskFlow(
                    taskId: task.taskId, feature: task.feature, mode: .agent,
                    context: TaskContext(participantId: UUID()), sink: sink, confirmAction: task.confirmAction,
                    runId: runId, now: { clock.now })
            },
            connectivity: StaticConnectivity(online: online), now: { clock.now })
        self.holder = holder
    }

    private let holder: Holder
    var reauth: Int { holder.reauthCalls }
    var flows: [AgentTask] { holder.tasks }

    @MainActor final class Holder {
        var reauthCalls = 0
        var tasks: [AgentTask] = []
        func reauth() { reauthCalls += 1 }
    }

    /// Waits until the turn (and any card load) is done.
    func settle() async {
        for _ in 0..<500 {
            if !model.isBusy, !model.items.contains(where: { if case let .card(c) = $0.content { c.state == .loading } else { false } }) {
                break
            }
            try? await Task.sleep(for: .milliseconds(2))
        }
        try? await Task.sleep(for: .milliseconds(30))  // events are recorded by detached tasks
    }

    func events() async -> [ExperimentEvent] { await sink.events }

    var cards: [AgentChatModel.Card] {
        model.items.compactMap { if case let .card(card) = $0.content { card } else { nil } }
    }

    var replies: [AgentReply] {
        model.items.compactMap { if case let .agent(reply, _) = $0.content { reply } else { nil } }
    }
}

@MainActor
@Suite("AgentChatModel", .timeLimit(.minutes(1)))
struct AgentChatModelTests {
    @Test("FR-ANN-003 AGENT: an answer replaces the streamed text and carries its sources")
    func answerWithSources() async {
        let rig = Rig(AgentStubScenario.annOK.script)
        rig.model.send("Was gibt es Neues?")
        #expect(rig.model.phase != .idle)
        await rig.settle()
        #expect(rig.model.phase == .idle && rig.model.problem == nil)
        #expect(!rig.model.items.contains { if case .streaming = $0.content { true } else { false } })
        #expect(rig.replies.count == 1 && rig.replies[0].sources.map(\.announcementId) == ["a4", "a2"])
        #expect(rig.model.announcement?.text == rig.replies[0].text)
        // The history the api receives is the device's own: one user message.
        #expect(rig.stub.turns.map(\.messages) == [[AgentMessage(role: .user, content: "Was gibt es Neues?")]])
        #expect(rig.stub.turns[0].confirmation == nil)
    }

    @Test("EXP-001 AGENT: the task is learned from the tools; the flow starts at the first message and completes on the answer")
    func readTaskEvents() async {
        let rig = Rig(AgentStubScenario.annOK.script)
        let first = rig.clock.now
        rig.model.send("Was gibt es Neues?")
        rig.clock.advance(4)
        await rig.settle()
        let events = await rig.events()
        #expect(events.map(\.event) == [.taskStarted, .agentTurn, .taskCompleted])
        #expect(events.allSatisfy { $0.taskId == "T-ANN-READ" && $0.mode == "agent" && $0.feature == "ann" })
        #expect(events[0].ts == first)  // back-dated: the task began with the message, not the reply
        #expect(events[1].toolCalls == 1 && events[1].latencyTotalMs != nil)
        #expect(events[2].messageCount == 1 && events[2].outcomeValid == true)
        #expect(Set(events.map(\.taskRunId)).count == 1)
    }

    @Test("FR-AUTH-006 AGENT: a draft becomes a card from the stored proposal; nothing is confirmed until the tap")
    func cardWaitsForTheTap() async throws {
        let rig = Rig(AgentStubScenario.annDraft.script)
        rig.model.send("Sag allen im Tessin, dass wir Freitag um 8 öffnen")
        await rig.settle()
        let card = try #require(rig.cards.first)
        #expect(card.proposalId == "p-ann-1" && card.state == .proposal)
        guard case let .announcement(draft, count) = try #require(card.card).content else { Issue.record("wrong card"); return }
        #expect(draft.title == "Früher Start am Freitag" && count == 47)
        #expect(rig.stub.confirmedProposals.isEmpty)
        // Typed consent is only a message: no confirmation is sent, no token minted, the card stays open.
        rig.model.send("ja, veröffentlichen")
        await rig.settle()
        #expect(rig.stub.confirmedProposals.isEmpty)
        #expect(rig.stub.turns.allSatisfy { $0.confirmation == nil })
        #expect(rig.cards.first?.state == .proposal)
    }

    @Test("FR-ANN-001 AGENT: the tap mints the token, sends the confirmation turn and shows the agent's result")
    func confirmPublishes() async throws {
        let rig = Rig(AgentStubScenario.annSuccess.script)
        rig.model.send("Veröffentliche die Mitteilung")
        await rig.settle()
        rig.model.confirm(proposalId: "p-ann-1")
        #expect(rig.model.phase == .executing && rig.model.canStop == false)
        await rig.settle()
        #expect(rig.cards.first?.state == .success("Veröffentlicht an 47 Personen."))
        #expect(rig.stub.confirmedProposals == ["p-ann-1"])
        let confirmation = try #require(rig.stub.turns.last?.confirmation)
        #expect(confirmation.proposalId == "p-ann-1" && confirmation.token == "stub-confirmation-token-p-ann-1")
        let events = await rig.events()
        #expect(events.map(\.event) == [
            .taskStarted, .agentTurn, .confirmShown, .confirmAccepted, .agentTurn, .taskCompleted,
        ])
        #expect(events.allSatisfy { $0.taskId == "T-ANN-PUB" })
        #expect(events[2].action == .publish && events[3].action == .publish && events[3].latencyMs != nil)
        #expect(rig.flows == [.announcementsPublish])
    }

    @Test("FR-ANN-001 AGENT: editing by asking replaces the card; only the newest can be confirmed")
    func supersede() async {
        let rig = Rig(AgentStubScenario.annDraftEdit.script)
        rig.model.send("Entwurf bitte")
        await rig.settle()
        rig.model.send("Nimm Graubünden dazu")
        await rig.settle()
        #expect(rig.cards.map(\.proposalId) == ["p-ann-1", "p-ann-2"])
        #expect(rig.cards.map(\.state) == [.superseded, .proposal])
        rig.model.confirm(proposalId: "p-ann-1")  // a stale tap does nothing
        #expect(rig.stub.confirmedProposals.isEmpty && !rig.model.isBusy)
    }

    @Test("FR-AUTH-006 AGENT: an expired confirmation shows the expired card and sends no turn")
    func expired() async {
        let rig = Rig(AgentStubScenario.annExpired.script)
        rig.model.send("Entwurf")
        await rig.settle()
        let before = rig.stub.turns.count
        rig.model.confirm(proposalId: "p-ann-1")
        await rig.settle()
        #expect(rig.cards.first?.state == .expired)
        #expect(rig.stub.turns.count == before && rig.model.phase == .idle)
    }

    @Test("FR-AUTH-006 AGENT: a card past its validity cannot be confirmed locally")
    func locallyExpired() async {
        let rig = Rig(AgentStubScenario.annDraft.script, ttl: 300)
        rig.model.send("Entwurf")
        await rig.settle()
        rig.clock.advance(301)
        rig.model.confirm(proposalId: "p-ann-1")
        #expect(rig.cards.first?.state == .expired && rig.stub.confirmedProposals.isEmpty)
    }

    @Test("EXP-001 AGENT: cancelling the card is a rejection and tells the agent it was declined")
    func cancelCard() async {
        let rig = Rig(AgentStubScenario.annDraft.script)
        rig.model.send("Entwurf")
        await rig.settle()
        rig.model.cancel(proposalId: "p-ann-1")
        #expect(rig.cards.first?.state == .cancelled)
        rig.model.send("Danke")
        await rig.settle()
        let sent = rig.stub.turns.last?.messages.map(\.content) ?? []
        #expect(sent.contains("I cancelled the proposal on the confirm card."))
        #expect((await rig.events()).map(\.event).contains(.confirmRejected))
    }

    @Test("FR-VAC-002 AGENT: a failed confirmation (blackout) leaves the card failed with the agent's reason")
    func blackout() async {
        let rig = Rig(AgentStubScenario.vacBlackout.script, feature: .vacation)
        rig.model.send("Ferien 24. Dezember bis 4. Januar")
        await rig.settle()
        rig.model.confirm(proposalId: "p-vac-1")
        await rig.settle()
        guard case let .failed(text) = rig.cards.first?.state else { Issue.record("not failed"); return }
        #expect(text?.contains("BLACKOUT") == true)
        let events = await rig.events()
        #expect(events.contains { $0.event == .taskError && $0.code == "AGENT_TOOL_FAILURE" })
        #expect(!events.contains { $0.event == .taskCompleted })
    }

    @Test("FR-VAC-002 AGENT: choosing an offered range shows that range's stored proposal as the card")
    func options() async throws {
        let rig = Rig(AgentStubScenario.vacOptions.script, feature: .vacation)
        rig.model.send("Weihnachten frei")
        await rig.settle()
        let reply = try #require(rig.replies.first)
        #expect(reply.kind == .options && reply.options.count == 3)
        rig.model.choose(reply.options[0], label: "21.–31. Dez.")
        await rig.settle()
        #expect(rig.cards.map(\.proposalId) == ["p-vac-a"] && rig.cards.first?.state == .proposal)
        #expect(rig.stub.turns.count == 1)  // no extra turn: the option already has its proposal
        let events = await rig.events()
        #expect(events.contains { $0.event == .confirmShown && $0.taskId == "T-VAC-REQ" && $0.action == .request })
    }

    @Test("FR-VAC-004 AGENT: a manager's decision card is confirmed with the decision type")
    func decision() async {
        let rig = Rig(AgentStubScenario.vacDecisionSuccess.script, feature: .vacation)
        rig.model.send("Ferien von Marco freigeben")
        await rig.settle()
        guard case .vacationDecision = rig.cards.first?.card?.content else { Issue.record("wrong card"); return }
        rig.model.confirm(proposalId: "p-dec-1")
        await rig.settle()
        #expect(rig.cards.first?.state == .success("Genehmigt."))
        let events = await rig.events()
        #expect(events.allSatisfy { $0.taskId == "T-VAC-APR" })
        #expect(events.first { $0.event == .confirmAccepted }?.action == .decide)
    }

    @Test("FR-VAC-001 AGENT: a balance answer completes T-VAC-BAL")
    func balance() async {
        let rig = Rig(AgentStubScenario.vacBalance.script, feature: .vacation)
        rig.model.send("Wie viele Ferientage habe ich?")
        await rig.settle()
        #expect((await rig.events()).map(\.event) == [.taskStarted, .agentTurn, .taskCompleted])
        #expect(rig.flows == [.vacationBalance])
    }

    @Test("FR-VAC-002 AGENT: a refusal is a reply of its own kind with a reason code")
    func refusal() async {
        let rig = Rig(AgentStubScenario.vacRefusal.script, feature: .vacation)
        rig.model.send("Reiche es trotzdem ein")
        await rig.settle()
        #expect(rig.replies.first?.kind == .refusal && rig.replies.first?.reason == "rule_bypass")
        #expect(rig.model.problem == nil && rig.cards.isEmpty)
    }

    @Test("FR-ANN-002 AGENT: a clarification is a question with no card")
    func clarification() async {
        let rig = Rig(AgentStubScenario.vacClarification.script, feature: .vacation)
        rig.model.send("Frei über Weihnachten")
        await rig.settle()
        #expect(rig.replies.first?.kind == .clarification && rig.cards.isEmpty)
        #expect((await rig.events()).isEmpty)  // no tool yet, so no task: nothing to attribute
    }

    @Test("AGENT UX: a failed turn offers retry; retry resends without a duplicate message")
    func retry() async {
        let rig = Rig(AgentStubScenario.annError.script)
        rig.model.send("Was gibt es Neues?")
        await rig.settle()
        #expect(rig.model.problem == .unavailable(code: "AGENT_UNAVAILABLE"))
        #expect(rig.model.items.count == 1)
        rig.model.retry()
        await rig.settle()
        #expect(rig.model.problem == nil && rig.replies.count == 1 && rig.model.items.count == 2)
        #expect(rig.stub.turns.count == 2 && rig.stub.turns[0].messages == rig.stub.turns[1].messages)
    }

    @Test("FR-AUTH-006 AGENT: retrying a failed confirmation turn reuses the same token")
    func retryConfirmation() async throws {
        let failing = StubAgentScript(
            turns: [
                StubTurn([.final(AgentTurnResult(reply: AgentReply(kind: .proposal, text: "Prüfe", proposalId: "p-ann-1"), toolCalls: [AgentToolCall(name: "propose_announcement", ok: true)]))]),
                StubTurn([], ending: .fail(.unavailable)),
                StubTurn([.final(AgentTurnResult(reply: AgentReply(kind: .published, text: "Fertig"), toolCalls: [AgentToolCall(name: "publish_announcement", ok: true)]))]),
            ],
            cards: AgentStubScenario.annDraft.script.cards)
        let rig = Rig(failing)
        rig.model.send("Entwurf")
        await rig.settle()
        rig.model.confirm(proposalId: "p-ann-1")
        await rig.settle()
        #expect(rig.cards.first?.state == .failed(nil) && rig.model.problem == .unavailable(code: "AGENT_UNAVAILABLE"))
        rig.model.retry()
        await rig.settle()
        #expect(rig.cards.first?.state == .success("Fertig"))
        let tokens = rig.stub.turns.compactMap(\.confirmation?.token)
        #expect(tokens.count == 2 && Set(tokens).count == 1)
        #expect(rig.stub.confirmedProposals == ["p-ann-1"])  // the token was minted once
    }

    @Test("NFR-007 AGENT: offline disables sending; coming back online clears the notice")
    func offline() async {
        let rig = Rig(AgentStubScenario.annOffline.script)
        rig.model.send("Hallo")
        await rig.settle()
        #expect(rig.model.problem == .offline && rig.model.isOffline && !rig.model.canType)
        rig.model.draft = "nochmal"
        #expect(!rig.model.canSend)
        rig.model.send()
        #expect(rig.stub.turns.count == 1)
        let monitor = Task { await rig.model.monitorConnectivity() }
        for _ in 0..<200 where rig.model.isOffline { try? await Task.sleep(for: .milliseconds(5)) }
        monitor.cancel()
        #expect(!rig.model.isOffline && rig.model.problem == nil && rig.model.canSend)
    }

    @Test("NFR-007 AGENT: the device starts offline when the network path says so")
    func startsOffline() async {
        let rig = Rig(AgentStubScenario.annOK.script, online: false)
        let monitor = Task { await rig.model.monitorConnectivity() }
        for _ in 0..<200 where !rig.model.isOffline { try? await Task.sleep(for: .milliseconds(5)) }
        monitor.cancel()
        rig.model.send("Hallo")
        #expect(rig.model.isOffline && rig.stub.turns.isEmpty && rig.model.items.isEmpty)
    }

    @Test("AGENT UX: a rate limit blocks sending until the Retry-After passes")
    func rateLimit() async throws {
        let rig = Rig(StubAgentScript(turns: [StubTurn([], ending: .fail(.rateLimited(retryAfter: 1)))]))
        rig.model.send("Hallo")
        await rig.settle()
        guard case let .rateLimited(until) = rig.model.problem else { Issue.record("not limited"); return }
        #expect(until == rig.clock.now.addingTimeInterval(1) && rig.model.isRateLimited)
        rig.model.draft = "nochmal"
        #expect(!rig.model.canSend)
        try await Task.sleep(for: .milliseconds(1_200))
        #expect(rig.model.problem == nil)
    }

    @Test("FR-AUTH-005 AGENT: an expired session asks to sign in again and keeps the message for a retry")
    func signedOut() async {
        let rig = Rig(StubAgentScript(turns: [StubTurn([], ending: .fail(.unauthenticated))]))
        rig.model.send("Hallo")
        await rig.settle()
        #expect(rig.model.problem == .signedOut && rig.reauth == 1)
        #expect(rig.model.items.count == 1)
    }

    @Test("FR-ANN-001 AGENT: stop ends the turn, drops partial text and leaves the chat usable")
    func stop() async {
        let rig = Rig(AgentStubScenario.annLoading.script)
        rig.model.send("Was gibt es Neues?")
        for _ in 0..<200 where rig.model.phase == .thinking { try? await Task.sleep(for: .milliseconds(5)) }
        #expect(rig.model.phase == .tool("list_announcements") && rig.model.canStop)
        rig.model.stop()
        #expect(rig.model.phase == .idle && rig.model.problem == .stopped)
        rig.model.draft = "Neu"
        #expect(rig.model.canSend)
        rig.model.retry()  // a stopped turn is not retried by accident
        #expect(rig.model.phase == .idle)
    }

    @Test("AGENT UX: a cold start is shown while the agent has said nothing")
    func warming() async {
        let rig = Rig(AgentStubScenario.annWarming.script)
        rig.model.send("Hallo")
        for _ in 0..<200 where rig.model.phase != .warming { try? await Task.sleep(for: .milliseconds(5)) }
        #expect(rig.model.phase == .warming)
        rig.model.stop()
    }

    @Test("AGENT UX: the history is trimmed to the api's limits; an over-long message is not sent")
    func historyLimits() async {
        let rig = Rig(StubAgentScript(turns: [StubTurn([.final(AgentTurnResult(reply: AgentReply(kind: .message, text: String(repeating: "x", count: 4000)), toolCalls: []))])]))
        for index in 1...14 {
            rig.model.send("Frage \(index)")
            await rig.settle()
        }
        let last = rig.stub.turns.last?.messages ?? []
        #expect(last.count == AgentChatModel.maxMessages)
        #expect(last.allSatisfy { $0.content.count <= AgentChatModel.maxMessageCharacters })
        #expect(last.last?.content == "Frage 14")
        let sent = rig.stub.turns.count
        rig.model.send(String(repeating: "y", count: 4001))
        #expect(rig.model.problem == .tooLong && rig.stub.turns.count == sent)
    }

    @Test("FR-AUTH-005 AGENT: a new conversation forgets everything and abandons a running task")
    func newConversation() async {
        let rig = Rig(AgentStubScenario.annDraft.script)
        rig.model.send("Entwurf")
        await rig.settle()
        rig.model.newConversation()
        #expect(rig.model.items.isEmpty && rig.model.phase == .idle && rig.model.problem == nil)
        rig.model.send("Hallo")
        await rig.settle()
        #expect(rig.stub.turns.last?.messages == [AgentMessage(role: .user, content: "Hallo")])
        let events = await rig.events()
        #expect(events.contains { $0.event == .taskAbandoned && $0.lastState == "new_conversation" })
    }

    @Test("EXP-005 AGENT: calls before the task is known and after it started share one run id")
    func runIdIsAdopted() async {
        let rig = Rig(AgentStubScenario.annOK.script)
        rig.model.send("Was gibt es Neues?")
        await rig.settle()
        let events = await rig.events()
        #expect(events.first?.taskRunId != nil)
    }

    @Test("EXP-001 AGENT: the tool decides the task; a running task is not replaced")
    func taskResolution() {
        #expect(AgentTask.resolve(toolNames: ["list_announcements"], feature: .comms) == .announcementsRead)
        #expect(AgentTask.resolve(toolNames: ["list_audience_options", "propose_announcement"], feature: .comms) == .announcementsPublish)
        #expect(AgentTask.resolve(toolNames: ["get_balance"], feature: .vacation) == .vacationBalance)
        #expect(AgentTask.resolve(toolNames: ["get_holidays"], feature: .vacation) == nil)
        #expect(AgentTask.resolve(toolNames: ["list_pending_approvals", "propose_decision"], feature: .vacation) == .vacationApproval)
        #expect(AgentTask.resolve(toolNames: ["get_team_coverage"], feature: .vacation) == .vacationCoverage)
        #expect(AgentTask.resolve(toolNames: ["get_balance"], feature: .comms) == nil)
        let ok = [AgentToolCall(name: "get_balance", ok: true)]
        let plain = AgentReply(kind: .message, text: "14")
        #expect(AgentTask.vacationBalance.isCompleted(by: plain, toolCalls: ok))
        #expect(!AgentTask.vacationBalance.isCompleted(by: plain, toolCalls: [AgentToolCall(name: "get_balance", ok: false)]))
        #expect(!AgentTask.vacationRequest.isCompleted(by: plain, toolCalls: ok))
        #expect(AgentTask.vacationRequest.isCompleted(by: AgentReply(kind: .submitted, text: "x"), toolCalls: ok))
    }
}
#endif
