import Core
import SwiftUI

/// Week tab in CLASSIC mode (FR-BRF-001/002/003/005): opt-in screen, the week read live, and its failures.
/// The calendar is held in memory only; leaving the app and coming back reads it again.
struct BriefingView: View {
    let model: AppModel
    let environment: AppEnvironment
    let title: LocalizedStringResource
    @State private var briefing: BriefingModel?
    @State private var path: [String] = []
    #if DEBUG
    @State private var autopilotRan = false
    #endif

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let briefing {
                    BriefingContent(model: briefing)
                } else {
                    DSSkeleton().padding(DSSpacing.gutter)
                }
            }
            .background(DSColor.bg)
            .navigationTitle(Text(title))
            .navigationDestination(for: String.self) { id in
                if let day = briefing?.week?.days.first(where: { $0.id == id }) {
                    BriefingDayView(day: day)
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    if briefing?.week != nil {
                        Button { Task { await briefing?.refresh() } } label: {
                            Label { Text(L10n.brfWeekRefresh) } icon: { Image(systemName: "arrow.clockwise") }
                        }
                        .accessibilityIdentifier("briefing.refresh")
                    }
                }
            }
        }
        .task(id: model.session?.oid) {
            guard let session = model.session else { return }
            if briefing == nil || session.oid != ownerId { briefing = makeBriefing() }
            ownerId = session.oid
            await briefing?.begin()
            #if DEBUG
            await runAutopilot()
            #endif
        }
        // The tap on "Your week is ready" (FR-BRF-003.2): read the week now, not an older answer.
        .onChange(of: model.briefingOpenRequests) { Task { await briefing?.refresh() } }
        .accessibilityIdentifier("briefing.root")
    }

    @State private var ownerId: String?

    @MainActor private func makeBriefing() -> BriefingModel {
        let auth = environment.auth
        let events = environment.events, context = environment.taskContext
        return BriefingModel(
            service: environment.briefing,
            accessToken: { try await auth.accessToken() },
            onReauthNeeded: { [model] in model.needsReauth = true },
            reminder: environment.briefingReminder,
            reminderTitle: { String(localized: L10n.brfNotificationTitle) },
            makeFlow: {
                TaskFlow(
                    taskId: "T-BRF-VIEW", feature: "brf", mode: .classic, context: context, sink: events,
                    confirmAction: .optIn)
            })
    }

    #if DEBUG
    @MainActor private func runAutopilot() async {
        guard !autopilotRan, let autopilot = environment.briefingAutopilot else { return }
        autopilotRan = true
        switch autopilot {
        case .consentInProgress: Task { await briefing?.turnOn() }
        case .notificationPermission: await briefing?.turnOn()
        case .day:
            if let day = briefing?.week?.days.first(where: { !$0.events.isEmpty }) { path = [day.id] }
        case .optIn, .week, .settings: break
        }
    }
    #endif
}

struct BriefingContent: View {
    let model: BriefingModel

    var body: some View {
        ScrollView {
            VStack(spacing: DSSpacing.m) {
                switch model.state {
                case .checking:
                    DSSkeleton(rows: 4).accessibilityIdentifier("briefing.loading")
                case let .optIn(phase):
                    if model.reminderOffer == .ask {
                        ReminderAsk(model: model)
                    } else if model.declined {
                        Declined(model: model)
                    } else {
                        OptIn(model: model, phase: phase)
                    }
                case let .reading(stillWorking):
                    Reading(model: model, stillWorking: stillWorking)
                case let .content(week):
                    WeekContent(model: model, week: week)
                case let .problem(problem):
                    ProblemView(model: model, problem: problem)
                }
            }
            .padding(DSSpacing.gutter)
        }
        .refreshable { await model.refresh() }
        // The decision stays in reach above the tab bar, whatever the text size.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if case let .optIn(phase) = model.state, model.reminderOffer != .ask, !model.declined {
                OptInActions(model: model, phase: phase)
            }
        }
    }
}

private struct OptInActions: View {
    let model: BriefingModel
    let phase: BriefingModel.OptInPhase

