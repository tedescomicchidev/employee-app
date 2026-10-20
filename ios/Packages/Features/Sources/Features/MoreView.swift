import Core
import SwiftUI

/// "Mehr": account, sign-out with confirmation, and (DEBUG only) the debug menu.
struct MoreView: View {
    let model: AppModel
    let environment: AppEnvironment
    @State private var confirmSignOut = false
    @State private var briefing: BriefingSettingsModel?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DSSpacing.m) {
                    if let session = model.session {
                        DSGroupedSection(header: L10n.moreAccount) {
                            DSListRow(
                                title: Text(verbatim: session.displayName),
                                subtitle: Text(L10n.role(session.primaryRole)),
                                leading: .avatar(initials: Self.initials(session.displayName)))
                        }
                    }
                    if let briefing { BriefingSettingsSection(model: briefing) }
                    DSButton(L10n.signOut, kind: .destructive) { confirmSignOut = true }
                        .accessibilityIdentifier("more.signout")
                    #if DEBUG
                    DebugMenuView(model: model, environment: environment)
                    #endif
                }
                .padding(DSSpacing.gutter)
            }
            .background(DSColor.bg)
            .task(id: model.session?.oid) {
                guard model.session != nil else { return }
                if briefing == nil { briefing = makeBriefingSettings() }
                await briefing?.load()
            }
            .navigationTitle(Text(L10n.tabMore))
            .alert(Text(L10n.signOutTitle), isPresented: $confirmSignOut) {
                Button(role: .cancel) {} label: { Text(L10n.cancel) }
                Button(role: .destructive) {
                    Task { await model.signOut() }
                } label: { Text(L10n.signOut) }
            } message: {
                Text(L10n.signOutMessage)
            }
        }
    }

    @MainActor private func makeBriefingSettings() -> BriefingSettingsModel {
        let auth = environment.auth
        return BriefingSettingsModel(
            service: environment.briefing,
            accessToken: { try await auth.accessToken() },
            onReauthNeeded: { [model] in model.needsReauth = true },
            reminder: environment.briefingReminder,
            reminderTitle: { String(localized: L10n.brfNotificationTitle) })
    }

    static func initials(_ name: String) -> String {
        name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
    }
}
