import SwiftUI

/// Pick chip: 44 pt capsule toggle used for single or multi pick lists.
public struct DSPickChip: View {
    private let title: Text
    private let isSelected: Bool
    private let action: () -> Void

    public init(_ title: Text, isSelected: Bool, action: @escaping () -> Void) {
        self.title = title
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: DSSpacing.xxs) {
                if isSelected { Image(systemName: "checkmark").imageScale(.small).accessibilityHidden(true) }
                title
            }
            .font(DSFont.secondary.weight(.medium))
            .foregroundStyle(isSelected ? DSColor.tint : DSColor.ink)
            .padding(.horizontal, DSSpacing.m)
            .frame(minHeight: DSSize.touch)
            .background(isSelected ? DSColor.tintSoft : DSColor.fill, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// 44 pt segmented control. Wraps the system `Picker` so HIG behaviour wins.
public struct DSSegmentedControl<Value: Hashable & Sendable>: View {
    public struct Option: Identifiable {
        public let value: Value
        public let title: LocalizedStringResource
        public var id: Value { value }

        public init(_ value: Value, _ title: LocalizedStringResource) {
            self.value = value
            self.title = title
        }
    }

    private let options: [Option]
    @Binding private var selection: Value

    public init(_ options: [Option], selection: Binding<Value>) {
        self.options = options
        self._selection = selection
    }

    public var body: some View {
        Picker("", selection: $selection) {
            ForEach(options) { option in Text(option.title).tag(option.value) }
        }
        .pickerStyle(.segmented)
        .frame(minHeight: DSSize.touch)
    }
}

#Preview("Choice") {
    struct Demo: View {
        @State private var mode = 0
        var body: some View {
            VStack(alignment: .leading, spacing: DSSpacing.m) {
                HStack {
                    DSPickChip(Text("Tessin"), isSelected: true, action: {})
                    DSPickChip(Text("Zürich"), isSelected: false, action: {})
                }
                DSSegmentedControl([.init(0, "Classic"), .init(1, "Agent")], selection: $mode)
            }
            .padding(DSSpacing.gutter)
            .background(DSColor.bg)
        }
    }
    return Demo()
}
