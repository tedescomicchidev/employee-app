import SwiftUI

public enum DSButtonKind: Sendable {
    case primary, soft, neutral, destructive
}

public struct DSButtonStyle: ButtonStyle {
    private let kind: DSButtonKind
    private let isBusy: Bool
    @Environment(\.isEnabled) private var isEnabled

    public init(kind: DSButtonKind = .primary, isBusy: Bool = false) {
        self.kind = kind
        self.isBusy = isBusy
    }

    public func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: DSSpacing.xs) {
            if isBusy { ProgressView().tint(foreground) }
            configuration.label
        }
        .font(DSFont.button)
        .foregroundStyle(foreground)
        .frame(maxWidth: .infinity, minHeight: DSSize.button)
        .padding(.horizontal, DSSpacing.m)
        .background(background, in: Capsule())
        .contentShape(Capsule())
        .opacity(configuration.isPressed ? 0.8 : 1)
    }

    private var active: Bool { isEnabled && !isBusy }

    private var foreground: Color {
        guard isEnabled else { return DSColor.placeholder }
        switch kind {
        case .primary: return .white
        case .soft: return DSColor.tint
        case .neutral: return DSColor.ink
        case .destructive: return DSColor.red
        }
    }

    private var background: Color {
        guard isEnabled else { return DSColor.fill }
        switch kind {
        case .primary: return active ? DSColor.tint : DSColor.tint.opacity(0.6)
        case .soft: return DSColor.tintSoft
        case .neutral: return DSColor.fill
        case .destructive: return DSColor.redSoft
        }
    }
}

/// Capsule button. `isBusy` disables the button and shows a spinner.
public struct DSButton: View {
    private let title: LocalizedStringResource
    private let kind: DSButtonKind
    private let isBusy: Bool
    private let action: () -> Void

    public init(
        _ title: LocalizedStringResource,
        kind: DSButtonKind = .primary,
        isBusy: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.kind = kind
        self.isBusy = isBusy
        self.action = action
    }

    public var body: some View {
        Button(action: action) { Text(title) }
            .buttonStyle(DSButtonStyle(kind: kind, isBusy: isBusy))
            .disabled(isBusy)
            .accessibilityValue(isBusy ? Text(DSStrings.loading) : Text(verbatim: ""))
    }
}

#Preview("Buttons") {
    VStack(spacing: DSSpacing.s) {
        DSButton("Primary", action: {})
        DSButton("Soft", kind: .soft, action: {})
        DSButton("Neutral", kind: .neutral, action: {})
        DSButton("Destructive", kind: .destructive, action: {})
        DSButton("Busy", isBusy: true, action: {})
        DSButton("Disabled", action: {}).disabled(true)
    }
    .padding(DSSpacing.gutter)
    .background(DSColor.bg)
}

#Preview("Buttons dark") {
    VStack(spacing: DSSpacing.s) {
        DSButton("Primary", action: {})
        DSButton("Soft", kind: .soft, action: {})
        DSButton("Destructive", kind: .destructive, action: {})
    }
    .padding(DSSpacing.gutter)
    .background(DSColor.bg)
    .preferredColorScheme(.dark)
}
