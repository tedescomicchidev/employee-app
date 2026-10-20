import Core
import Foundation

/// What a confirm card shows, built only from the stored proposal (A-13): never from model text.
struct AgentCardPresentation {
    var title: LocalizedStringResource
    var lines: [DSQuotedBlock.Line]
    var confirmTitle: LocalizedStringResource
    var footnote: LocalizedStringResource
}

enum AgentCardPresenter {
    /// What the card says once the write is done: the app's own words, from the stored proposal. The agent's
    /// sentence appears in the transcript, but a model-written claim is never what the card asserts (A-13).
    static func successText(_ content: AgentProposalCard.Content) -> LocalizedStringResource {
        switch content {
        case let .announcement(_, count): L10n.annSuccessTitle(count)
        case .vacation: L10n.agentCardDoneRequest
        case .vacationCancel: L10n.agentCardDoneCancel
        case let .vacationDecision(decision, _, _):
            decision == .approve ? L10n.agentCardDoneApprove : L10n.agentCardDoneReject
        }
    }

    static func present(_ content: AgentProposalCard.Content) -> AgentCardPresentation {
        switch content {
        case let .announcement(draft, count):
            return AgentCardPresentation(
                title: L10n.agentCardAnnTitle,
                lines: [
                    .init(L10n.agentCardFieldTitle, draft.title),
                    .init(L10n.agentCardFieldBody, draft.body),
                    .init(L10n.agentCardFieldLanguage, String(localized: L10n.annLanguage(draft.language))),
                    .init(
                        L10n.agentCardFieldAudience,
                        "\(L10n.annAudienceSummary(draft.audience)) · \(String(localized: L10n.annRecipients(count)))"),
                ],
                confirmTitle: L10n.agentCardAnnConfirm, footnote: L10n.agentCardAnnFootnote)
        case let .vacation(start, end, review):
            var lines: [DSQuotedBlock.Line] = [
                .init(L10n.agentCardFieldPeriod, VacationFormat.range(start, end, long: true)),
                .init(L10n.agentCardFieldDays, VacationFormat.days(review.countedDays)),
            ]
            if let after = review.remainingAfter {
                lines.append(.init(
                    L10n.agentCardFieldBalance,
                    "\(VacationFormat.days(review.remaining)) → \(VacationFormat.days(after))"))
            }
            if let approver = review.approver { lines.append(.init(L10n.agentCardFieldApprover, approver)) }
            return AgentCardPresentation(
                title: L10n.agentCardVacTitle, lines: lines,
                confirmTitle: L10n.agentCardVacConfirm, footnote: L10n.agentCardVacFootnote)
        case let .vacationCancel(request):
            return AgentCardPresentation(
                title: L10n.agentCardCancelTitle,
                lines: [
                    .init(L10n.agentCardFieldPeriod, VacationFormat.range(request.start, request.end, long: true)),
                    .init(L10n.agentCardFieldDays, VacationFormat.days(request.countedDays)),
                ],
                confirmTitle: L10n.agentCardCancelConfirm, footnote: L10n.agentCardCancelFootnote)
        case let .vacationDecision(decision, reason, request):
            var lines: [DSQuotedBlock.Line] = [
                .init(L10n.agentCardFieldEmployee, request.ownerName),
                .init(L10n.agentCardFieldPeriod, VacationFormat.range(request.start, request.end, long: true)),
                .init(L10n.agentCardFieldDays, VacationFormat.days(request.countedDays)),
            ]
            if let reason, !reason.isEmpty { lines.append(.init(L10n.agentCardFieldReason, reason)) }
            let approve = decision == .approve
            return AgentCardPresentation(
                title: approve ? L10n.agentCardApproveTitle : L10n.agentCardRejectTitle, lines: lines,
                confirmTitle: approve ? L10n.agentCardApproveConfirm : L10n.agentCardRejectConfirm,
                footnote: L10n.agentCardDecisionFootnote)
        }
    }
}

/// Agent text is shown verbatim and never interpreted as markup or links (FR-ANN-005). Lines that begin
/// with ">" are the agent quoting an announcement; they are shown in the quoted data block.
enum AgentText {
    enum Segment: Equatable {
        case plain(String)
        case quote(String)
    }

    static func segments(_ text: String) -> [Segment] {
        var segments: [Segment] = []
        var plain: [String] = []
        var quote: [String] = []
        func flushPlain() {
            let joined = plain.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !joined.isEmpty { segments.append(.plain(joined)) }
            plain = []
        }
        func flushQuote() {
            let joined = quote.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !joined.isEmpty { segments.append(.quote(joined)) }
            quote = []
        }
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.drop(while: { $0 == " " })
            if trimmed.hasPrefix(">") {
                flushPlain()
                quote.append(String(trimmed.dropFirst().drop(while: { $0 == " " })))
            } else {
                flushQuote()
                plain.append(String(line))
            }
        }
        flushPlain()
        flushQuote()
        return segments
    }
}
