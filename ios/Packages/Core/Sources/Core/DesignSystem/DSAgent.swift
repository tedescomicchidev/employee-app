import SwiftUI

public enum DSBubbleRole: Sendable {
    case user, agent
}

/// Chat bubble: radius 22 with a 6 pt tail corner. Content is user or agent text, shown verbatim.
public struct DSChatBubble: View {
    private let role: DSBubbleRole
    private let text: String

    public init(_ role: DSBubbleRole, text: String) {
        self.role = role
        self.text = text
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
    case proposal, executing, success, failed, expired
}

/// Confirm card. Only the buttons confirm: typed text such as "ja" never does.
/// Cancel sits left, the wider primary sits right.
public struct DSConfirmCard: View {
    private let state: DSConfirmState
    private let title: LocalizedStringResource
    private let lines: [DSQuotedBlock.Line]
    private let cancelTitle: LocalizedStringResource
    private let confirmTitle: LocalizedStringResource
    private let stateMessage: LocalizedStringResource?
    private let onCancel: () -> Void
    private let onConfirm: () -> Void

    public init(
        state: DSConfirmState,
        title: LocalizedStringResource,
        lines: [DSQuotedBlock.Line],
        cancelTitle: LocalizedStringResource,
        confirmTitle: LocalizedStringResource,
        stateMessage: LocalizedStringResource? = nil,
        onCancel: @escaping () -> Void,
        onConfirm: @escaping () -> Void
    ) {
        self.state = state
        self.title = title
        self.lines = lines
        self.cancelTitle = cancelTitle
        self.confirmTitle = confirmTitle
        self.stateMessage = stateMessage
        self.onCancel = onCancel
        self.onConfirm = onConfirm
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.s) {
            Text(title).font(DSFont.cardTitle).accessibilityAddTraits(.isHeader)
            DSQuotedBlock(lines: lines)
            if let stateMessage, state != .proposal {
                DSBanner(bannerKind, message: Text(stateMessage))
            }
            if state == .proposal || state == .executing {
                HStack(spacing: DSSpacing.xs) {
                    Button { onCancel() } label: { Text(cancelTitle) }
                        .buttonStyle(DSButtonStyle(kind: .neutral))
                        .frame(maxWidth: .infinity)
                        .layoutPriority(0)
                    DSButton(confirmTitle, isBusy: state == .executing, action: onConfirm)
                        .layoutPriority(1)
                        .containerRelativeFrame(.horizontal) { width, _ in width * 0.5 }
                }
                .disabled(state == .executing)
            }
        }
        .padding(DSSpacing.m)
        .background(DSColor.card, in: RoundedRectangle(cornerRadius: DSRadius.card))
        .shadow(color: .black.opacity(0.07), radius: 14, y: 5)
    }

    private var bannerKind: DSBannerKind {
        switch state {
        case .success: .success
        case .failed: .error
        case .expired: .info
        case .proposal, .executing: .info
        }
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
            DSConfirmCard(
                state: .expired, title: "Ferien beantragen", lines: [.init("Tage", "6")],
                cancelTitle: "Abbrechen", confirmTitle: "Beantragen",
                stateMessage: "Die Bestätigung ist abgelaufen.", onCancel: {}, onConfirm: {})
        }
        .padding(DSSpacing.gutter)
    }
    .background(DSColor.bg)
}
