import SwiftUI

public enum DSStatusKind: Sendable {
    case pending, approved, rejected, info, neutral

    var symbol: String {
        switch self {
        case .pending: "clock"
        case .approved: "checkmark.circle.fill"
        case .rejected: "xmark.circle.fill"
        case .info: "info.circle"
        case .neutral: "circle"
        }
    }

    var foreground: Color {
        switch self {
        case .pending: DSColor.orange
        case .approved: DSColor.green
        case .rejected: DSColor.red
        case .info: DSColor.tint
        case .neutral: DSColor.ink2
        }
    }

    var background: Color {
        switch self {
        case .pending: DSColor.orangeSoft
        case .approved: DSColor.greenSoft
        case .rejected: DSColor.redSoft
        case .info: DSColor.tintSoft
        case .neutral: DSColor.fill
        }
    }
}

/// Status is never colour alone (A11Y-003): every chip has an icon and a text label.
public struct DSStatusChip: View {
    private let kind: DSStatusKind
    private let label: Text
    private let symbol: String

    public init(_ kind: DSStatusKind, label: Text, symbol: String? = nil) {
        self.kind = kind
        self.label = label
        self.symbol = symbol ?? kind.symbol
    }

    public var body: some View {
        HStack(spacing: DSSpacing.xxs) {
            Image(systemName: symbol).imageScale(.small).accessibilityHidden(true)
            label
        }
        .font(DSFont.caption.weight(.semibold))
        .foregroundStyle(kind.foreground)
        .padding(.horizontal, DSSpacing.xs)
        .frame(minHeight: DSSize.chipHeight)
        .background(kind.background, in: RoundedRectangle(cornerRadius: DSRadius.chip))
        .accessibilityElement(children: .combine)
    }
}

#Preview("Status chips") {
    VStack(alignment: .leading, spacing: DSSpacing.xs) {
        DSStatusChip(.pending, label: Text("Pending"))
        DSStatusChip(.approved, label: Text("Approved"))
        DSStatusChip(.rejected, label: Text("Rejected"))
        DSStatusChip(.info, label: Text("DE"), symbol: "globe")
        DSStatusChip(.neutral, label: Text("3"))
    }
    .padding(DSSpacing.gutter)
    .background(DSColor.bg)
}