    var body: some View {
        VStack(spacing: DSSpacing.xs) {
            DSButton(phase == .working ? L10n.brfOptinWorking : L10n.brfOptinTurnon, isBusy: phase == .working) {
                Task { await model.turnOn() }
            }
            .disabled(phase == .offline)
            .accessibilityIdentifier("briefing.optin.turnon")
            DSButton(L10n.brfOptinNotnow, kind: .neutral) { model.notNow() }
                .disabled(phase == .working)
                .accessibilityIdentifier("briefing.optin.notnow")
        }
        .padding(.horizontal, DSSpacing.gutter)
        .padding(.vertical, DSSpacing.xs)
        .background(.bar)
    }
}

// MARK: Opt-in (FR-BRF-001)

private struct OptIn: View {
    let model: BriefingModel
    let phase: BriefingModel.OptInPhase

    var body: some View {
        VStack(spacing: DSSpacing.m) {
            DSEmptyState(symbol: "calendar.badge.clock", title: L10n.brfOptinTitle, message: L10n.brfOptinMessage)
            // The explicit action names what is accessed before anything is read (FR-BRF-001.2).
            DSGroupedSection(header: L10n.brfOptinAccessHeader) {
                DSListRow(
                    title: Text(L10n.brfOptinAccessCalendar), leading: .icon(systemName: "calendar", tint: DSColor.tint))
                DSRowDivider()
                DSListRow(
                    title: Text(L10n.brfOptinAccessVia), leading: .icon(systemName: "person.badge.key", tint: DSColor.tint))
                DSRowDivider()
                DSListRow(
                    title: Text(L10n.brfOptinAccessStored),
                    leading: .icon(systemName: "internaldrive", tint: DSColor.tint))
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("briefing.optin.access")
            switch phase {
            case .failed: DSBanner(.error, message: Text(L10n.brfOptinFailed)).accessibilityIdentifier("briefing.optin.failed")
            case .offline: DSBanner(.offline, message: Text(L10n.brfOptinOffline)).accessibilityIdentifier("briefing.optin.offline")
            case .ready, .working: EmptyView()
            }
            Text(L10n.brfOptinFootnote).font(DSFont.caption).foregroundStyle(DSColor.ink2)
                .multilineTextAlignment(.center)
        }
    }
}

private struct Declined: View {
    let model: BriefingModel

    var body: some View {
        DSEmptyState(
            symbol: "calendar.badge.clock", title: L10n.brfOptinTitle, message: L10n.brfOptinFootnote,
            actionTitle: L10n.brfOptinTurnon) { model.reconsider() }
            .accessibilityIdentifier("briefing.declined")
    }
}

/// Right after opting in: ask once, in context, for the Monday reminder (FR-BRF-003.1).
private struct ReminderAsk: View {
    let model: BriefingModel

    var body: some View {
        VStack(spacing: DSSpacing.m) {
            DSEmptyState(symbol: "bell.badge", title: L10n.brfReminderTitle, message: L10n.brfReminderMessage)
            DSButton(L10n.brfReminderAllow) { Task { await model.allowReminder() } }
                .accessibilityIdentifier("briefing.reminder.allow")
            DSButton(L10n.brfReminderSkip, kind: .neutral) { Task { await model.skipReminder() } }
                .accessibilityIdentifier("briefing.reminder.skip")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("briefing.reminder")
    }
}

// MARK: Reading (40-60 s)

private struct Reading: View {
    let model: BriefingModel
    let stillWorking: Bool

    var body: some View {
        VStack(spacing: DSSpacing.m) {
            ProgressView()
                .controlSize(.large)
                .padding(.top, DSSpacing.xl)
                .accessibilityHidden(true)
            Text(L10n.brfReadingTitle).font(DSFont.sheetTitle).multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text(L10n.brfReadingMessage).font(DSFont.body).foregroundStyle(DSColor.ink2).multilineTextAlignment(.center)
            if stillWorking {
                DSBanner(.info, message: Text(L10n.brfReadingSlow)).accessibilityIdentifier("briefing.slow")
            }
            DSButton(L10n.brfReadingStop, kind: .neutral) { model.stopReading() }
                .accessibilityIdentifier("briefing.stop")
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("briefing.reading")
    }
}

// MARK: Week (FR-BRF-002, FR-BRF-005.2/3)

private struct WeekContent: View {
    let model: BriefingModel
    let week: BriefingWeek

