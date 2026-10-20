import Core
import Foundation

/// Typed keys for the AGENT chat (Resources/Localizable.xcstrings, `agent.*`). No string literals in views.
extension L10n {
    static var agentTitle: LocalizedStringResource { .init("agent.title", bundle: bundle) }
    static var agentNew: LocalizedStringResource { .init("agent.new", bundle: bundle) }
    static var agentEmptyTitle: LocalizedStringResource { .init("agent.empty.title", bundle: bundle) }
    static var agentEmptyAnnReader: LocalizedStringResource { .init("agent.empty.ann.reader", bundle: bundle) }
    static var agentEmptyAnnPublisher: LocalizedStringResource { .init("agent.empty.ann.publisher", bundle: bundle) }
    static var agentEmptyVacEmployee: LocalizedStringResource { .init("agent.empty.vac.employee", bundle: bundle) }
    static var agentEmptyVacManager: LocalizedStringResource { .init("agent.empty.vac.manager", bundle: bundle) }
    static var agentSuggestAnnNew: LocalizedStringResource { .init("agent.suggest.ann.new", bundle: bundle) }
    static var agentSuggestAnnHours: LocalizedStringResource { .init("agent.suggest.ann.hours", bundle: bundle) }
    static var agentSuggestAnnPublish: LocalizedStringResource { .init("agent.suggest.ann.publish", bundle: bundle) }
    static var agentSuggestVacBalance: LocalizedStringResource { .init("agent.suggest.vac.balance", bundle: bundle) }
    static var agentSuggestVacRequest: LocalizedStringResource { .init("agent.suggest.vac.request", bundle: bundle) }
    static var agentSuggestVacHolidays: LocalizedStringResource { .init("agent.suggest.vac.holidays", bundle: bundle) }
    static var agentSuggestVacPending: LocalizedStringResource { .init("agent.suggest.vac.pending", bundle: bundle) }
    static var agentSuggestVacCoverage: LocalizedStringResource { .init("agent.suggest.vac.coverage", bundle: bundle) }
    static var agentComposerPlaceholder: LocalizedStringResource { .init("agent.composer.placeholder", bundle: bundle) }
    static var agentComposerOffline: LocalizedStringResource { .init("agent.composer.offline", bundle: bundle) }
    static var agentSend: LocalizedStringResource { .init("agent.send", bundle: bundle) }
    static var agentStop: LocalizedStringResource { .init("agent.stop", bundle: bundle) }
    static var agentStatusThinking: LocalizedStringResource { .init("agent.status.thinking", bundle: bundle) }
    static var agentStatusWarming: LocalizedStringResource { .init("agent.status.warming", bundle: bundle) }
    static var agentStatusWorking: LocalizedStringResource { .init("agent.status.working", bundle: bundle) }
    static var agentA11yStreaming: LocalizedStringResource { .init("agent.a11y.streaming", bundle: bundle) }
    static var agentA11yYou: LocalizedStringResource { .init("agent.a11y.you", bundle: bundle) }
    static var agentA11yAssistant: LocalizedStringResource { .init("agent.a11y.assistant", bundle: bundle) }
    static var agentA11yRefusal: LocalizedStringResource { .init("agent.a11y.refusal", bundle: bundle) }
    static var agentSummaryTitle: LocalizedStringResource { .init("agent.summary.title", bundle: bundle) }
    static var agentSourceHint: LocalizedStringResource { .init("agent.source.hint", bundle: bundle) }
    static var agentQuoteLabel: LocalizedStringResource { .init("agent.quote.label", bundle: bundle) }
    static var agentRefusalGeneric: LocalizedStringResource { .init("agent.refusal.generic", bundle: bundle) }
    static var agentOptionHint: LocalizedStringResource { .init("agent.option.hint", bundle: bundle) }
    static var agentRetry: LocalizedStringResource { .init("agent.retry", bundle: bundle) }
    static var agentProblemOffline: LocalizedStringResource { .init("agent.problem.offline", bundle: bundle) }
    static var agentProblemSignedOut: LocalizedStringResource { .init("agent.problem.signedout", bundle: bundle) }
    static var agentProblemForbidden: LocalizedStringResource { .init("agent.problem.forbidden", bundle: bundle) }
    static var agentProblemTooLong: LocalizedStringResource { .init("agent.problem.toolong", bundle: bundle) }
    static var agentProblemRateLimited: LocalizedStringResource { .init("agent.problem.ratelimited", bundle: bundle) }
    static var agentProblemUnavailable: LocalizedStringResource { .init("agent.problem.unavailable", bundle: bundle) }
    static var agentProblemStopped: LocalizedStringResource { .init("agent.problem.stopped", bundle: bundle) }
    static var agentCardFieldTitle: LocalizedStringResource { .init("agent.card.field.title", bundle: bundle) }
    static var agentCardFieldBody: LocalizedStringResource { .init("agent.card.field.body", bundle: bundle) }
    static var agentCardFieldLanguage: LocalizedStringResource { .init("agent.card.field.language", bundle: bundle) }
    static var agentCardFieldAudience: LocalizedStringResource { .init("agent.card.field.audience", bundle: bundle) }
    static var agentCardFieldPeriod: LocalizedStringResource { .init("agent.card.field.period", bundle: bundle) }
    static var agentCardFieldDays: LocalizedStringResource { .init("agent.card.field.days", bundle: bundle) }
    static var agentCardFieldBalance: LocalizedStringResource { .init("agent.card.field.balance", bundle: bundle) }
    static var agentCardFieldApprover: LocalizedStringResource { .init("agent.card.field.approver", bundle: bundle) }
    static var agentCardFieldEmployee: LocalizedStringResource { .init("agent.card.field.employee", bundle: bundle) }
    static var agentCardFieldReason: LocalizedStringResource { .init("agent.card.field.reason", bundle: bundle) }
    static var agentCardAnnTitle: LocalizedStringResource { .init("agent.card.ann.title", bundle: bundle) }
    static var agentCardAnnConfirm: LocalizedStringResource { .init("agent.card.ann.confirm", bundle: bundle) }
    static var agentCardAnnFootnote: LocalizedStringResource { .init("agent.card.ann.footnote", bundle: bundle) }
    static var agentCardVacTitle: LocalizedStringResource { .init("agent.card.vac.title", bundle: bundle) }
    static var agentCardVacConfirm: LocalizedStringResource { .init("agent.card.vac.confirm", bundle: bundle) }
    static var agentCardVacFootnote: LocalizedStringResource { .init("agent.card.vac.footnote", bundle: bundle) }
    static var agentCardCancelTitle: LocalizedStringResource { .init("agent.card.cancel.title", bundle: bundle) }
    static var agentCardCancelConfirm: LocalizedStringResource { .init("agent.card.cancel.confirm", bundle: bundle) }
    static var agentCardCancelFootnote: LocalizedStringResource { .init("agent.card.cancel.footnote", bundle: bundle) }
    static var agentCardApproveTitle: LocalizedStringResource { .init("agent.card.approve.title", bundle: bundle) }
    static var agentCardApproveConfirm: LocalizedStringResource { .init("agent.card.approve.confirm", bundle: bundle) }
    static var agentCardRejectTitle: LocalizedStringResource { .init("agent.card.reject.title", bundle: bundle) }
    static var agentCardRejectConfirm: LocalizedStringResource { .init("agent.card.reject.confirm", bundle: bundle) }
    static var agentCardDecisionFootnote: LocalizedStringResource { .init("agent.card.decision.footnote", bundle: bundle) }
    static var agentCardValid: LocalizedStringResource { .init("agent.card.valid", bundle: bundle) }
    static var agentCardLoading: LocalizedStringResource { .init("agent.card.loading", bundle: bundle) }
    static var agentCardUnavailable: LocalizedStringResource { .init("agent.card.unavailable", bundle: bundle) }
    static var agentCardFailed: LocalizedStringResource { .init("agent.card.state.failed", bundle: bundle) }
    static var agentCardExpired: LocalizedStringResource { .init("agent.card.state.expired", bundle: bundle) }
    static var agentCardSuperseded: LocalizedStringResource { .init("agent.card.state.superseded", bundle: bundle) }
    static var agentCardCancelled: LocalizedStringResource { .init("agent.card.state.cancelled", bundle: bundle) }
    static var agentCardNotDone: LocalizedStringResource { .init("agent.card.state.notdone", bundle: bundle) }
    static var agentCardDoneRequest: LocalizedStringResource { .init("agent.card.done.request", bundle: bundle) }
    static var agentCardDoneCancel: LocalizedStringResource { .init("agent.card.done.cancel", bundle: bundle) }
    static var agentCardDoneApprove: LocalizedStringResource { .init("agent.card.done.approve", bundle: bundle) }
    static var agentCardDoneReject: LocalizedStringResource { .init("agent.card.done.reject", bundle: bundle) }
    static var agentSuccessRequests: LocalizedStringResource { .init("agent.success.requests", bundle: bundle) }
    static func agentProblemReference(_ code: String) -> LocalizedStringResource {
        .init("agent.problem.reference", defaultValue: "Reference: \(code)", bundle: bundle)
    }

