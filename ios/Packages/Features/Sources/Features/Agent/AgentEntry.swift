import Core
import SwiftUI

/// Builds the chat model of a feature from the app environment. One place, so both entry points wire the
/// same service, token source, connectivity and experiment flows.
@MainActor
enum AgentChat {
    static func make(feature: AgentFeature, model: AppModel, environment: AppEnvironment) -> AgentChatModel {
        let auth = environment.auth
        let events = environment.events, context = environment.taskContext
        return AgentChatModel(
            feature: feature, service: environment.agent,
            accessToken: { try await auth.accessToken() },
            onReauthNeeded: { [model] in model.needsReauth = true },
            makeFlow: { task, runId in
                TaskFlow(
                    taskId: task.taskId, feature: task.feature, mode: .agent, context: context, sink: events,
                    confirmAction: task.confirmAction, runId: runId)
            },
            connectivity: environment.connectivity, now: environment.clock)
    }

    #if DEBUG
    /// Sends the autopilot's messages, one after the other, then taps confirm or the first offered range.
    static func drive(_ chat: AgentChatModel, _ autopilot: AgentAutopilot) async {
        for message in autopilot.messages {
            chat.send(message)
            await chat.waitUntilIdle()
        }
        if autopilot.chooseFirstOption, let option = chat.lastOptions.first {
            chat.choose(option, label: VacationFormat.range(option.start, option.end, long: true))
            await chat.waitUntilIdle()
        }
        if autopilot.confirm, let id = chat.openCardId {
            chat.confirm(proposalId: id)
        }
    }
    #endif
}

/// Announcements tab in AGENT mode (FR-ANN-001/002/003/005 AGENT): the agent composer instead of the feed.
/// An answer's sources open the classic detail screen.
struct AnnouncementAgentView: View {
    let model: AppModel
    let environment: AppEnvironment
    @State private var chat: AgentChatModel?
    @State private var feed: FeedModel?
    @State private var path: [String] = []
    #if DEBUG
    @State private var autopilotRan = false
    #endif

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let chat {
                    AgentChatView(model: chat, config: config)
                } else {
                    DSSkeleton().padding(DSSpacing.gutter)
                }
            }
            .background(DSColor.bg)
            .navigationTitle(Text(L10n.agentTitle))
            .navigationDestination(for: String.self) { id in
                if let feed { AnnouncementDetailView(feed: feed, id: id) }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { chat?.newConversation() } label: {
                        Label { Text(L10n.agentNew) } icon: { Image(systemName: "square.and.pencil") }
                    }
                    .disabled(chat?.isEmpty ?? true)
                    .accessibilityIdentifier("agent.new")
                }
            }
        }
        .task(id: model.session?.oid) {
            guard let session = model.session else { return }
            if chat == nil {
                chat = AgentChat.make(feature: .comms, model: model, environment: environment)
                feed = makeFeed(session)
            }
            #if DEBUG
            if let chat, !autopilotRan, let autopilot = environment.agentAutopilot {
                autopilotRan = true
                await AgentChat.drive(chat, autopilot)
            }
            #endif
        }
    }

    private var config: AgentChatConfig {
        let publisher = model.session?.has(.communicator) == true
        var config = AgentChatConfig(
            emptyMessage: publisher ? L10n.agentEmptyAnnPublisher : L10n.agentEmptyAnnReader,
            suggestions: publisher
                ? [L10n.agentSuggestAnnNew, L10n.agentSuggestAnnHours, L10n.agentSuggestAnnPublish]
                : [L10n.agentSuggestAnnNew, L10n.agentSuggestAnnHours])
        config.openSource = { id in
            Task {
                await feed?.refresh()  // the detail screen reads the announcement from the loaded feed
                path.append(id)
            }
        }
        return config
    }

    /// Only used to show a source's detail: it is never `begin()`-ed, so it starts no T-ANN-READ flow.
    @MainActor private func makeFeed(_ session: Session) -> FeedModel {
        let auth = environment.auth
        let events = environment.events, context = environment.taskContext
        return FeedModel(
            service: environment.announcements,
            accessToken: { try await auth.accessToken() },
            onReauthNeeded: { [model] in model.needsReauth = true },
            cache: environment.feedCache, userKey: session.oid,
            makeFlow: {
                TaskFlow(taskId: "T-ANN-READ", feature: "ann", mode: .agent, context: context, sink: events)
            })
    }
}

