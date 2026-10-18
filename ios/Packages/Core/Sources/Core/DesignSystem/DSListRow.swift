import SwiftUI

/// Card container for grouped rows (radius 26). Put `DSRowDivider()` between rows.
public struct DSGroupedSection<Content: View>: View {
    private let header: LocalizedStringResource?
    private let content: Content

    public init(header: LocalizedStringResource? = nil, @ViewBuilder content: () -> Content) {
        self.header = header
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let header {
                Text(header)
                    .font(DSFont.sectionHeader)
                    .foregroundStyle(DSColor.ink2)
                    .padding(DSSpacing.sectionHeaderInset)
                    .accessibilityAddTraits(.isHeader)
            }
            VStack(spacing: 0) { content }
                .background(DSColor.card, in: RoundedRectangle(cornerRadius: DSRadius.card))
                .clipShape(RoundedRectangle(cornerRadius: DSRadius.card))
        }
    }
}

public struct DSRowDivider: View {
    public init() {}
    public var body: some View {
        Rectangle().fill(DSColor.sep).frame(height: 1 / 3).padding(.leading, DSSpacing.m)
    }
}

public enum DSRowLeading {
    case none
    case icon(systemName: String, tint: Color)
    case avatar(initials: String)
}

/// Grouped list row: title, subtitle, trailing value, chevron, unread dot, avatar or icon badge.
public struct DSListRow: View {
    private let title: Text
    private let subtitle: Text?
    private let trailing: Text?
    private let leading: DSRowLeading
    private let showsChevron: Bool
    private let isUnread: Bool

    public init(
        title: Text,
        subtitle: Text? = nil,
        trailing: Text? = nil,
        leading: DSRowLeading = .none,
        showsChevron: Bool = false,
        isUnread: Bool = false
    ) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
        self.leading = leading
        self.showsChevron = showsChevron
        self.isUnread = isUnread
    }

    public var body: some View {
        HStack(spacing: DSSpacing.s) {
            if isUnread {
                Circle().fill(DSColor.tint).frame(width: DSSize.unreadDot, height: DSSize.unreadDot)
                    .accessibilityHidden(true)
            }
            leadingView
            VStack(alignment: .leading, spacing: 2) {
                title.font(DSFont.body).foregroundStyle(DSColor.ink)
                if let subtitle { subtitle.font(DSFont.secondary).foregroundStyle(DSColor.ink2) }
            }
            Spacer(minLength: DSSpacing.xs)
            if let trailing { trailing.font(DSFont.body).foregroundStyle(DSColor.ink2).monospacedDigit() }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(DSFont.caption.weight(.semibold))
                    .foregroundStyle(DSColor.placeholder)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, DSSpacing.m)
        .padding(.vertical, DSSpacing.xs)
        .frame(minHeight: DSSize.rowMin)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var leadingView: some View {
        switch leading {
        case .none:
            EmptyView()
        case let .icon(name, tint):
            Image(systemName: name)
                .foregroundStyle(.white)
                .frame(width: DSSize.iconBadge, height: DSSize.iconBadge)
                .background(tint, in: RoundedRectangle(cornerRadius: DSRadius.chip))
                .accessibilityHidden(true)
        case let .avatar(initials):
            Text(verbatim: initials)
                .font(DSFont.secondary.weight(.semibold))
                .foregroundStyle(DSColor.tint)
                .frame(width: DSSize.avatar, height: DSSize.avatar)
                .background(DSColor.tintSoft, in: Circle())
                .accessibilityHidden(true)
        }
    }
}

#Preview("List rows") {
    ScrollView {
        DSGroupedSection(header: "Aktuell") {
            DSListRow(title: Text("Früher Start am Freitag"), subtitle: Text("Region Tessin"),
                      trailing: Text("09:00"), showsChevron: true, isUnread: true)
            DSRowDivider()
            DSListRow(title: Text("Ferien"), leading: .icon(systemName: "sun.max", tint: DSColor.orange),
                      showsChevron: true)
            DSRowDivider()
            DSListRow(title: Text("Anna Muster"), subtitle: Text("Manager"), leading: .avatar(initials: "AM"))
        }
        .padding(DSSpacing.gutter)
    }
    .background(DSColor.bg)
}

#Preview("List rows AX5") {
    DSGroupedSection {
        DSListRow(title: Text("Früher Start am Freitag"), subtitle: Text("Region Tessin"), showsChevron: true)
    }
    .padding(DSSpacing.gutter)
    .background(DSColor.bg)
    .dynamicTypeSize(.accessibility5)
}
