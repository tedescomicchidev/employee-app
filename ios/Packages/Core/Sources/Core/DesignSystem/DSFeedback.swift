import SwiftUI

public enum DSBannerKind: Sendable {
    case offline, error, info, success

    var symbol: String {
        switch self {
        case .offline: "wifi.slash"
        case .error: "exclamationmark.triangle.fill"
        case .info: "info.circle.fill"
        case .success: "checkmark.circle.fill"
        }
    }

    var foreground: Color {
        switch self {
        case .offline: DSColor.orange
        case .error: DSColor.red
        case .info: DSColor.tint
        case .success: DSColor.green
        }
    }

    var background: Color {
        switch self {
        case .offline: DSColor.orangeSoft
        case .error: DSColor.redSoft
        case .info: DSColor.tintSoft
        case .success: DSColor.greenSoft
        }
    }
}

public struct DSBanner: View {
    private let kind: DSBannerKind
    private let message: Text
    private let actionTitle: LocalizedStringResource?
    private let action: (() -> Void)?

    public init(
        _ kind: DSBannerKind,
        message: Text,
        actionTitle: LocalizedStringResource? = nil,
        action: (() -> Void)? = nil
    ) {
        self.kind = kind
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        HStack(alignment: .top, spacing: DSSpacing.s) {
            Image(systemName: kind.symbol).foregroundStyle(kind.foreground).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                message.font(DSFont.secondary).foregroundStyle(DSColor.ink)
                if let actionTitle, let action {
                    Button(action: action) { Text(actionTitle).font(DSFont.secondary.weight(.semibold)) }
                        .foregroundStyle(kind.foreground)
                        .frame(minHeight: DSSize.touch, alignment: .leading)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(DSSpacing.s)
        .background(kind.background, in: RoundedRectangle(cornerRadius: DSRadius.chip + 4))
        .accessibilityElement(children: .combine)
    }
}

/// Skeleton placeholder. Announces "Loading" and pauses shimmer for Reduce Motion.
public struct DSSkeleton: View {
    private let rows: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dim = false

    public init(rows: Int = 3) { self.rows = rows }

    public var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<rows, id: \.self) { index in
                HStack(spacing: DSSpacing.s) {
                    Circle().fill(DSColor.fill).frame(width: DSSize.avatar, height: DSSize.avatar)
                    VStack(alignment: .leading, spacing: DSSpacing.xs) {
                        RoundedRectangle(cornerRadius: 4).fill(DSColor.fill).frame(height: 14)
                        RoundedRectangle(cornerRadius: 4).fill(DSColor.fill).frame(width: 120, height: 12)
                    }
                }
                .padding(DSSpacing.m)
                .frame(minHeight: DSSize.rowMin)
                if index < rows - 1 { DSRowDivider() }
            }
        }
        .background(DSColor.card, in: RoundedRectangle(cornerRadius: DSRadius.card))
        .opacity(dim ? 0.55 : 1)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { dim = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(DSStrings.loading))
    }
}

public struct DSEmptyState: View {
    private let symbol: String
    private let title: LocalizedStringResource
    private let message: LocalizedStringResource?
    private let actionTitle: LocalizedStringResource?
    private let action: (() -> Void)?

    public init(
        symbol: String,
        title: LocalizedStringResource,
        message: LocalizedStringResource? = nil,
        actionTitle: LocalizedStringResource? = nil,
        action: (() -> Void)? = nil
    ) {
        self.symbol = symbol
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        VStack(spacing: DSSpacing.m) {
            Image(systemName: symbol)
                .font(.largeTitle)
                .foregroundStyle(DSColor.tint)
                .frame(width: DSSize.emptyIconDisc, height: DSSize.emptyIconDisc)
                .background(DSColor.tintSoft, in: Circle())
                .accessibilityHidden(true)
            Text(title).font(DSFont.sheetTitle).multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            if let message {
                Text(message).font(DSFont.body).foregroundStyle(DSColor.ink2).multilineTextAlignment(.center)
            }
            if let actionTitle, let action {
                DSButton(actionTitle, kind: .soft, action: action).padding(.top, DSSpacing.xs)
            }
        }
        .padding(DSSpacing.l)
        .frame(maxWidth: .infinity)
    }
}

