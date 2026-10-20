import Core
import Foundation
import Observation

/// AGENT-mode chat for one feature (FR-ANN-* and FR-VAC-* AGENT variants). The device keeps the history and
/// resends it (PRIV-004); `api/` owns every rule, so this model only shows what the agent said and what
/// the stored proposal says, and lets the user confirm. Writes need a tap on the card (FR-AUTH-006): typed
/// "yes" is just another message.
@MainActor @Observable
public final class AgentChatModel {
    public enum Phase: Equatable {
        case idle
        /// No word from the agent for a few seconds: its sandbox is starting.
        case warming
        case thinking
        case tool(String)
        case streaming
        /// A confirmation turn is running; the write may already have happened, so it cannot be stopped.
        case executing
    }

    /// Why the last turn did not produce an answer. Every case but `stopped` offers a retry.
    public enum Problem: Equatable {
        case offline
        case signedOut
        case forbidden
        case tooLong
        case rateLimited(until: Date)
        case unavailable(code: String)
        case stopped
    }

    public struct Card: Equatable {
        public enum State: Equatable {
            case loading
            case proposal
            case executing
            /// The agent's own words after the write (the tool result, FR-ANN-001 / FR-VAC-002).
            case success(String)
            /// Nothing was written. `nil` means a generic failure; otherwise the agent's explanation.
            case failed(String?)
            case expired
            /// A newer proposal replaced this one.
            case superseded
            case cancelled
        }

        public let proposalId: String
        public var card: AgentProposalCard?
        public var state: State
    }

    public enum Content: Equatable {
        case user(String)
        case agent(AgentReply, tools: [AgentToolCall])
        /// Text still arriving. Display only: the final reply replaces it.
        case streaming(String)
        case card(Card)
    }

    public struct Item: Identifiable, Equatable {
        public let id: UUID
        public var content: Content
    }

    /// What VoiceOver should read once, when an answer is complete (A11Y-006).
    public struct Announcement: Equatable {
        public let id = UUID()
        public let text: String
    }

    public static let maxMessages = 20
    public static let maxMessageCharacters = 4000

    public private(set) var items: [Item] = []
    public private(set) var phase: Phase = .idle
    public private(set) var problem: Problem?
    public private(set) var isOffline = false
    public private(set) var announcement: Announcement?
    public var draft = ""

    public let feature: AgentFeature
    private let service: any AgentService
    private let accessToken: @Sendable () async throws -> String
    private let onReauthNeeded: @MainActor () -> Void
    private let makeFlow: @MainActor (AgentTask, UUID) -> TaskFlow
    private let connectivity: any Connectivity
    private let now: @Sendable () -> Date

    private var history: [AgentMessage] = []
    private var turnTask: Task<Void, Never>?
    private var rateLimitTask: Task<Void, Never>?
    /// What a retry sends again: the confirmation of the failed turn, if it was one (the token is idempotent).
    private var retryConfirmation: AgentConfirmation?
    private var retryProposalId: String?
    /// A failure while minting the token: retry asks for the token again (nothing was sent to the agent).
    private var retryMint: String?

    private var flow: TaskFlow?
    private var flowTask: AgentTask?
    /// Tags the calls of a chat whose task is not known yet; the flow later adopts it (EXP-005).
    private var pendingRunId = UUID()
    private var firstMessageAt: Date?
    private var userMessages = 0
    private var turnStartedAt = Date()
    private var firstTokenAt: Date?

