import SwiftUI

/// Semantic colours from docs/design/tokens.md. Values live in Colors.xcassets
/// (light, dark, increased contrast). Never use hex literals in views.
public enum DSColor {
    public static let bg = Color("bg", bundle: .module)
    public static let card = Color("card", bundle: .module)
    public static let ink = Color("ink", bundle: .module)
    public static let ink2 = Color("ink2", bundle: .module)
    public static let sep = Color("sep", bundle: .module)
    public static let fill = Color("fill", bundle: .module)
    public static let tint = Color("tint", bundle: .module)
    public static let tintSoft = Color("tintS", bundle: .module)
    public static let red = Color("red", bundle: .module)
    public static let redSoft = Color("redS", bundle: .module)
    public static let green = Color("grn", bundle: .module)
    public static let greenSoft = Color("grnS", bundle: .module)
    public static let orange = Color("org", bundle: .module)
    public static let orangeSoft = Color("orgS", bundle: .module)
    public static let agentBubble = Color("agentBubble", bundle: .module)
    public static let placeholder = Color("placeholder", bundle: .module)

    /// Names of every colour set, used by tests to prove the asset catalog is complete.
    public static let allNames = [
        "bg", "card", "ink", "ink2", "sep", "fill", "tint", "tintS", "red", "redS",
        "grn", "grnS", "org", "orgS", "agentBubble", "placeholder",
    ]
}

/// Text styles mapped to Dynamic Type (tokens.md "Typography").
public enum DSFont {
    public static let largeTitle = Font.largeTitle.weight(.bold)
    public static let title = Font.title.weight(.bold)
    public static let sheetTitle = Font.title2.weight(.semibold)
    public static let cardTitle = Font.title3.weight(.semibold)
    public static let body = Font.body
    public static let button = Font.headline
    public static let secondary = Font.subheadline
    public static let caption = Font.footnote
    public static let sectionHeader = Font.footnote.weight(.semibold)
    public static let tabLabel = Font.caption2.weight(.medium)
    public static let code = Font.caption.monospaced().weight(.medium)
}

/// Hero number (64 pt in the mockups) that scales with Dynamic Type.
public struct DSHeroNumberStyle: ViewModifier {
    @ScaledMetric(relativeTo: .largeTitle) private var size: CGFloat = 64

    public func body(content: Content) -> some View {
        content
            .font(.system(size: size, weight: .bold))
            .monospacedDigit()
            .minimumScaleFactor(0.5)
            .lineLimit(1)
    }
}

public extension View {
    func dsHeroNumber() -> some View { modifier(DSHeroNumberStyle()) }
}

public enum DSSpacing {
    public static let xxs: CGFloat = 4
    public static let xs: CGFloat = 8
    public static let s: CGFloat = 12
    public static let m: CGFloat = 16
    public static let l: CGFloat = 24
    public static let xl: CGFloat = 32
    /// Content gutter.
    public static let gutter: CGFloat = 16
    public static let sectionHeaderInset = EdgeInsets(top: 18, leading: 36, bottom: 7, trailing: 16)
}

public enum DSRadius {
    public static let card: CGFloat = 26
    public static let hero: CGFloat = 30
    public static let sheet: CGFloat = 40
    public static let alert: CGFloat = 34
    public static let bubble: CGFloat = 22
    public static let bubbleTail: CGFloat = 6
    public static let chip: CGFloat = 12
}

public enum DSSize {
    /// Minimum touch target (HIG).
    public static let touch: CGFloat = 44
    public static let button: CGFloat = 50
    public static let cardButton: CGFloat = 48
    public static let rowMin: CGFloat = 56
    public static let rowDense: CGFloat = 50
    public static let chipHeight: CGFloat = 24
    public static let emptyIconDisc: CGFloat = 76
    public static let avatar: CGFloat = 40
    public static let iconBadge: CGFloat = 32
    public static let unreadDot: CGFloat = 10
}
