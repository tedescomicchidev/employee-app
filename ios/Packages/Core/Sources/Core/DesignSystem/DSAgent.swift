import SwiftUI

public enum DSBubbleRole: Sendable {
    case user, agent
}

/// Chat bubble: radius 22 with a 6 pt tail corner. Content is user or agent text, shown verbatim.
public struct DSChatBubble: View {
    private let role: DSBubbleRole
    private let text: String
    private let spokenOverride: LocalizedStringResource?

    /// - Parameter spokenOverride: what VoiceOver reads instead of `text` while it is still changing
    ///   (A11Y-006: replies are read once they complete, never character by character).
    public init(_ role: DSBubbleRole, text: String, spokenOverride: LocalizedStringResource? = nil) {
        self.role = role
        self.text = text
        self.spokenOverride = spokenOverride
    }

    private var shape: UnevenRoundedRectangle {
        let r = DSRadius.bubble, t = DSRadius.bubbleTail
        return role == .user
            ? UnevenRoundedRectangle(topLeadingRadius: r, bottomLeadingRadius: r, bottomTrailingRadius: t, topTrailingRadius: r)
            : UnevenRoundedRectangle(topLeadingRadius: r, bottomLeadingRadius: t, bottomTrailingRadius: r, topTrailingRadius: r)
    }

    public var body: some View {
        HStack {
            if role == .user { Spacer(minLength: DSSpacing.xl) }
            Text(verbatim: text)
                .font(DSFont.body)
                .foregroundStyle(role == .user ? Color.white : DSColor.ink)
                .padding(.horizontal, DSSpacing.m)
                .padding(.vertical, DSSpacing.s)
                .background(role == .user ? DSColor.tint : DSColor.agentBubble, in: shape)
            if role == .agent { Spacer(minLength: DSSpacing.xl) }
        }
        .modifier(StreamingSpeech(spoken: spokenOverride))
    }
}

private struct StreamingSpeech: ViewModifier {
    let spoken: LocalizedStringResource?

    func body(content: Content) -> some View {
        if let spoken {
            content
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(spoken))
                .accessibilityAddTraits(.updatesFrequently)
        } else {
            content
        }
    }
}

/// Quoted data block: labelled values the agent read from api/ tools.
public struct DSQuotedBlock: View {
    public struct Line: Identifiable {
        public let id = UUID()
        public let label: LocalizedStringResource
        public let value: String

        public init(_ label: LocalizedStringResource, _ value: String) {
            self.label = label
            self.value = value
        }
    }

    private let lines: [Line]

    public init(lines: [Line]) { self.lines = lines }

