import Foundation

/// Which hosted agent a chat talks to. The app picks it from the feature entry point (overview.md).
public enum AgentFeature: String, Sendable, CaseIterable {
    case comms, vacation, briefing
}

/// One turn of the history the device keeps and resends (PRIV-004: nothing is stored server-side).
public struct AgentMessage: Sendable, Equatable, Codable {
    public enum Role: String, Sendable, Codable { case user, assistant }
    public let role: Role
    public let content: String

    public init(role: Role, content: String) {
        self.role = role
        self.content = content
    }
}

/// `docs/architecture/agent-turn-contract.md`. Unknown kinds decode as `.message`.
public enum AgentReplyKind: String, Sendable, Equatable {
    case message, clarification, proposal, published
    case options, submitted, cancelled, decided
    /// Briefing: the opt-in write is done, and a summary of the user's own week (the api checked that
    /// `get_my_week` succeeded in this turn).
    case optedIn = "opted_in", summary
    case refusal

    /// A reply that reports a finished write (the api has verified the tool succeeded).
    public var isWriteResult: Bool {
        [.published, .submitted, .cancelled, .decided, .optedIn].contains(self)
    }
}

/// A candidate vacation range, each with its own stored proposal (FR-VAC-002).
public struct AgentOption: Sendable, Equatable, Identifiable {
    public let proposalId: String
    public let start: CalendarDay
    public let end: CalendarDay
    public var id: String { proposalId }

    public init(proposalId: String, start: CalendarDay, end: CalendarDay) {
        self.proposalId = proposalId
        self.start = start
        self.end = end
    }
}

/// An announcement an answer is based on (FR-ANN-003). The api checked the id and set the title.
public struct AgentSource: Sendable, Equatable, Identifiable {
    public let announcementId: String
    public let title: String
    public var id: String { announcementId }

    public init(announcementId: String, title: String) {
        self.announcementId = announcementId
        self.title = title
    }
}

public struct AgentReply: Sendable, Equatable {
    public let kind: AgentReplyKind
    public let text: String
    public let proposalId: String?
    public let options: [AgentOption]
    /// Refusals only: a short code such as `rule_bypass`. Unknown codes fall back to `text`.
    public let reason: String?
    public let sources: [AgentSource]
    /// Briefing summaries: events the text leaves out; the full list is the Briefing screen.
    public let omittedCount: Int?

    public init(
        kind: AgentReplyKind, text: String, proposalId: String? = nil, options: [AgentOption] = [],
        reason: String? = nil, sources: [AgentSource] = [], omittedCount: Int? = nil
    ) {
        self.kind = kind
        self.text = text
        self.proposalId = proposalId
        self.options = options
        self.reason = reason
        self.sources = sources
        self.omittedCount = omittedCount
    }
}

/// Names only: no arguments, no results (the api records what ran, not what it read).
public struct AgentToolCall: Sendable, Equatable {
    public let name: String
    public let ok: Bool

    public init(name: String, ok: Bool) {
        self.name = name
        self.ok = ok
    }
}

public struct AgentTurnResult: Sendable, Equatable {
    public let reply: AgentReply
    public let toolCalls: [AgentToolCall]

    public init(reply: AgentReply, toolCalls: [AgentToolCall]) {
        self.reply = reply
        self.toolCalls = toolCalls
    }
}

public enum AgentPhase: Sendable, Equatable {
    /// No word from the agent for a few seconds: its sandbox is starting.
    case warming
    case thinking
    case tool(String)
}

public enum AgentEvent: Sendable, Equatable {
    case status(AgentPhase)
    case toolFinished(AgentToolCall)
    /// Display-only text. `final` replaces everything shown so far.
    case delta(String)
    case final(AgentTurnResult)
}

/// The tap on the confirm card: the only way a write reaches an agent (FR-AUTH-006).
public struct AgentConfirmation: Sendable, Equatable {
    public let proposalId: String
    public let token: String

    public init(proposalId: String, token: String) {
        self.proposalId = proposalId
        self.token = token
    }
}

public enum AgentProposalKind: String, Sendable, Equatable {
    case announcement
    case vacation
    case vacationCancel = "vacation_cancel"
    case vacationDecision = "vacation_decision"
    case briefing
}

/// Confirm-card content from `GET /v1/proposals/{id}`: what the server stored, never model text (A-13).
public struct AgentProposalCard: Sendable, Equatable {
    public enum Content: Sendable, Equatable {
        case announcement(AnnouncementDraft, recipientCount: Int)
        case vacation(start: CalendarDay, end: CalendarDay, review: VacationReview)
        case vacationCancel(VacationRequestSummary)
        case vacationDecision(decision: VacationDecision, reason: String?, request: VacationRequestSummary)
        /// Turning the weekly briefing on or off: it reads the user's own calendar (FR-BRF-001.2).
        case briefing(enabled: Bool)
    }

    public let id: String
    public let kind: AgentProposalKind
    public let content: Content
    public let expiresAt: Date

    public init(id: String, kind: AgentProposalKind, content: Content, expiresAt: Date) {
        self.id = id
        self.kind = kind
        self.content = content
        self.expiresAt = expiresAt
    }
}

public enum AgentError: Error, Sendable, Equatable {
    case offline
    case unauthenticated
    /// 403 NOT_PROVISIONED or AGENT_UNAVAILABLE (consent), or a role the api denies.
    case forbidden
    /// 404: an unknown agent, or a proposal that is not yours or has expired.
    case notFound
    case tooLong
    /// 429. `retryAfter` is in seconds, from the `Retry-After` header.
    case rateLimited(retryAfter: Int?)
    /// 502/503 or an `error` event: the assistant could not be reached.
    case unavailable
    /// The stream ended without `final` or `error`.
    case interrupted
    /// `CONFIRMATION_REQUIRED` / `INVALID_CONFIRMATION`: expired, reused or tampered.
    case invalidConfirmation
    case failed(code: String?, correlationId: String?)

    /// Stable code for `task_error` events; never content.
    public var code: String {
        switch self {
        case .offline: "OFFLINE"
        case .unauthenticated: "UNAUTHENTICATED"
        case .forbidden: "FORBIDDEN"
        case .notFound: "NOT_FOUND"
        case .tooLong: "PAYLOAD_TOO_LARGE"
        case .rateLimited: "RATE_LIMITED"
        case .unavailable: "AGENT_UNAVAILABLE"
        case .interrupted: "AGENT_INTERRUPTED"
        case .invalidConfirmation: "INVALID_CONFIRMATION"
        case let .failed(code, _): code ?? "UNKNOWN"
        }
    }
}
