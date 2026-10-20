import Foundation

/// One scripted agent turn: the events it streams, then how it ends.
public struct StubTurn: Sendable {
    public enum Ending: Sendable, Equatable {
        case finish
        /// Stay open until the consumer cancels (the "stop" button, a screenshot of the working state).
        case hang
        case fail(AgentError)
    }

    public var events: [AgentEvent]
    public var ending: Ending

    public init(_ events: [AgentEvent], ending: Ending = .finish) {
        self.events = events
        self.ending = ending
    }
}

/// Everything a scenario needs: turns in order, the cards behind its proposal ids, and how confirm behaves.
public struct StubAgentScript: Sendable {
    public var turns: [StubTurn]
    public var cards: [String: AgentProposalCard]
    public var confirmFailure: AgentError?
    public var proposalFailure: AgentError?

    public init(
        turns: [StubTurn] = [], cards: [String: AgentProposalCard] = [:], confirmFailure: AgentError? = nil,
        proposalFailure: AgentError? = nil
    ) {
        self.turns = turns
        self.cards = cards
        self.confirmFailure = confirmFailure
        self.proposalFailure = proposalFailure
    }
}

/// Deterministic agent for unit tests, UI tests and screenshots (DEBUG launch arguments). Turns are
/// consumed in order; once they run out the last one repeats. Records what the app sent.
/// `@unchecked Sendable`: every mutable property is read and written only under `lock`.
public final class StubAgentService: AgentService, @unchecked Sendable {
    public struct SentTurn: Sendable, Equatable {
        public let feature: AgentFeature
        public let messages: [AgentMessage]
        public let confirmation: AgentConfirmation?
    }

    private let lock = NSLock()
    private var script: StubAgentScript
    private var next = 0
    private var sent: [SentTurn] = []
    private var confirmed: [String] = []
    private let pace: Duration
    private let ttl: TimeInterval
    private let now: @Sendable () -> Date

    /// - Parameters:
    ///   - pace: delay between streamed events (zero in unit tests).
    ///   - ttl: how long a proposal card is valid from the moment it is fetched.
    public init(
        script: StubAgentScript, pace: Duration = .zero, ttl: TimeInterval = 300,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.script = script
        self.pace = pace
        self.ttl = ttl
        self.now = now
    }

    public var turns: [SentTurn] { lock.withLock { sent } }

    /// Tests: change how confirmation behaves mid-scenario (a failure that goes away).
    public func setConfirmFailure(_ failure: AgentError?) { lock.withLock { script.confirmFailure = failure } }
    /// Proposal ids a confirmation token was minted for, in order.
    public var confirmedProposals: [String] { lock.withLock { confirmed } }

    private func take(_ record: SentTurn) -> StubTurn? {
        lock.withLock {
            sent.append(record)
            guard !script.turns.isEmpty else { return nil }
            defer { next += 1 }
            return script.turns[min(next, script.turns.count - 1)]
        }
    }

    public func turn(
        _ feature: AgentFeature, messages: [AgentMessage], confirmation: AgentConfirmation?,
        accessToken: String
    ) -> AsyncThrowingStream<AgentEvent, Error> {
        let record = SentTurn(feature: feature, messages: messages, confirmation: confirmation)
        let step = take(record)
        let pace = pace
        return AsyncThrowingStream { continuation in
            let task = Task {
                guard let step else {
                    continuation.finish(throwing: AgentError.unavailable)
                    return
                }
                do {
                    for event in step.events {
                        if pace > .zero { try await Task.sleep(for: pace) }
                        try Task.checkCancellation()
                        continuation.yield(event)
                    }
                    switch step.ending {
                    case .finish: continuation.finish()
                    case let .fail(error): continuation.finish(throwing: error)
                    case .hang:
                        while true { try await Task.sleep(for: .seconds(3600)) }
                    }
                } catch {
                    continuation.finish()  // cancelled
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func proposal(id: String, accessToken: String) async throws -> AgentProposalCard {
        let (card, failure) = lock.withLock { (script.cards[id], script.proposalFailure) }
        if let failure { throw failure }
        guard let card else { throw AgentError.notFound }
        return AgentProposalCard(
            id: card.id, kind: card.kind, content: card.content, expiresAt: now().addingTimeInterval(ttl))
    }

    public func confirm(proposalId: String, kind: AgentProposalKind, accessToken: String) async throws -> String {
        let failure = lock.withLock { script.confirmFailure }
        if let failure { throw failure }
        lock.withLock { confirmed.append(proposalId) }
        return "stub-confirmation-token-\(proposalId)"
    }
}