    public var body: some View {
        HStack(spacing: DSSpacing.s) {
            RoundedRectangle(cornerRadius: 2).fill(DSColor.tint).frame(width: 3)
            VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                ForEach(lines) { line in
                    VStack(alignment: .leading, spacing: 0) {
                        Text(line.label).font(DSFont.caption).foregroundStyle(DSColor.ink2)
                        Text(verbatim: line.value).font(DSFont.body)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(DSSpacing.s)
        .background(DSColor.fill, in: RoundedRectangle(cornerRadius: DSRadius.chip + 4))
    }
}

public enum DSToolState: Sendable {
    case running, done, failed
}

public struct DSToolStatusLine: View {
    private let text: LocalizedStringResource
    private let state: DSToolState

    public init(_ text: LocalizedStringResource, state: DSToolState) {
        self.text = text
        self.state = state
    }

    public var body: some View {
        HStack(spacing: DSSpacing.xs) {
            switch state {
            case .running: ProgressView().controlSize(.small)
            case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(DSColor.green)
            case .failed: Image(systemName: "exclamationmark.circle.fill").foregroundStyle(DSColor.red)
            }
            Text(text).font(DSFont.caption).foregroundStyle(DSColor.ink2)
        }
        .frame(minHeight: DSSize.chipHeight)
        .accessibilityElement(children: .combine)
    }
}

public enum DSConfirmState: Sendable {
    /// `superseded`: the agent proposed something newer; this card can no longer be confirmed.
    case proposal, executing, success, failed, expired, superseded
}

/// Confirm card. Only the buttons confirm: typed text such as "ja" never does.
/// Cancel sits left, the wider primary sits right.
public struct DSConfirmCard: View {
    private let state: DSConfirmState
    private let title: LocalizedStringResource
    private let lines: [DSQuotedBlock.Line]
    private let cancelTitle: LocalizedStringResource
    private let confirmTitle: LocalizedStringResource
    private let stateMessage: Text?
    private let footnote: Text?
    private let onCancel: () -> Void
    private let onConfirm: () -> Void

    public init(
        state: DSConfirmState,
        title: LocalizedStringResource,
        lines: [DSQuotedBlock.Line],
        cancelTitle: LocalizedStringResource,
        confirmTitle: LocalizedStringResource,
        stateMessage: Text? = nil,
        footnote: Text? = nil,
        onCancel: @escaping () -> Void,
        onConfirm: @escaping () -> Void
    ) {
        self.state = state
        self.title = title
        self.lines = lines
        self.cancelTitle = cancelTitle
        self.confirmTitle = confirmTitle
        self.stateMessage = stateMessage
        self.footnote = footnote
        self.onCancel = onCancel
        self.onConfirm = onConfirm
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.s) {
            Text(title).font(DSFont.cardTitle).accessibilityAddTraits(.isHeader)
            DSQuotedBlock(lines: lines)
            if let stateMessage, state != .proposal {
                DSBanner(bannerKind, message: stateMessage)
            }
            if state == .proposal || state == .executing {
                HStack(spacing: DSSpacing.xs) {
                    Button { onCancel() } label: { Text(cancelTitle) }
                        .buttonStyle(DSButtonStyle(kind: .neutral))
                        .accessibilityIdentifier("confirmcard.cancel")
                        .frame(maxWidth: .infinity)
                        .layoutPriority(0)
                    DSButton(confirmTitle, isBusy: state == .executing, action: onConfirm)
                        .accessibilityIdentifier("confirmcard.confirm")
                        .layoutPriority(1)
                        .containerRelativeFrame(.horizontal) { width, _ in width * 0.5 }
                }
                .disabled(state == .executing)
            }
            if let footnote, state == .proposal {
                footnote.font(DSFont.caption).foregroundStyle(DSColor.ink2)
            }
        }
        .padding(DSSpacing.m)
        .background(DSColor.card, in: RoundedRectangle(cornerRadius: DSRadius.card))
        .shadow(color: .black.opacity(state == .superseded ? 0 : 0.07), radius: 14, y: 5)
        .opacity(state == .superseded || state == .expired ? 0.6 : 1)
    }

    private var bannerKind: DSBannerKind {
        switch state {
        case .success: .success
        case .failed: .error
        case .expired, .superseded: .info
        case .proposal, .executing: .info
        }
    }
}

/// Message composer: a capsule text field with send, which becomes stop while a turn is running.
/// A plain system text field, so keyboard dictation works and nothing else listens to the microphone.
public struct DSComposer: View {
    @Binding private var text: String
    private let placeholder: LocalizedStringResource
    private let sendLabel: LocalizedStringResource
    private let stopLabel: LocalizedStringResource
    private let isRunning: Bool
    private let isEnabled: Bool
    private let onSend: () -> Void
    private let onStop: () -> Void

    public init(
        text: Binding<String>,
        placeholder: LocalizedStringResource,
        sendLabel: LocalizedStringResource,
        stopLabel: LocalizedStringResource,
        isRunning: Bool,
        isEnabled: Bool = true,
        onSend: @escaping () -> Void,
        onStop: @escaping () -> Void
    ) {
        _text = text
        self.placeholder = placeholder
        self.sendLabel = sendLabel
        self.stopLabel = stopLabel
        self.isRunning = isRunning
        self.isEnabled = isEnabled
        self.onSend = onSend
        self.onStop = onStop
    }

    private var canSend: Bool { isEnabled && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    public var body: some View {
        HStack(alignment: .bottom, spacing: DSSpacing.xs) {
            TextField(text: $text, axis: .vertical) { Text(placeholder) }
                .font(DSFont.body)
                .lineLimit(1...5)
                .submitLabel(.send)
                .onSubmit { if canSend && !isRunning { onSend() } }
                .disabled(!isEnabled)
                .padding(.leading, DSSpacing.s)
                .padding(.vertical, DSSpacing.s)
                .accessibilityIdentifier("agent.composer")
            if isRunning {
                Button(action: onStop) {
                    Image(systemName: "stop.fill").font(DSFont.button).foregroundStyle(Color.white)
                        .frame(width: DSSize.touch, height: DSSize.touch)
                        .background(DSColor.ink, in: Circle())
                }
                .accessibilityLabel(Text(stopLabel))
                .accessibilityIdentifier("agent.stop")
            } else {
                Button(action: onSend) {
                    Image(systemName: "arrow.up").font(DSFont.button).foregroundStyle(Color.white)
                        .frame(width: DSSize.touch, height: DSSize.touch)
                        .background(canSend ? DSColor.tint : DSColor.placeholder, in: Circle())
                }
                .disabled(!canSend)
                .accessibilityLabel(Text(sendLabel))
                .accessibilityIdentifier("agent.send")
            }
        }
        .padding(.horizontal, DSSpacing.xxs)
        .frame(minHeight: DSSize.button)
        .background(DSColor.card, in: Capsule())
        .overlay(Capsule().strokeBorder(DSColor.sep, lineWidth: 0.5))
        .opacity(isEnabled ? 1 : 0.6)
    }
}

/// The agent is working: a spinner and one phrase ("Thinking", "Checking your balance"), in an agent bubble.
public struct DSThinkingBubble: View {
    private let text: LocalizedStringResource

    public init(_ text: LocalizedStringResource) { self.text = text }

    public var body: some View {
        HStack {
            HStack(spacing: DSSpacing.xs) {
                ProgressView().controlSize(.small)
                Text(text).font(DSFont.secondary).foregroundStyle(DSColor.ink2)
            }
            .padding(.horizontal, DSSpacing.m)
            .padding(.vertical, DSSpacing.s)
            .background(
                DSColor.agentBubble,
                in: UnevenRoundedRectangle(
                    topLeadingRadius: DSRadius.bubble, bottomLeadingRadius: DSRadius.bubbleTail,
                    bottomTrailingRadius: DSRadius.bubble, topTrailingRadius: DSRadius.bubble))
            Spacer(minLength: DSSpacing.xl)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }
}

/// A source announcement behind an answer; opens it in the classic detail screen.
public struct DSSourceChip: View {
    private let title: String
    private let hint: LocalizedStringResource
    private let action: () -> Void

    /// `title` is the announcement's own title, shown verbatim.
    public init(title: String, hint: LocalizedStringResource, action: @escaping () -> Void) {
        self.title = title
        self.hint = hint
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: DSSpacing.xs) {
                Image(systemName: "megaphone").font(DSFont.caption)
                Text(verbatim: title).font(DSFont.secondary).lineLimit(2).multilineTextAlignment(.leading)
            }
            .foregroundStyle(DSColor.tint)
            .padding(.horizontal, DSSpacing.s)
            .frame(minHeight: DSSize.touch)
            .background(DSColor.tintSoft, in: RoundedRectangle(cornerRadius: DSRadius.chip))
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text(hint))
    }
}

/// "What the assistant did": the tools that ran, one line each, collapsed by default.
public struct DSActionSummary: View {
    public struct Item: Identifiable, Sendable {
        public let id = UUID()
        public let text: LocalizedStringResource
        public let ok: Bool

        public init(_ text: LocalizedStringResource, ok: Bool) {
            self.text = text
            self.ok = ok
        }
    }

    private let title: LocalizedStringResource
    private let items: [Item]
    @State private var expanded = false

    public init(title: LocalizedStringResource, items: [Item]) {
        self.title = title
        self.items = items
    }

    public var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                ForEach(items) { item in
                    DSToolStatusLine(item.text, state: item.ok ? .done : .failed)
                }
            }
            .padding(.top, DSSpacing.xxs)
        } label: {
            Text(title).font(DSFont.caption).foregroundStyle(DSColor.ink2)
                .frame(minHeight: DSSize.touch, alignment: .leading)
        }
        .tint(DSColor.ink2)
    }
}

