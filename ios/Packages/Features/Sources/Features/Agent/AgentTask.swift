import Core
import Foundation

/// The experiment task an AGENT chat is, learned from what the agent actually did (docs/experiment/metrics.md).
/// A chat spans tasks and the app is not told which one a participant was assigned, so the tools the api
/// reports (names only) decide. `T-VAC-REJ` is not emitted separately, as in CLASSIC: the protocol relabels.
public enum AgentTask: Equatable, Sendable {
    case announcementsRead, announcementsPublish
    case vacationBalance, vacationRequest, vacationApproval, vacationCoverage
    /// FR-BRF-001/002: asking for the week, including turning the briefing on first.
    case briefingView

    public var taskId: String {
        switch self {
        case .announcementsRead: "T-ANN-READ"
        case .announcementsPublish: "T-ANN-PUB"
        case .vacationBalance: "T-VAC-BAL"
        case .vacationRequest: "T-VAC-REQ"
        case .vacationApproval: "T-VAC-APR"
        case .vacationCoverage: "T-VAC-COV"
        case .briefingView: "T-BRF-VIEW"
        }
    }

    public var feature: String {
        switch self {
        case .announcementsRead, .announcementsPublish: "ann"
        case .briefingView: "brf"
        default: "vac"
        }
    }

    /// What `confirm_*` events report for this task.
    public var confirmAction: ExperimentEvent.Action {
        switch self {
        case .announcementsPublish: .publish
        case .vacationApproval: .decide
        case .briefingView: .optIn
        default: .request
        }
    }

    /// Writes finish on a write result; reads finish on a plain answer backed by a successful tool call.
    var isWrite: Bool {
        switch self {
        case .announcementsPublish, .vacationRequest, .vacationApproval: true
        default: false
        }
    }

    /// The first tool of a turn that says what the user is doing. Later tools in the same chat do not
    /// change a task that is already running.
    static func resolve(toolNames: [String], feature: AgentFeature) -> AgentTask? {
        for name in toolNames {
            switch (feature, name) {
            case (.comms, "propose_announcement"), (.comms, "publish_announcement"),
                 (.comms, "list_audience_options"), (.comms, "resolve_audience"):
                return .announcementsPublish
            case (.comms, "list_announcements"), (.comms, "get_announcement"):
                return .announcementsRead
            case (.vacation, "get_balance"), (.vacation, "list_vacation_requests"):
                return .vacationBalance
            case (.vacation, "propose_vacation_request"), (.vacation, "create_vacation_request"),
                 (.vacation, "propose_cancel"), (.vacation, "cancel_vacation_request"):
                return .vacationRequest
            case (.vacation, "list_pending_approvals"), (.vacation, "propose_decision"),
                 (.vacation, "decide_vacation_request"):
                return .vacationApproval
            case (.vacation, "get_team_coverage"):
                return .vacationCoverage
            case (.briefing, "get_briefing_status"), (.briefing, "get_my_week"),
                 (.briefing, "propose_briefing_optin"), (.briefing, "set_briefing_optin"):
                return .briefingView
            default: continue
            }
        }
        return nil
    }

    /// Whether this reply ends the task: a write result for writes, a plain answer for reads.
    func isCompleted(by reply: AgentReply, toolCalls: [AgentToolCall]) -> Bool {
        // The week is shown: a summary backed by a successful `get_my_week` (or the "No events" answer).
        if self == .briefingView { return reply.kind == .summary && toolCalls.contains { $0.name == "get_my_week" && $0.ok } }
        if isWrite { return reply.kind.isWriteResult }
        return reply.kind == .message && toolCalls.contains { $0.ok }
    }
}
