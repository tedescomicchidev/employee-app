import SwiftUI

/// Alert/sheet card (radius 34) for custom in-content dialogs and previews.
/// Real dialogs use the system `.alert` / `.confirmationDialog` / `.sheet` (HIG wins).
public struct DSAlertCard: View {
    private let title: LocalizedStringResource
    private let message: LocalizedStringResource?
    private let primaryTitle: LocalizedStringResource
    private let secondaryTitle: LocalizedStringResource?
    private let isDestructive: Bool
    private let onPrimary: () -> Void
    private let onSecondary: (() -> Void)?

    public init(
        title: LocalizedStringResource,
        message: LocalizedStringResource? = nil,
        primaryTitle: LocalizedStringResource,
        secondaryTitle: LocalizedStringResource? = nil,
        isDestructive: Bool = false,
        onPrimary: @escaping () -> Void,
        onSecondary: (() -> Void)? = nil
    ) {
        self.title = title
        self.message = message
        self.primaryTitle = primaryTitle
        self.secondaryTitle = secondaryTitle
        self.isDestructive = isDestructive
        self.onPrimary = onPrimary
        self.onSecondary = onSecondary
    }

    public var body: some View {
        VStack(spacing: DSSpacing.s) {
            Text(title).font(DSFont.sheetTitle).multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            if let message {
                Text(message).font(DSFont.body).foregroundStyle(DSColor.ink2).multilineTextAlignment(.center)
            }
            HStack(spacing: DSSpacing.xs) {
                if let secondaryTitle, let onSecondary {
                    DSButton(secondaryTitle, kind: .neutral, action: onSecondary)
                }
                DSButton(primaryTitle, kind: isDestructive ? .destructive : .primary, action: onPrimary)
            }
        }
        .padding(DSSpacing.l)
        .background(DSColor.card, in: RoundedRectangle(cornerRadius: DSRadius.alert))
        .padding(DSSpacing.gutter)
    }
}

#Preview("Alert") {
    DSAlertCard(title: "Abmelden?", message: "Lokale Daten werden gelöscht.", primaryTitle: "Abmelden",
                secondaryTitle: "Abbrechen", isDestructive: true, onPrimary: {}, onSecondary: {})
        .background(DSColor.bg)
}