/// The assistant declines (a write without the card, a rule it cannot bend, a role limit).
public struct DSRefusalBubble: View {
    private let text: String

    public init(text: String) { self.text = text }

    public var body: some View {
        HStack(alignment: .top) {
            HStack(alignment: .top, spacing: DSSpacing.xs) {
                Image(systemName: "hand.raised.fill").foregroundStyle(DSColor.orange).accessibilityHidden(true)
                Text(verbatim: text).font(DSFont.body).foregroundStyle(DSColor.ink)
            }
            .padding(.horizontal, DSSpacing.m)
            .padding(.vertical, DSSpacing.s)
            .background(
                DSColor.orangeSoft,
                in: UnevenRoundedRectangle(
                    topLeadingRadius: DSRadius.bubble, bottomLeadingRadius: DSRadius.bubbleTail,
                    bottomTrailingRadius: DSRadius.bubble, topTrailingRadius: DSRadius.bubble))
            Spacer(minLength: DSSpacing.xl)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview("Agent components") {
    ScrollView {
        VStack(alignment: .leading, spacing: DSSpacing.s) {
            DSChatBubble(.user, text: "Ferien vom 24. Dez. bis 4. Jan.")
            DSChatBubble(.agent, text: "Ich habe 6 Arbeitstage berechnet.")
            DSToolStatusLine("Saldo geprüft", state: .done)
            DSToolStatusLine("Prüfe Team-Abdeckung", state: .running)
            DSConfirmCard(
                state: .proposal, title: "Ferien beantragen",
                lines: [.init("Zeitraum", "24.12.–04.01."), .init("Tage", "6")],
                cancelTitle: "Abbrechen", confirmTitle: "Beantragen", onCancel: {}, onConfirm: {})
            DSThinkingBubble("Prüfe Saldo …")
            DSRefusalBubble(text: "Das kann ich nicht ohne Bestätigung auf der Karte.")
            DSSourceChip(title: "Früher Start am Freitag", hint: "Öffnet die Mitteilung") {}
            DSActionSummary(title: "Das hat der Assistent getan", items: [.init("Saldo geprüft", ok: true)])
            DSComposer(
                text: .constant(""), placeholder: "Nachricht", sendLabel: "Senden", stopLabel: "Stopp",
                isRunning: false, onSend: {}, onStop: {})
            DSConfirmCard(
                state: .superseded, title: "Ferien beantragen", lines: [.init("Tage", "6")],
                cancelTitle: "Abbrechen", confirmTitle: "Beantragen",
                stateMessage: Text("Ersetzt durch einen neuen Vorschlag."), onCancel: {}, onConfirm: {})
            DSConfirmCard(
                state: .expired, title: "Ferien beantragen", lines: [.init("Tage", "6")],
                cancelTitle: "Abbrechen", confirmTitle: "Beantragen",
                stateMessage: Text("Die Bestätigung ist abgelaufen."), onCancel: {}, onConfirm: {})
        }
        .padding(DSSpacing.gutter)
    }
    .background(DSColor.bg)
}