    /// The phrase while a tool runs ("Checking your balance").
    static func agentToolRunning(_ name: String) -> LocalizedStringResource {
        switch name {
        case "list_announcements": .init("agent.tool.list_announcements.run", bundle: bundle)
        case "get_announcement": .init("agent.tool.get_announcement.run", bundle: bundle)
        case "list_audience_options": .init("agent.tool.list_audience_options.run", bundle: bundle)
        case "resolve_audience": .init("agent.tool.resolve_audience.run", bundle: bundle)
        case "propose_announcement": .init("agent.tool.propose_announcement.run", bundle: bundle)
        case "publish_announcement": .init("agent.tool.publish_announcement.run", bundle: bundle)
        case "get_balance": .init("agent.tool.get_balance.run", bundle: bundle)
        case "get_holidays": .init("agent.tool.get_holidays.run", bundle: bundle)
        case "list_vacation_requests": .init("agent.tool.list_vacation_requests.run", bundle: bundle)
        case "get_team_coverage": .init("agent.tool.get_team_coverage.run", bundle: bundle)
        case "list_pending_approvals": .init("agent.tool.list_pending_approvals.run", bundle: bundle)
        case "propose_vacation_request": .init("agent.tool.propose_vacation_request.run", bundle: bundle)
        case "create_vacation_request": .init("agent.tool.create_vacation_request.run", bundle: bundle)
        case "propose_cancel": .init("agent.tool.propose_cancel.run", bundle: bundle)
        case "cancel_vacation_request": .init("agent.tool.cancel_vacation_request.run", bundle: bundle)
        case "propose_decision": .init("agent.tool.propose_decision.run", bundle: bundle)
        case "decide_vacation_request": .init("agent.tool.decide_vacation_request.run", bundle: bundle)
        default: .init("agent.tool.generic.run", bundle: bundle)
        }
    }

