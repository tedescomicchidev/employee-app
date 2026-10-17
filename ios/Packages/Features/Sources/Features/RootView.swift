import SwiftUI

/// Placeholder root. Real screens follow docs/design/ and the screen-state matrix.
public struct RootView: View {
    public init() {}

    public var body: some View {
        Text("root.title", bundle: .main)
            .font(.title)
            .accessibilityIdentifier("root.title")
    }
}