/// Vacation tab in AGENT mode (FR-VAC-001..007 AGENT): the agent composer instead of the overview.
/// After a write, "Open my requests" shows the classic list.
struct VacationAgentView: View {
    let model: AppModel
    let environment: AppEnvironment
    @State private var chat: AgentChatModel?
    @State private var overview: VacationOverviewModel?
    @State private var path: [VacationView.Route] = []
    #if DEBUG
    @State private var autopilotRan = false
    #endif

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let chat {
                    AgentChatView(model: chat, config: config)
                } else {
                    DSSkeleton().padding(DSSpacing.gutter)
                }
            }
            .background(DSColor.bg)
            .navigationTitle(Text(L10n.agentTitle))
            .navigationDestination(for: VacationView.Route.self) { route in
                switch route {
                case .mine: if let overview { MyRequestsView(overview: overview) }
                case let .detail(id): RequestDetailHost { makeDetail(id) }
                case .holidays: EmptyView()
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { chat?.newConversation() } label: {
                        Label { Text(L10n.agentNew) } icon: { Image(systemName: "square.and.pencil") }
                    }
                    .disabled(chat?.isEmpty ?? true)
                    .accessibilityIdentifier("agent.new")
                }
            }
        }
        .task(id: model.session?.oid) {
            guard let session = model.session else { return }
            if chat == nil {
                chat = AgentChat.make(feature: .vacation, model: model, environment: environment)
                overview = makeOverview(session)
            }
            #if DEBUG
            if let chat, !autopilotRan, let autopilot = environment.agentAutopilot {
                autopilotRan = true
                await AgentChat.drive(chat, autopilot)
            }
            #endif
        }
    }

    private var config: AgentChatConfig {
        let manager = model.session?.has(.manager) == true
        var config = AgentChatConfig(
            emptyMessage: manager ? L10n.agentEmptyVacManager : L10n.agentEmptyVacEmployee,
            suggestions: manager
                ? [L10n.agentSuggestVacPending, L10n.agentSuggestVacCoverage, L10n.agentSuggestVacBalance]
                : [L10n.agentSuggestVacBalance, L10n.agentSuggestVacRequest, L10n.agentSuggestVacHolidays])
        config.openRequests = {
            Task {
                await overview?.refresh()  // the list is read from the loaded overview
                path.append(.mine)
            }
        }
        return config
    }

    /// Only used to show "My requests": never `begin()`-ed, so it starts no T-VAC-BAL flow.
    @MainActor private func makeOverview(_ session: Session) -> VacationOverviewModel {
        let auth = environment.auth
        let events = environment.events, context = environment.taskContext
        return VacationOverviewModel(
            service: environment.vacation,
            accessToken: { try await auth.accessToken() },
            onReauthNeeded: { [model] in model.needsReauth = true },
            cache: environment.vacationCache, userKey: session.oid,
            makeFlow: {
                TaskFlow(taskId: "T-VAC-BAL", feature: "vac", mode: .agent, context: context, sink: events)
            },
            now: environment.clock)
    }

    @MainActor private func makeDetail(_ id: String) -> RequestDetailModel {
        let auth = environment.auth
        return RequestDetailModel(
            id: id, seed: overview?.requests.first { $0.id == id }, service: environment.vacation,
            accessToken: { try await auth.accessToken() },
            onReauthNeeded: { [model] in model.needsReauth = true },
            onChanged: { [overview] in Task { await overview?.refresh() } })
    }
}
