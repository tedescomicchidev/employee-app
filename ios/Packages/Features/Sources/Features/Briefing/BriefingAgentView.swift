import Core
import SwiftUI

/// Week tab in AGENT mode (FR-BRF-001/002/004/005 AGENT): the briefing agent instead of the week screen.
/// "Open the full week" shows the classic screen, which reads the week again (nothing is kept).
struct BriefingAgentView: View {
    enum Route: Hashable { case week }

    let model: AppModel
    let environment: AppEnvironment
    @State private var chat: AgentChatModel?
    @State private var chatOwner: String?
    @State private var week: BriefingModel?
    @State private var path: [Route] = []
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
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .week:
                    if let week { BriefingWeekHost(model: week) }
                }
            }
            // The week screen's day rows push the day's id.
            .navigationDestination(for: String.self) { id in
                if let day = week?.week?.days.first(where: { $0.id == id }) { BriefingDayView(day: day) }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { chat?.newConversation() } label: {
                        Label { Text(L10n.agentNew) } icon: { Image(systemName: "square.and.pencil") }
                    }
                    .disabled(chat.map { $0.isEmpty || !$0.canStartOver } ?? true)
                    .accessibilityIdentifier("agent.new")
                }
            }
        }
        .task(id: model.session?.oid) {
            guard let session = model.session else { return }
            if chat == nil || chatOwner != session.oid {  // another account never sees this one's chat
                chat = AgentChat.make(feature: .briefing, model: model, environment: environment)
                week = makeWeek()
                chatOwner = session.oid
                path = []
            }
            #if DEBUG
            if let chat, !autopilotRan, let autopilot = environment.agentAutopilot {
                autopilotRan = true
                await AgentChat.drive(chat, autopilot)
            }
            #endif
        }
        // FR-BRF-003.2 AGENT: the tap on the Monday notification opens the briefing conversation,
        // and asks for the week now.
        .onChange(of: model.briefingOpenRequests) {
            guard let chat, !chat.isBusy else { return }
            path = []
            chat.newConversation()
            chat.send(String(localized: L10n.brfAgentSuggestWeek))
        }
    }

    private var config: AgentChatConfig {
        var config = AgentChatConfig(
            emptyMessage: L10n.brfAgentEmpty,
            suggestions: [L10n.brfAgentSuggestWeek, L10n.brfAgentSuggestConflicts, L10n.brfAgentSuggestTurnon])
        config.openWeek = {
            Task {
                path = [.week]
                await week?.begin()
            }
        }
        return config
    }

    /// Only used to show the full week: it starts no T-BRF-VIEW flow of its own (the chat's flow is the task).
    @MainActor private func makeWeek() -> BriefingModel {
        let auth = environment.auth
        return BriefingModel(
            service: environment.briefing,
            accessToken: { try await auth.accessToken() },
            onReauthNeeded: { [model] in model.needsReauth = true },
            reminder: environment.briefingReminder,
            reminderTitle: { String(localized: L10n.brfNotificationTitle) },
            makeFlow: nil)
    }
}

/// The classic week screen inside the agent tab's navigation stack.
private struct BriefingWeekHost: View {
    let model: BriefingModel

    var body: some View {
        BriefingContent(model: model)
            .background(DSColor.bg)
            .navigationTitle(Text(L10n.tabWeek))
    }
}
