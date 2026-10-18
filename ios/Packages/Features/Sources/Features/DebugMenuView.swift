#if DEBUG
import Core
import SwiftUI

/// Debug menu: switch CLASSIC/AGENT mode and seed auth scenarios. Compiled out of Release (EXP-004).
/// English only on purpose: an internal tool, not user-facing copy.
struct DebugMenuView: View {
    let model: AppModel
    let environment: AppEnvironment
    @State private var mode: AppMode

    init(model: AppModel, environment: AppEnvironment) {
        self.model = model
        self.environment = environment
        _mode = State(initialValue: environment.mode.current)
    }

    var body: some View {
        DSGroupedSection {
            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                Text(verbatim: "Debug").font(DSFont.sectionHeader).foregroundStyle(DSColor.ink2)
                Picker(selection: $mode) {
                    Text(verbatim: "CLASSIC").tag(AppMode.classic)
                    Text(verbatim: "AGENT").tag(AppMode.agent)
                } label: { Text(verbatim: "Mode") }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("debug.mode")
                .onChange(of: mode) { _, new in environment.mode.setForDebug(new) }
            }
            .padding(DSSpacing.m)
            if let hooks = environment.debug {
                DSRowDivider()
                VStack(alignment: .leading, spacing: DSSpacing.xs) {
                    Text(verbatim: "Seed scenarios").font(DSFont.caption).foregroundStyle(DSColor.ink2)
                    HStack {
                        ForEach([StubScenario.employee, .manager, .publisher], id: \.self) { scenario in
                            DSPickChip(Text(verbatim: scenario.rawValue), isSelected: false) {
                                Task {
                                    await hooks.useScenario(scenario)
                                    await model.reload()
                                }
                            }
                            .accessibilityIdentifier("debug.seed.\(scenario.rawValue)")
                        }
                    }
                    DSButton("Simulate expired session", kind: .soft) {
                        Task {
                            await hooks.expireSession()
                            await model.reload()
                        }
                    }
                    .accessibilityIdentifier("debug.expire")
                }
                .padding(DSSpacing.m)
            }
        }
    }
}
#endif
