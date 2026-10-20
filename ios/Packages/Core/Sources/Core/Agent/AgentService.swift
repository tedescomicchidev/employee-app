import Foundation

/// AGENT-mode path to `api/` (never Foundry): one chat turn as a stream of events, the confirm-card
/// content of a stored proposal, and the confirmation that mints the one-time token (FR-AUTH-006).
public protocol AgentService: Sendable {
    /// Streams `status`/`tool`/`delta` events and ends with exactly one `.final`, or throws.
    /// Cancelling the consuming task closes the connection.
    func turn(
        _ feature: AgentFeature, messages: [AgentMessage], confirmation: AgentConfirmation?,
        accessToken: String
    ) -> AsyncThrowingStream<AgentEvent, Error>

    func proposal(id: String, accessToken: String) async throws -> AgentProposalCard

    /// The card's primary button: the only call that yields a `confirmation_token`.
    func confirm(proposalId: String, kind: AgentProposalKind, accessToken: String) async throws -> String
}

public struct UnconfiguredAgentService: AgentService {
    public init() {}

    public func turn(
        _ feature: AgentFeature, messages: [AgentMessage], confirmation: AgentConfirmation?,
        accessToken: String
    ) -> AsyncThrowingStream<AgentEvent, Error> {
        AsyncThrowingStream { $0.finish(throwing: AgentError.unavailable) }
    }

    public func proposal(id: String, accessToken: String) async throws -> AgentProposalCard {
        throw AgentError.unavailable
    }

    public func confirm(proposalId: String, kind: AgentProposalKind, accessToken: String) async throws -> String {
        throw AgentError.unavailable
    }
}