    public init(
        feature: AgentFeature,
        service: any AgentService,
        accessToken: @escaping @Sendable () async throws -> String,
        onReauthNeeded: @escaping @MainActor () -> Void,
        makeFlow: @escaping @MainActor (AgentTask, UUID) -> TaskFlow,
        connectivity: any Connectivity = PathConnectivity(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.feature = feature
        self.service = service
        self.accessToken = accessToken
        self.onReauthNeeded = onReauthNeeded
        self.makeFlow = makeFlow
        self.connectivity = connectivity
        self.now = now
    }

    // MARK: Derived state

    public var isBusy: Bool { phase != .idle }
    public var isEmpty: Bool { items.isEmpty }
    /// Stop is offered while the agent works, but not while a confirmed write is in flight.
    public var canStop: Bool { isBusy && phase != .executing }

    public var isRateLimited: Bool {
        if case let .rateLimited(until) = problem { return until > now() }
        return false
    }

    public var canType: Bool { !isOffline && phase != .executing }

    public var canSend: Bool {
        !isBusy && !isOffline && !isRateLimited
            && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The card waiting for a tap, if any: the latest proposal that is still open.
    public var openCardId: String? {
        for item in items.reversed() {
            if case let .card(card) = item.content, card.state == .proposal { return card.proposalId }
        }
        return nil
    }

    /// The ranges the agent last offered (vacation), for screenshots and tests.
    public var lastOptions: [AgentOption] {
        for item in items.reversed() {
            if case let .agent(reply, _) = item.content, !reply.options.isEmpty { return reply.options }
        }
        return []
    }

    #if DEBUG
    /// Screenshots and UI tests: waits until the turn and any card load are done.
    public func waitUntilIdle() async {
        for _ in 0..<1_000 {
            let loading = items.contains { if case let .card(card) = $0.content { card.state == .loading } else { false } }
            if !isBusy, !loading { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
    #endif

    // MARK: Connectivity

    /// Run for the lifetime of the screen (`.task`): offline disables the composer instead of failing a turn.
    public func monitorConnectivity() async {
        for await online in connectivity.updates() {
            isOffline = !online
            if online, problem == .offline { problem = nil }
        }
    }

    // MARK: Sending

    /// Sends `text`, or the draft when nil. A suggested prompt is sent as typed text.
    public func send(_ text: String? = nil) {
        let message = (text ?? draft).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isBusy, !isOffline, !isRateLimited, !message.isEmpty else { return }
        guard message.count <= Self.maxMessageCharacters else {
            problem = .tooLong
            return
        }
        draft = ""
        flow?.tap()
        noteUserMessage()
        append(.user(message))
        history.append(AgentMessage(role: .user, content: message))
        run(confirmation: nil, proposalId: nil)
    }

    /// A vacation range the agent offered: shown as the user's choice, then its stored proposal becomes a card.
    public func choose(_ option: AgentOption, label: String) {
        guard !isBusy else { return }
        flow?.tap()
        noteUserMessage()
        append(.user(label))
        history.append(AgentMessage(role: .user, content: label))
        problem = nil
        supersedeOpenCards(except: option.proposalId)
        Task { await showCard(option.proposalId) }
    }

    /// Resends the failed turn. A failed confirmation turn resends the same token, so a write that did
    /// happen is not repeated (FR-AUTH-006, idempotent).
    public func retry() {
        guard !isBusy, problem != nil, problem != .stopped else { return }
        flow?.tap()
        if let id = retryMint, let content = card(id)?.card {
            retryMint = nil
            startConfirmation(id, content)
        } else {
            run(confirmation: retryConfirmation, proposalId: retryProposalId)
        }
    }

    public func stop() {
        guard canStop else { return }
        turnTask?.cancel()
        turnTask = nil
        removeStreaming()
        phase = .idle
        problem = .stopped
    }

    public func newConversation() {
        turnTask?.cancel()
        turnTask = nil
        rateLimitTask?.cancel()
        flow?.abandon(lastState: "new_conversation")
        items = []
        history = []
        phase = .idle
        problem = nil
        draft = ""
        retryConfirmation = nil
        retryProposalId = nil
        retryMint = nil
        resetTask()
    }

    // MARK: The confirm card

    /// The primary button. Only this call mints a confirmation token (FR-AUTH-006).
    public func confirm(proposalId: String) {
        guard !isBusy, let card = card(proposalId), card.state == .proposal, let content = card.card else { return }
        guard content.expiresAt > now() else {
            setCard(proposalId, .expired)
            return
        }
        flow?.tap()
        flow?.confirmAccepted()
        startConfirmation(proposalId, content)
    }

    private func startConfirmation(_ proposalId: String, _ content: AgentProposalCard) {
        setCard(proposalId, .executing)
        phase = .executing
        problem = nil
        turnTask = Task {
            do {
                let token = try await TaskRun.$current.withValue(runId) {
                    try await service.confirm(
                        proposalId: proposalId, kind: content.kind, accessToken: try await accessToken())
                }
                guard !Task.isCancelled else { return }
                let confirmation = AgentConfirmation(proposalId: proposalId, token: token)
                retryConfirmation = confirmation
                retryProposalId = proposalId
                await perform(confirmation: confirmation, proposalId: proposalId)
            } catch {
                phase = .idle
                switch error as? AgentError {
                case .invalidConfirmation, .notFound:
                    setCard(proposalId, .expired)
                case .offline:
                    setCard(proposalId, .proposal)
                    isOffline = true
                    problem = .offline
                default:
                    setCard(proposalId, .failed(nil))
                    retryMint = proposalId
                    fail(error)
                }
            }
        }
    }

    public func cancel(proposalId: String) {
        guard !isBusy, card(proposalId)?.state == .proposal else { return }
        flow?.tap()
        flow?.confirmRejected()
        setCard(proposalId, .cancelled)
        // The agent only knows what the history says; a declined card must not look pending to it.
        history.append(AgentMessage(role: .user, content: "I cancelled the proposal on the confirm card."))
    }

    // MARK: Turn

    private func run(confirmation: AgentConfirmation?, proposalId: String?) {
        retryConfirmation = confirmation
        retryProposalId = proposalId
        problem = nil
        phase = confirmation == nil ? .thinking : .executing
        if let proposalId { setCard(proposalId, .executing) }
        turnTask?.cancel()
        turnTask = Task { await perform(confirmation: confirmation, proposalId: proposalId) }
    }

    private var runId: UUID { flow?.activeRunId ?? pendingRunId }

    private func perform(confirmation: AgentConfirmation?, proposalId: String?) async {
        turnStartedAt = now()
        firstTokenAt = nil
        var streamed = ""
        let messages = trimmedHistory()
        do {
            let token = try await accessToken()
            let stream = TaskRun.$current.withValue(runId) {
                service.turn(feature, messages: messages, confirmation: confirmation, accessToken: token)
            }
            for try await event in stream {
                switch event {
                case let .status(status):
                    guard streamed.isEmpty, confirmation == nil else { continue }
                    switch status {
                    case .warming: phase = .warming
                    case .thinking: phase = .thinking
                    case let .tool(name): phase = .tool(name)
                    }
                case .toolFinished:
                    continue
                case let .delta(text):
                    if firstTokenAt == nil { firstTokenAt = now() }
                    streamed += text
                    showStreaming(streamed)
                    if confirmation == nil { phase = .streaming }
                case let .final(result):
                    await finish(result, confirmation: confirmation, proposalId: proposalId)
                    return
                }
            }
            if Task.isCancelled { return }  // stopped: `stop()` already cleaned up
            throw AgentError.interrupted
        } catch is CancellationError {
            return
        } catch AuthError.interactionRequired {
            removeStreaming()
            onReauthNeeded()
            failTurn(.signedOut, code: "UNAUTHENTICATED", proposalId: proposalId)
        } catch {
            if Task.isCancelled { return }
            removeStreaming()
            if let proposalId { setCard(proposalId, .failed(nil)) }
            phase = .idle
            fail(error)
        }
    }

    private func finish(_ result: AgentTurnResult, confirmation: AgentConfirmation?, proposalId: String?) async {
        removeStreaming()
        let reply = result.reply
        phase = .idle
        isOffline = false
        problem = nil
        retryConfirmation = nil
        retryProposalId = nil
        retryMint = nil

        resolveFlow(result.toolCalls)
        let elapsed = Int(now().timeIntervalSince(turnStartedAt) * 1000)
        let firstToken = firstTokenAt.map { Int($0.timeIntervalSince(turnStartedAt) * 1000) }
        flow?.agentTurn(firstTokenMs: firstToken, totalMs: elapsed, toolCalls: result.toolCalls.count)

        append(.agent(reply, tools: result.toolCalls))
        if !reply.text.isEmpty {
            history.append(AgentMessage(role: .assistant, content: String(reply.text.prefix(Self.maxMessageCharacters))))
        }
        announcement = Announcement(text: reply.text)

        if let proposalId {
            // The confirmation turn: a write result is the only success; anything else wrote nothing.
            if reply.kind.isWriteResult {
                setCard(proposalId, .success(reply.text))
            } else {
                setCard(proposalId, .failed(reply.text))
                flow?.error(code: "AGENT_TOOL_FAILURE", recovered: false)
            }
        }

        if let task = flowTask, task.isCompleted(by: reply, toolCalls: result.toolCalls) {
            flow?.complete(outcomeValid: true, messageCount: userMessages)
            resetTask()
        }

        if reply.kind == .proposal, let id = reply.proposalId {
            supersedeOpenCards(except: id)
            await showCard(id)
        }
    }

    private func failTurn(_ problem: Problem, code: String, proposalId: String?) {
        if let proposalId { setCard(proposalId, .failed(nil)) }
        phase = .idle
        self.problem = problem
        flow?.error(code: code, recovered: false)
    }

    private func fail(_ error: Error) {
        let agentError = error as? AgentError ?? .failed(code: nil, correlationId: nil)
        switch agentError {
        case .offline:
            isOffline = true
            problem = .offline
        case .unauthenticated:
            onReauthNeeded()
            problem = .signedOut
        case .forbidden:
            problem = .forbidden
        case .tooLong:
            problem = .tooLong
        case let .rateLimited(retryAfter):
            let until = now().addingTimeInterval(TimeInterval(max(retryAfter ?? 30, 1)))
            problem = .rateLimited(until: until)
            scheduleRateLimitEnd(until)
        default:
            problem = .unavailable(code: agentError.code)
        }
        flow?.error(code: agentError.code, recovered: false)
    }

    private func scheduleRateLimitEnd(_ until: Date) {
        rateLimitTask?.cancel()
        let delay = max(until.timeIntervalSince(now()), 0)
        rateLimitTask = Task {
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, case .rateLimited = problem else { return }
            problem = nil
        }
    }

    // MARK: Cards

    private func showCard(_ id: String) async {
        let existing = card(id)
        if existing == nil { append(.card(Card(proposalId: id, card: nil, state: .loading))) }
        else { setCard(id, .loading) }
        do {
            let token = try await accessToken()
            let loaded = try await TaskRun.$current.withValue(runId) {
                try await service.proposal(id: id, accessToken: token)
            }
            updateCard(id) { $0.card = loaded; $0.state = loaded.expiresAt > now() ? .proposal : .expired }
            if card(id)?.state == .proposal { flow?.confirmShown() }
        } catch AgentError.notFound {
            setCard(id, .expired)
        } catch AuthError.interactionRequired {
            onReauthNeeded()
            setCard(id, .failed(nil))
        } catch {
            if case .offline = error as? AgentError { isOffline = true }
            setCard(id, .failed(nil))
        }
    }

    private func card(_ id: String) -> Card? {
        for item in items { if case let .card(card) = item.content, card.proposalId == id { return card } }
        return nil
    }

    private func updateCard(_ id: String, _ change: (inout Card) -> Void) {
        for index in items.indices {
            if case var .card(card) = items[index].content, card.proposalId == id {
                change(&card)
                items[index].content = .card(card)
                return
            }
        }
    }

    private func setCard(_ id: String, _ state: Card.State) { updateCard(id) { $0.state = state } }

    /// A newer proposal makes the earlier open ones obsolete: only the latest can be confirmed.
    private func supersedeOpenCards(except id: String) {
        for item in items {
            if case let .card(card) = item.content, card.proposalId != id, card.state == .proposal {
                setCard(card.proposalId, .superseded)
            }
        }
    }

    // MARK: Transcript

    private func append(_ content: Content) { items.append(Item(id: UUID(), content: content)) }

    private func showStreaming(_ text: String) {
        if let index = items.lastIndex(where: { if case .streaming = $0.content { true } else { false } }) {
            items[index].content = .streaming(text)
        } else {
            append(.streaming(text))
        }
    }

    private func removeStreaming() {
        items.removeAll { if case .streaming = $0.content { true } else { false } }
    }

    /// The last `maxMessages`, each within the api's limit (it rejects a longer one with 413).
    private func trimmedHistory() -> [AgentMessage] {
        history.suffix(Self.maxMessages).map {
            AgentMessage(role: $0.role, content: String($0.content.prefix(Self.maxMessageCharacters)))
        }
    }

    // MARK: Experiment events

    private func noteUserMessage() {
        if firstMessageAt == nil { firstMessageAt = now() }
        userMessages += 1
    }

    /// The first tool the agent used says which task this is; the flow starts back-dated to the first message.
    private func resolveFlow(_ calls: [AgentToolCall]) {
        guard flow == nil, let task = AgentTask.resolve(toolNames: calls.map(\.name), feature: feature) else { return }
        let started = makeFlow(task, pendingRunId)
        started.start(at: firstMessageAt ?? now())
        flow = started
        flowTask = task
    }

    private func resetTask() {
        flow = nil
        flowTask = nil
        pendingRunId = UUID()
        firstMessageAt = nil
        userMessages = 0
    }
}
