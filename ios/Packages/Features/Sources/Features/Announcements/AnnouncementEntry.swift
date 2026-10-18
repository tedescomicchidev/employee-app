import Core
import SwiftUI

/// Toolbar entry on the Announcements tab, shown to Publishers only (FR-AUTH-002: the API still denies others).
struct ComposeEntry: ViewModifier {
    let model: AppModel
    let environment: AppEnvironment
    @State private var flowItem: ComposeFlowItem?

    func body(content: Content) -> some View {
        content
            .toolbar {
                if model.session?.has(.communicator) == true {
                    ToolbarItem(placement: .navigation) {
                        Button { open() } label: {
                            Label { Text(L10n.annEntry) } icon: { Image(systemName: "square.and.pencil") }
                        }
                        .accessibilityIdentifier("announcements.compose")
                    }
                }
            }
            .sheet(item: $flowItem) { publish in
                ComposeFlowView(model: publish.model, startAtAudience: publish.startAtAudience) { flowItem = nil }
            }
            #if DEBUG
            .task {
                guard flowItem == nil, let autopilot = environment.announcementAutopilot,
                      model.session?.has(.communicator) == true else { return }
                open(autopilot: autopilot)
            }
            #endif
    }

    @MainActor private func open() { present(nil) }

    #if DEBUG
    @MainActor private func open(autopilot: AnnouncementAutopilot) { present(autopilot) }
    #endif

    @MainActor private func present(_ autopilot: AnnouncementAutopilot?) {
        guard let session = model.session else { return }
        let flow = TaskFlow(
            taskId: "T-ANN-PUB", feature: "ann", mode: .classic,
            context: environment.taskContext, sink: environment.events)
        let auth = environment.auth
        let publish = PublishModel(
            service: environment.announcements,
            accessToken: { try await auth.accessToken() },
            onReauthNeeded: { [model] in model.needsReauth = true },
            drafts: environment.drafts, userKey: session.oid, flow: flow)
        #if DEBUG
        if let autopilot {
            publish.draft = autopilot.prefill
            Task { await Self.drive(publish, autopilot) }
        }
        #endif
        #if DEBUG
        flowItem = ComposeFlowItem(model: publish, startAtAudience: autopilot == .audienceOK)
        #else
        flowItem = ComposeFlowItem(model: publish)
        #endif
    }

    #if DEBUG
    @MainActor private static func drive(_ model: PublishModel, _ autopilot: AnnouncementAutopilot) async {
        switch autopilot {
        case .composeOK, .audienceOK: break
        case .composeValidation, .reviewOK: await model.review()
        case .reviewSuccess: await model.review(); await model.publish()
        case .reviewError, .reviewOffline: await model.review(); await model.publish()
        }
    }
    #endif
}

struct ComposeFlowItem: Identifiable {
    let id = UUID()
    let model: PublishModel
    var startAtAudience = false
}

extension View {
    func composeEntry(model: AppModel, environment: AppEnvironment) -> some View {
        modifier(ComposeEntry(model: model, environment: environment))
    }
}
