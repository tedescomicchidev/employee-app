import Core
import SwiftUI

/// "Mehr" > weekly briefing (FR-BRF-001.4): the toggle, and the Monday reminder's state (FR-BRF-003).
struct BriefingSettingsSection: View {
    let model: BriefingSettingsModel
    @Environment(\.openURL) private var openURL

    var body: some View {
        DSGroupedSection(header: L10n.brfSettingsHeader) {
            DSToggleRow(
                title: Text(L10n.brfSettingsToggle), subtitle: subtitle,
                isOn: Binding(get: { model.optedIn ?? false }, set: { model.request($0) }))
                .disabled(model.optedIn == nil || model.isWorking)
                .accessibilityIdentifier("briefing.settings.toggle")
            if model.optedIn == true {
                DSRowDivider()
                DSListRow(
                    title: Text(L10n.brfSettingsReminder),
                    subtitle: model.reminder == .denied ? Text(L10n.brfSettingsReminderDenied) : nil,
                    trailing: Text(model.reminder == .scheduled ? L10n.brfSettingsReminderOn : L10n.brfSettingsReminderOff))
                    .accessibilityIdentifier("briefing.settings.reminder")
                if model.reminder == .denied {
                    Button {
                        if let url = URL(string: iosSettingsURL) { openURL(url) }
                    } label: {
                        Text(L10n.brfSettingsOpensettings).font(DSFont.body)
                            .frame(maxWidth: .infinity, minHeight: DSSize.touch, alignment: .leading)
                            .padding(.horizontal, DSSpacing.m)
                    }
                    .accessibilityIdentifier("briefing.settings.opensettings")
                }
            }
        }
        .alert(title, isPresented: Binding(get: { model.pending != nil }, set: { if !$0 { model.cancelPending() } })) {
            Button(role: .cancel) { model.cancelPending() } label: { Text(L10n.cancel) }
            Button { model.confirm() } label: { Text(confirmTitle) }
        } message: {
            Text(message)
        }
    }

    private var iosSettingsURL: String { "app-settings:" }

    private var subtitle: Text {
        if model.failedCode != nil { return Text(L10n.brfSettingsFailed) }
        if case let .unavailable(offline) = model.state, offline { return Text(L10n.brfSettingsOffline) }
        return Text(L10n.brfSettingsToggleHint)
    }

    private var turningOn: Bool { model.pending ?? true }
    private var title: Text { Text(turningOn ? L10n.brfAlertOnTitle : L10n.brfAlertOffTitle) }
    private var message: LocalizedStringResource { turningOn ? L10n.brfAlertOnMessage : L10n.brfAlertOffMessage }
    private var confirmTitle: LocalizedStringResource { turningOn ? L10n.brfAlertOnConfirm : L10n.brfAlertOffConfirm }
}
