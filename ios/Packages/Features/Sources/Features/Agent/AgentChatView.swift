import Core
import SwiftUI

/// Per-feature copy and links of an agent chat.
struct AgentChatConfig {
    let emptyMessage: LocalizedStringResource
    let suggestions: [LocalizedStringResource]
    /// Opens an announcement the answer is based on, in the classic detail screen.
    var openSource: (String) -> Void = { _ in }
    /// After a vacation write: the classic list of the user's requests.
    var openRequests: (() -> Void)?
}

/// The agent composer inside a feature (docs/design/mockups: `<feature>-agent_chat-*`). Shows the
/// conversation, the thinking and tool status while a turn runs, native confirm cards, and the composer.
struct AgentChatView: View {
    @Bindable var model: AgentChatModel
    let config: AgentChatConfig
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AccessibilityFocusState private var focusedCard: String?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: DSSpacing.s) {
                    if model.isEmpty { emptyState }
                    ForEach(model.items) { item in
                        row(item).id(item.id)
                    }
                    statusRow
                    problemBanner
                    Color.clear.frame(height: 1).id(Self.bottom)
                }
                .padding(DSSpacing.gutter)
            }
            .scrollDismissesKeyboard(.interactively)
            .defaultScrollAnchor(.bottom)
            .onChange(of: model.items) { scrollToBottom(proxy) }
            .onChange(of: model.phase) { scrollToBottom(proxy) }
            .onChange(of: model.problem) { scrollToBottom(proxy) }
        }
        .background(DSColor.bg)
        .safeAreaInset(edge: .bottom, spacing: 0) { composer }
        .task { await model.monitorConnectivity() }
        .onChange(of: model.announcement) { _, announcement in
            if let text = announcement?.text, !text.isEmpty { AccessibilityNotification.Announcement(text).post() }
        }
        .onChange(of: model.openCardId) { _, id in if let id { focusedCard = id } }
    }

    private static let bottom = "agent.bottom"

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { proxy.scrollTo(Self.bottom, anchor: .bottom) }
    }

    // MARK: Empty

    private var emptyState: some View {
        VStack(spacing: DSSpacing.m) {
            DSEmptyState(symbol: "bubble.left", title: L10n.agentEmptyTitle, message: config.emptyMessage)
            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                ForEach(Array(config.suggestions.enumerated()), id: \.offset) { index, suggestion in
                    DSPickChip(Text(suggestion), isSelected: false) { model.send(String(localized: suggestion)) }
                        .disabled(!model.canType || model.isBusy)
                        .accessibilityIdentifier("agent.suggestion.\(index)")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // `.contain` first: a bare identifier on a container would replace the ids of what is inside it.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("agent.empty")
    }

    // MARK: Items

    @ViewBuilder private func row(_ item: AgentChatModel.Item) -> some View {
        switch item.content {
        case let .user(text):
            DSChatBubble(.user, text: text)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(L10n.agentA11yYou) + Text(verbatim: text))
                .accessibilityIdentifier("agent.message.user")
        case let .streaming(text):
            DSChatBubble(.agent, text: text, spokenOverride: L10n.agentA11yStreaming)
                .accessibilityIdentifier("agent.message.streaming")
        case let .agent(reply, tools):
            AgentReplyView(reply: reply, tools: tools, config: config, model: model)
        case let .card(card):
            AgentCardView(card: card, model: model, config: config)
                .accessibilityFocused($focusedCard, equals: card.proposalId)
        }
    }

    // MARK: Status and problems

    @ViewBuilder private var statusRow: some View {
        switch model.phase {
        case .warming:
            DSThinkingBubble(L10n.agentStatusWarming).accessibilityIdentifier("agent.status.warming")
        case .thinking:
            DSThinkingBubble(L10n.agentStatusThinking).accessibilityIdentifier("agent.status.thinking")
        case let .tool(name):
            DSThinkingBubble(L10n.agentToolRunning(name)).accessibilityIdentifier("agent.status.tool")
        case .idle, .streaming, .executing:
            EmptyView()
        }
    }

    @ViewBuilder private var problemBanner: some View {
        if let problem = model.problem {
            VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                switch problem {
                case .offline:
                    DSBanner(.offline, message: Text(L10n.agentProblemOffline))
                case .signedOut:
                    DSBanner(.error, message: Text(L10n.agentProblemSignedOut),
                             actionTitle: L10n.agentRetry, action: model.retry)
                case .forbidden:
                    DSBanner(.error, message: Text(L10n.agentProblemForbidden))
                case .tooLong:
                    DSBanner(.info, message: Text(L10n.agentProblemTooLong))
                case let .rateLimited(until):
                    DSBanner(.error, message: Text(L10n.agentProblemRateLimited) + Text(" ") + Text(until, style: .timer))
                case let .unavailable(code):
                    DSBanner(.error, message: Text(L10n.agentProblemUnavailable),
                             actionTitle: L10n.agentRetry, action: model.retry)
                    Text(L10n.agentProblemReference(code)).font(DSFont.code).foregroundStyle(DSColor.ink2)
                        .padding(.horizontal, DSSpacing.s)
                case .stopped:
                    DSBanner(.info, message: Text(L10n.agentProblemStopped))
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("agent.problem")
        }
    }

    // MARK: Composer

    private var composer: some View {
        VStack(spacing: DSSpacing.xs) {
            if model.isOffline && model.problem != .offline {
                DSBanner(.offline, message: Text(L10n.agentProblemOffline))
            }
            DSComposer(
                text: $model.draft,
                placeholder: model.isOffline ? L10n.agentComposerOffline : L10n.agentComposerPlaceholder,
                sendLabel: L10n.agentSend, stopLabel: L10n.agentStop,
                isRunning: model.canStop, isEnabled: model.canType && !model.isRateLimited,
                onSend: { model.send() }, onStop: model.stop)
        }
        .padding(.horizontal, DSSpacing.s)
        .padding(.vertical, DSSpacing.xs)
        .background(.bar)
    }
}

/// A finished agent reply: text (with quoted announcement text as data), refusals, sources, offered ranges
/// and "what the assistant did".
private struct AgentReplyView: View {
    let reply: AgentReply
    let tools: [AgentToolCall]
    let config: AgentChatConfig
    let model: AgentChatModel

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            if reply.kind == .refusal {
                let text = reply.text.isEmpty ? String(localized: L10n.agentRefusalGeneric) : reply.text
                DSRefusalBubble(text: text)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(L10n.agentA11yRefusal) + Text(verbatim: text))
                    .accessibilityIdentifier("agent.refusal")
            } else {
                ForEach(Array(AgentText.segments(reply.text).enumerated()), id: \.offset) { _, segment in
                    switch segment {
                    case let .plain(text):
                        DSChatBubble(.agent, text: text)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(Text(L10n.agentA11yAssistant) + Text(verbatim: text))
                            .accessibilityIdentifier("agent.message.agent")
                    case let .quote(text):
                        DSQuotedBlock(lines: [.init(L10n.agentQuoteLabel, text)])
                            .padding(.trailing, DSSpacing.xl)
                            .accessibilityIdentifier("agent.quote")
                    }
                }
            }
            if !reply.options.isEmpty { options }
            if !reply.sources.isEmpty { sources }
            if !tools.isEmpty {
                DSActionSummary(
                    title: L10n.agentSummaryTitle,
                    items: tools.map { .init(L10n.agentToolDone($0.name), ok: $0.ok) })
                    .accessibilityIdentifier("agent.summary")
            }
        }
    }

    private var options: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            ForEach(reply.options) { option in
                let label = VacationFormat.range(option.start, option.end, long: true)
                DSPickChip(Text(verbatim: label), isSelected: false) { model.choose(option, label: label) }
                    .disabled(model.isBusy)
                    .accessibilityHint(Text(L10n.agentOptionHint))
                    .accessibilityIdentifier("agent.option.\(option.proposalId)")
            }
        }
    }

    private var sources: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            ForEach(reply.sources) { source in
                DSSourceChip(title: source.title, hint: L10n.agentSourceHint) { config.openSource(source.announcementId) }
                    .accessibilityIdentifier("agent.source.\(source.announcementId)")
            }
        }
    }
}