/// Plain cause and retry; the correlation id and code sit behind "Details".
public struct DSErrorState: View {
    private let title: LocalizedStringResource
    private let message: LocalizedStringResource
    private let retryTitle: LocalizedStringResource
    private let retry: () -> Void
    private let correlationId: String?
    private let code: String?

    public init(
        title: LocalizedStringResource,
        message: LocalizedStringResource,
        retryTitle: LocalizedStringResource,
        correlationId: String? = nil,
        code: String? = nil,
        retry: @escaping () -> Void
    ) {
        self.title = title
        self.message = message
        self.retryTitle = retryTitle
        self.correlationId = correlationId
        self.code = code
        self.retry = retry
    }

    public var body: some View {
        VStack(spacing: DSSpacing.m) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundStyle(DSColor.red)
                .frame(width: DSSize.emptyIconDisc, height: DSSize.emptyIconDisc)
                .background(DSColor.redSoft, in: Circle())
                .accessibilityHidden(true)
            Text(title).font(DSFont.sheetTitle).multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text(message).font(DSFont.body).foregroundStyle(DSColor.ink2).multilineTextAlignment(.center)
            DSButton(retryTitle, action: retry)
            if correlationId != nil || code != nil {
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                        if let correlationId {
                            Text("\(Text(DSStrings.correlationId)): \(correlationId)").font(DSFont.code)
                        }
                        if let code { Text("\(Text(DSStrings.code)): \(code)").font(DSFont.code) }
                    }
                    .foregroundStyle(DSColor.ink2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                } label: {
                    Text(DSStrings.details).font(DSFont.secondary)
                }
            }
        }
        .padding(DSSpacing.l)
        .frame(maxWidth: .infinity)
    }
}

public struct DSToggleRow: View {
    private let title: Text
    private let subtitle: Text?
    @Binding private var isOn: Bool

    public init(title: Text, subtitle: Text? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.subtitle = subtitle
        self._isOn = isOn
    }

    public var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                title.font(DSFont.body)
                if let subtitle { subtitle.font(DSFont.secondary).foregroundStyle(DSColor.ink2) }
            }
        }
        .tint(DSColor.green)
        .padding(.horizontal, DSSpacing.m)
        .padding(.vertical, DSSpacing.xs)
        .frame(minHeight: DSSize.rowMin)
    }
}

#Preview("Feedback") {
    ScrollView {
        VStack(spacing: DSSpacing.m) {
            DSBanner(.offline, message: Text("Offline. Stand: 09:12"))
            DSBanner(.error, message: Text("Etwas ist schiefgelaufen"), actionTitle: "Erneut versuchen", action: {})
            DSBanner(.info, message: Text("Hinweis"))
            DSBanner(.success, message: Text("Gespeichert"))
            DSSkeleton()
            DSEmptyState(symbol: "tray", title: "Keine Einträge", message: "Hier ist noch nichts.",
                         actionTitle: "Aktualisieren", action: {})
            DSErrorState(title: "Fehler", message: "Bitte erneut versuchen.", retryTitle: "Erneut versuchen",
                         correlationId: "c0ffee-1234", code: "UPSTREAM_ERROR", retry: {})
        }
        .padding(DSSpacing.gutter)
    }
    .background(DSColor.bg)
}

#Preview("Feedback dark") {
    VStack(spacing: DSSpacing.m) {
        DSBanner(.offline, message: Text("Offline"))
        DSBanner(.error, message: Text("Fehler"))
        DSToggleRow(title: Text("Benachrichtigungen"), subtitle: Text("Täglich"), isOn: .constant(true))
    }
    .padding(DSSpacing.gutter)
    .background(DSColor.bg)
    .preferredColorScheme(.dark)
}
