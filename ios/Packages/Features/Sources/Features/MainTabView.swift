import Core
import SwiftUI

/// Tabs per docs/design: Aktuell, Ferien, Woche, Mehr; managers get "Freigaben" as the fifth tab.
/// Only built once the session (and so the roles) is known, so tabs never flicker.
enum AppTab: String, Identifiable, CaseIterable {
    case announcements, vacation, week, approvals, more

    var id: String { rawValue }

    /// The UI hides what the API would deny (FR-AUTH-002); the API stays the authority.
    static func tabs(for session: Session?) -> [AppTab] {
        allCases.filter { $0 != .approvals || session?.has(.manager) == true }
    }

    var title: LocalizedStringResource {
        switch self {
        case .announcements: L10n.tabAnnouncements
        case .vacation: L10n.tabVacation
        case .week: L10n.tabWeek
        case .approvals: L10n.tabApprovals
        case .more: L10n.tabMore
        }
    }

    var symbol: String {
        switch self {
        case .announcements: "megaphone"
        case .vacation: "sun.max"
        case .week: "calendar"
        case .approvals: "checkmark.circle"
        case .more: "slider.horizontal.3"
        }
    }
}

struct MainTabView: View {
    let model: AppModel
    let environment: AppEnvironment

    private var session: Session? { model.session }

    @ViewBuilder private func content(for tab: AppTab) -> some View {
        switch tab {
        case .announcements: FeedView(model: model, environment: environment, title: tab.title)
        case .more: MoreView(model: model, environment: environment)
        case .vacation, .week, .approvals: PlaceholderTab(title: tab.title, symbol: tab.symbol)
        }
    }

    private func tabLabel(_ title: LocalizedStringResource, _ symbol: String) -> some View {
        Label { Text(title) } icon: { Image(systemName: symbol) }
    }

    var body: some View {
        @Bindable var model = model
        TabView {
            ForEach(AppTab.tabs(for: session)) { tab in
                content(for: tab)
                    .tabItem { tabLabel(tab.title, tab.symbol) }
            }
        }
        .sheet(isPresented: $model.needsReauth) {
            ReauthSheet(model: model)
                .interactiveDismissDisabled()
        }
    }
}

struct PlaceholderTab: View {
    let title: LocalizedStringResource
    let symbol: String

    var body: some View {
        NavigationStack {
            DSEmptyState(symbol: symbol, title: L10n.placeholderTitle, message: L10n.placeholderMessage)
                .frame(maxHeight: .infinity)
                .background(DSColor.bg)
                .navigationTitle(Text(title))
        }
    }
}

struct ReauthSheet: View {
    let model: AppModel

    var body: some View {
        VStack(spacing: DSSpacing.l) {
            DSEmptyState(symbol: "lock", title: L10n.reauthTitle, message: L10n.reauthMessage)
            if let issue = model.issue, issue != .cancelled {
                DSBanner(issue.bannerKind, message: Text(issue.message))
            }
            DSButton(L10n.signInButton, isBusy: model.isReauthenticating) {
                Task { await model.reauthenticate() }
            }
            .accessibilityIdentifier("reauth.button")
        }
        .padding(DSSpacing.gutter)
        .presentationDetents([.medium])
    }
}