/// The native confirm card. Only its buttons confirm (FR-AUTH-006); content comes from the stored proposal.
private struct AgentCardView: View {
    let card: AgentChatModel.Card
    let model: AgentChatModel
    let config: AgentChatConfig

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            switch card.state {
            case .loading:
                DSSkeleton(rows: 3).accessibilityIdentifier("agent.card.loading")
            default:
                if let content = card.card {
                    let shown = AgentCardPresenter.present(content.content)
                    DSConfirmCard(
                        state: dsState, title: shown.title, lines: shown.lines,
                        cancelTitle: L10n.cancel, confirmTitle: shown.confirmTitle,
                        stateMessage: stateMessage, footnote: footnote(shown, content),
                        onCancel: { model.cancel(proposalId: card.proposalId) },
                        onConfirm: { model.confirm(proposalId: card.proposalId) })
                    if case .success = card.state, let openRequests = config.openRequests {
                        DSButton(L10n.agentSuccessRequests, kind: .soft, action: openRequests)
                            .accessibilityIdentifier("agent.card.requests")
                    }
                    if case .failed = card.state {
                        DSButton(L10n.agentRetry, kind: .soft) { model.retry() }
                            .disabled(model.problem == nil)
                            .accessibilityIdentifier("agent.card.retry")
                    }
                } else {
                    DSBanner(.error, message: Text(L10n.agentCardUnavailable))
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("agent.card.\(card.proposalId)")
    }

    private var dsState: DSConfirmState {
        switch card.state {
        case .loading, .proposal: .proposal
        case .executing: .executing
        case .success: .success
        case .failed: .failed
        case .expired: .expired
        case .superseded, .cancelled: .superseded
        }
    }

    private var stateMessage: Text? {
        switch card.state {
        case .loading, .proposal, .executing: nil
        case let .success(text): Text(verbatim: text.isEmpty ? String(localized: L10n.agentCardSuccess) : text)
        case let .failed(text): Text(verbatim: text ?? String(localized: L10n.agentCardFailed))
        case .expired: Text(L10n.agentCardExpired)
        case .superseded: Text(L10n.agentCardSuperseded)
        case .cancelled: Text(L10n.agentCardCancelled)
        }
    }

    /// "Exactly this content will be published. Valid for 4:32": the countdown runs on the system clock.
    private func footnote(_ shown: AgentCardPresentation, _ content: AgentProposalCard) -> Text {
        Text(shown.footnote) + Text(" ") + Text(L10n.agentCardValid) + Text(" ")
            + Text(content.expiresAt, style: .timer)
    }
}