    /// The same step once it finished, for "what the assistant did".
    static func agentToolDone(_ name: String) -> LocalizedStringResource {
        switch name {
        case "list_announcements": .init("agent.tool.list_announcements.done", bundle: bundle)
        case "get_announcement": .init("agent.tool.get_announcement.done", bundle: bundle)
        case "list_audience_options": .init("agent.tool.list_audience_options.done", bundle: bundle)
        case "resolve_audience": .init("agent.tool.resolve_audience.done", bundle: bundle)
        case "propose_announcement": .init("agent.tool.propose_announcement.done", bundle: bundle)
        case "publish_announcement": .init("agent.tool.publish_announcement.done", bundle: bundle)
        case "get_balance": .init("agent.tool.get_balance.done", bundle: bundle)
        case "get_holidays": .init("agent.tool.get_holidays.done", bundle: bundle)
        case "list_vacation_requests": .init("agent.tool.list_vacation_requests.done", bundle: bundle)
        case "get_team_coverage": .init("agent.tool.get_team_coverage.done", bundle: bundle)
        case "list_pending_approvals": .init("agent.tool.list_pending_approvals.done", bundle: bundle)
        case "propose_vacation_request": .init("agent.tool.propose_vacation_request.done", bundle: bundle)
        case "create_vacation_request": .init("agent.tool.create_vacation_request.done", bundle: bundle)
        case "propose_cancel": .init("agent.tool.propose_cancel.done", bundle: bundle)
        case "cancel_vacation_request": .init("agent.tool.cancel_vacation_request.done", bundle: bundle)
        case "propose_decision": .init("agent.tool.propose_decision.done", bundle: bundle)
        case "decide_vacation_request": .init("agent.tool.decide_vacation_request.done", bundle: bundle)
        default: .init("agent.tool.generic.done", bundle: bundle)
        }
    }
}
