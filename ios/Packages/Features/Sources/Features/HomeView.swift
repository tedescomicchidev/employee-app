import Core
import SwiftUI

/// Signed-in home: name + role from `GET /v1/me`. Feature content lands in later slices.
struct HomeView: View {
    let model: AppModel
    let environment: AppEnvironment
    let title: LocalizedStringResource

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DSSpacing.m) {
                    if model.isOffline {
                        DSBanner(.offline, message: Text(L10n.homeOffline))
                    }
                    if let session = model.session {
                        IdentityCard(session: session)
                    }
                    DSEmptyState(symbol: "megaphone", title: L10n.placeholderTitle, message: L10n.placeholderMessage)
                }
                .padding(DSSpacing.gutter)
            }
            .background(DSColor.bg)
            .navigationTitle(Text(title))
            .composeEntry(model: model, environment: environment)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { Task { await model.reload() } } label: {
                        Label { Text(L10n.homeRefresh) } icon: { Image(systemName: "arrow.clockwise") }
                    }
                    .accessibilityIdentifier("home.refresh")
                }
            }
            .refreshable { await model.reload() }
        }
    }
}

struct IdentityCard: View {
    let session: Session

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            Text(verbatim: session.displayName)
                .font(DSFont.title)
                .accessibilityIdentifier("home.name")
            Text(verbatim: session.upn).font(DSFont.secondary).foregroundStyle(DSColor.ink2)
            // Reflows to a column when the chips no longer fit (AX sizes).
            ViewThatFits(in: .horizontal) {
                HStack(spacing: DSSpacing.xs) { chips }
                VStack(alignment: .leading, spacing: DSSpacing.xs) { chips }
            }
            .accessibilityIdentifier("home.role")
            .padding(.top, DSSpacing.xxs)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DSSpacing.m)
        .background(DSColor.card, in: RoundedRectangle(cornerRadius: DSRadius.hero))
    }

    @ViewBuilder private var chips: some View {
        ForEach(Role.allCases.filter(session.roles.contains), id: \.self) { role in
            DSStatusChip(role == session.primaryRole ? .info : .neutral,
                         label: Text(L10n.role(role)), symbol: Self.symbol(role))
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    private static func symbol(_ role: Role) -> String {
        switch role {
        case .communicator: "megaphone"
        case .manager: "person.2"
        case .employee: "person"
        }
    }
}

#Preview("Identity card") {
    IdentityCard(session: Session(oid: "o", displayName: "Maria Keller", upn: "mgr1@example.test",
                                  roles: [.manager, .employee], tenantID: "t"))
        .padding(DSSpacing.gutter)
        .background(DSColor.bg)
}
