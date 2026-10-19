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
    @State private var selection: AppTab
    @State private var inbox: ManagerInboxModel?
    @State private var team: TeamCoverageModel?

    init(model: AppModel, environment: AppEnvironment) {
        self.model = model
        self.environment = environment
        #if DEBUG
        _selection = State(
            initialValue: environment.startOnApprovals ? .approvals : environment.startOnVacation ? .vacation : .announcements)
        #else
        _selection = State(initialValue: .announcements)
        #endif
    }

    private var session: Session? { model.session }

    @ViewBuilder private func content(for tab: AppTab) -> some View {
        switch tab {
        case .announcements: FeedView(model: model, environment: environment, title: tab.title)
        case .more: MoreView(model: model, environment: environment)
        case .vacation: VacationView(model: model, environment: environment, title: tab.title)
        case .approvals:
            if let inbox, let team {
                ManagerInboxView(
                    inbox: inbox, team: team, makeDetail: makeDecisionDetail, autopilot: approvalsAutopilot,
                    opensFirst: opensFirstApproval, opensTeam: opensTeamCoverage)
            } else {
                PlaceholderTab(title: tab.title, symbol: tab.symbol)
            }
        case .week: PlaceholderTab(title: tab.title, symbol: tab.symbol)
        }
    }

    private func tabLabel(_ title: LocalizedStringResource, _ symbol: String) -> some View {
        Label { Text(title) } icon: { Image(systemName: symbol) }
    }

    var body: some View {
        @Bindable var model = model
        TabView(selection: $selection) {
            ForEach(AppTab.tabs(for: session)) { tab in
                content(for: tab)
                    .tabItem { tabLabel(tab.title, tab.symbol) }
                    .badge(tab == .approvals ? (inbox?.count ?? 0) : 0)
                    .tag(tab)
            }
        }
        .sheet(isPresented: $model.needsReauth) {
            ReauthSheet(model: model)
                .interactiveDismissDisabled()
        }
        .task(id: session?.oid) {
            guard session?.has(.manager) == true else {
                inbox = nil
                team = nil
                return
            }
            if inbox == nil { inbox = makeInbox() }
            if team == nil { team = makeTeam() }
            await inbox?.loadQuietly()  // the badge, before the tab is opened
        }
    }

    @MainActor private func makeInbox() -> ManagerInboxModel {
        let auth = environment.auth
        let events = environment.events, context = environment.taskContext
        return ManagerInboxModel(
            service: environment.vacation,
            accessToken: { try await auth.accessToken() },
            onReauthNeeded: { [model] in model.needsReauth = true },
            makeFlow: {
                TaskFlow(
                    taskId: "T-VAC-APR", feature: "vac", mode: .classic, context: context, sink: events,
                    confirmAction: .decide)
            })
    }

    @MainActor private func makeTeam() -> TeamCoverageModel {
        let auth = environment.auth
        let events = environment.events, context = environment.taskContext
        return TeamCoverageModel(
            service: environment.vacation,
            accessToken: { try await auth.accessToken() },
            onReauthNeeded: { [model] in model.needsReauth = true },
            today: CalendarDay(date: environment.clock()),
            makeFlow: {
                TaskFlow(taskId: "T-VAC-COV", feature: "vac", mode: .classic, context: context, sink: events)
            },
            now: environment.clock)
    }

    private var opensTeamCoverage: Bool {
        #if DEBUG
        environment.vacationAutopilot == .team
        #else
        false
        #endif
    }

    @MainActor private func makeDecisionDetail(_ seed: VacationRequestSummary) -> RequestDetailModel {
        let auth = environment.auth
        let inbox = inbox
        return RequestDetailModel(
            id: seed.id, role: .approver, seed: seed, service: environment.vacation,
            accessToken: { try await auth.accessToken() },
            onReauthNeeded: { [model] in model.needsReauth = true },
            flow: { inbox?.currentFlow() },
            onChanged: { Task { await inbox?.loadQuietly() } })
    }

    private var opensFirstApproval: Bool {
        #if DEBUG
        [.decision, .rejectReason, .approveConfirmed].contains(environment.vacationAutopilot)
        #else
        false
        #endif
    }

    private var approvalsAutopilot: DetailAutopilot? {
        #if DEBUG
        switch environment.vacationAutopilot {
        case .decision: .none
        case .rejectReason: .reject
        case .approveConfirmed: .approve
        default: nil
        }
        #else
        nil
        #endif
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