    var body: some View {
        VStack(spacing: DSSpacing.m) {
            summary
            if week.isPartial {
                // Labelled partial, with the missing days named; those days are not shown as free (FR-BRF-005.3).
                VStack(alignment: .leading, spacing: DSSpacing.xs) {
                    Text(L10n.brfWeekPartialTitle).font(DSFont.sectionHeader)
                    DSBanner(
                        .info, message: Text(L10n.brfWeekPartialMessage(missingNames)),
                        actionTitle: L10n.brfRetry) { Task { await model.refresh() } }
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("briefing.partial")
            }
            if week.isEmpty {
                DSEmptyState(
                    symbol: "calendar", title: L10n.brfWeekEmptyTitle, message: L10n.brfWeekEmptyMessage)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("briefing.empty")
            } else {
                ForEach(week.days) { day in DaySection(day: day) }
            }
            if model.reminderScheduled {
                Text(L10n.brfWeekReminderOn).font(DSFont.caption).foregroundStyle(DSColor.ink2)
                    .accessibilityIdentifier("briefing.reminder.on")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("briefing.week")
    }

    private var missingNames: String {
        week.missingDays.map { VacationFormat.weekday($0.day) }.joined(separator: ", ")
    }

    private var freeBlockCount: Int { week.days.reduce(0) { $0 + $1.freeBlocks.count } }

    private var summary: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xxs) {
            Text(L10n.brfWeekHeader(BriefingFormat.weekRange(week.start, week.end))).font(DSFont.sectionHeader)
                .foregroundStyle(DSColor.ink2)
            HStack(spacing: DSSpacing.xs) {
                DSStatusChip(.info, label: Text(L10n.brfSummaryEvents(week.eventCount)), symbol: "calendar")
                if freeBlockCount > 0 {
                    DSStatusChip(.neutral, label: Text(L10n.brfSummaryFree(freeBlockCount)), symbol: "clock")
                }
                if week.conflictCount > 0 {
                    DSStatusChip(.pending, label: Text(L10n.brfSummaryConflicts(week.conflictCount)), symbol: "exclamationmark.triangle")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("briefing.summary")
    }
}

private struct DaySection: View {
    let day: BriefingDay

    var body: some View {
        DSGroupedSection {
            NavigationLink(value: day.id) {
                DSListRow(
                    title: Text(verbatim: BriefingFormat.dayHeader(day.day)),
                    trailing: day.missing ? nil : Text(L10n.brfSummaryEvents(day.events.count)), showsChevron: true)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("briefing.day.\(day.id)")
            if day.missing {
                DSRowDivider()
                DSListRow(title: Text(L10n.brfDayMissing), leading: .icon(systemName: "questionmark.circle", tint: DSColor.orange))
            } else if day.events.isEmpty {
                DSRowDivider()
                DSListRow(title: Text(L10n.brfDayNoevents))
            } else {
                ForEach(day.events) { event in
                    DSRowDivider()
                    EventRow(event: event)
                }
            }
        }
    }
}

struct EventRow: View {
    let event: BriefingEvent

    var body: some View {
        // The title is somebody else's text: verbatim, never markup or a link, and never an instruction.
        DSListRow(
            title: Text(verbatim: event.title), subtitle: Text(verbatim: subtitle),
            leading: event.hasConflict
                ? .icon(systemName: "exclamationmark.triangle.fill", tint: DSColor.orange)
                : .icon(systemName: event.online ? "video.fill" : "calendar", tint: DSColor.tint))
            .accessibilityIdentifier("briefing.event.\(event.id)")
    }

    private var subtitle: String {
        var parts = [BriefingFormat.eventLine(event)]
        if !event.location.isEmpty { parts.append(event.location) }
        if event.online { parts.append(String(localized: L10n.brfOnline)) }
        if event.attendeeCount > 1 { parts.append(String(localized: L10n.brfAttendees(event.attendeeCount))) }
        if event.hasConflict { parts.append(String(localized: L10n.brfConflictChip)) }
        return parts.joined(separator: " · ")
    }
}

// MARK: Problems (FR-BRF-005.1)

private struct ProblemView: View {
    let model: BriefingModel
    let problem: BriefingModel.Problem

    var body: some View {
        Group {
            switch problem {
            case .unavailable: error(L10n.brfProblemUnavailableTitle, L10n.brfProblemUnavailableMessage)
            case .timedOut: error(L10n.brfProblemTimeoutTitle, L10n.brfProblemTimeoutMessage)
            case let .failed(code, correlationId):
                DSErrorState(
                    title: L10n.brfProblemFailedTitle, message: L10n.brfProblemFailedMessage, retryTitle: L10n.brfRetry,
                    correlationId: correlationId, code: code) { retry() }
            case .noLicence: calm("lock", L10n.brfProblemNolicenceTitle, L10n.brfProblemNolicenceMessage)
            case .consentRequired: calm("lock.shield", L10n.brfProblemConsentTitle, L10n.brfProblemConsentMessage)
            case .offline: calm("wifi.slash", L10n.brfProblemOfflineTitle, L10n.brfProblemOfflineMessage)
            case .signedOut: calm("person.crop.circle.badge.exclamationmark", L10n.brfProblemSignedoutTitle, L10n.brfProblemSignedoutMessage)
            case .stopped: calm("stop.circle", L10n.brfProblemStoppedTitle, L10n.brfProblemStoppedMessage)
            case .notProvisioned: calm("person.crop.circle.badge.questionmark", L10n.brfProblemNotprovisionedTitle, L10n.brfProblemNotprovisionedMessage)
            }
        }
        .accessibilityIdentifier("briefing.problem.\(problem.code)")
    }

    private func error(_ title: LocalizedStringResource, _ message: LocalizedStringResource) -> some View {
        DSErrorState(title: title, message: message, retryTitle: L10n.brfRetry, code: problem.code) { retry() }
    }

    private func calm(_ symbol: String, _ title: LocalizedStringResource, _ message: LocalizedStringResource) -> some View {
        DSEmptyState(symbol: symbol, title: title, message: message, actionTitle: L10n.brfRetry) { retry() }
    }

    private func retry() { Task { await model.refresh() } }
}

// MARK: Day detail

struct BriefingDayView: View {
    let day: BriefingDay

    var body: some View {
        ScrollView {
            VStack(spacing: DSSpacing.m) {
                DSGroupedSection {
                    if day.events.isEmpty {
                        DSListRow(title: Text(day.missing ? L10n.brfDayMissing : L10n.brfDayNoevents))
                    }
                    ForEach(Array(day.events.enumerated()), id: \.element.id) { index, event in
                        if index > 0 { DSRowDivider() }
                        EventRow(event: event)
                    }
                }
                if !day.freeBlocks.isEmpty {
                    DSGroupedSection(header: L10n.brfDayFreeHeader) {
                        ForEach(Array(day.freeBlocks.enumerated()), id: \.offset) { index, block in
                            if index > 0 { DSRowDivider() }
                            DSListRow(
                                title: Text(L10n.brfFreeBlock(BriefingFormat.timeRange(block.start, block.end))),
                                trailing: Text(verbatim: BriefingFormat.hours(minutes: block.minutes)),
                                leading: .icon(systemName: "clock", tint: DSColor.green))
                        }
                    }
                }
            }
            .padding(DSSpacing.gutter)
        }
        .background(DSColor.bg)
        .navigationTitle(Text(verbatim: BriefingFormat.dayHeader(day.day)))
        .accessibilityIdentifier("briefing.dayDetail")
    }
}
