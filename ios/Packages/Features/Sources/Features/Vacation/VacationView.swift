import Core
import SwiftUI

private struct RequestFlowItem: Identifiable {
    let id = UUID()
    let model: VacationRequestModel
}

/// Vacation tab: the five numbers (FR-VAC-001), the next request, holidays (FR-VAC-006) and the request entry.
struct VacationView: View {
    enum Route: Hashable { case holidays, mine }

    let model: AppModel
    let environment: AppEnvironment
    let title: LocalizedStringResource
    @State private var overview: VacationOverviewModel?
    @State private var flowItem: RequestFlowItem?
    @State private var path: [Route] = []
    #if DEBUG
    @State private var autopilotRan = false
    #endif

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let overview {
                    VacationContent(overview: overview, today: today)
                } else {
                    DSSkeleton().padding(DSSpacing.gutter)
                }
            }
            .background(DSColor.bg)
            .navigationTitle(Text(title))
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .holidays: HolidaysView(model: makeHolidays())
                case .mine: if let overview { MyRequestsView(overview: overview) }
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { openRequest() } label: {
                        Label { Text(L10n.vacRequestButton) } icon: { Image(systemName: "plus") }
                    }
                    .disabled(overview?.canRequest != true)
                    .accessibilityIdentifier("vacation.request")
                }
            }
        }
        .sheet(item: $flowItem, onDismiss: { Task { await overview?.refresh() } }) { item in
            RequestFlowView(model: item.model) { flowItem = nil }
        }
        .task(id: model.session?.oid) {
            guard let session = model.session else { return }
            if overview == nil { overview = makeOverview(session) }
            await overview?.begin()
            #if DEBUG
            runAutopilot()
            #endif
        }
        .accessibilityIdentifier("vacation.overview")
    }

    private var today: CalendarDay { CalendarDay(date: environment.clock()) }

    @MainActor private func makeOverview(_ session: Session) -> VacationOverviewModel {
        let auth = environment.auth
        let events = environment.events, context = environment.taskContext
        return VacationOverviewModel(
            service: environment.vacation,
            accessToken: { try await auth.accessToken() },
            onReauthNeeded: { [model] in model.needsReauth = true },
            cache: environment.vacationCache, userKey: session.oid,
            makeFlow: {
                TaskFlow(taskId: "T-VAC-BAL", feature: "vac", mode: .classic, context: context, sink: events)
            },
            now: environment.clock)
    }

    @MainActor private func makeHolidays() -> HolidaysModel {
        let auth = environment.auth
        return HolidaysModel(
            service: environment.vacation,
            accessToken: { try await auth.accessToken() },
            onReauthNeeded: { [model] in model.needsReauth = true },
            year: today.year)
    }

    @MainActor private func openRequest() { present() }

    @MainActor @discardableResult private func present() -> VacationRequestModel {
        let auth = environment.auth
        let flow = TaskFlow(
            taskId: "T-VAC-REQ", feature: "vac", mode: .classic, context: environment.taskContext,
            sink: environment.events, confirmAction: .request)
        let request = VacationRequestModel(
            service: environment.vacation,
            accessToken: { try await auth.accessToken() },
            onReauthNeeded: { [model] in model.needsReauth = true },
            flow: flow, today: today)
        flowItem = RequestFlowItem(model: request)
        return request
    }

    #if DEBUG
    @MainActor private func runAutopilot() {
        guard !autopilotRan, let autopilot = environment.vacationAutopilot else { return }
        autopilotRan = true
        if autopilot == .holidays || autopilot == .mine {
            path = [autopilot == .mine ? .mine : .holidays]
            return
        }
        let request = present()
        guard let range = autopilot.range, let start = CalendarDay(iso: range.0), let end = CalendarDay(iso: range.1) else {
            return
        }
        Task {
            await request.begin()
            request.setDates(start: start, end: end)
            await request.waitForCheck()
            switch autopilot {
            case .reviewOK, .reviewSuccess, .reviewInsufficient: request.goToReview()
            default: break
            }
            if autopilot == .reviewSuccess { await request.submit() }
        }
    }
    #endif
}

private struct VacationContent: View {
    let overview: VacationOverviewModel
    let today: CalendarDay

    var body: some View {
        ScrollView {
            VStack(spacing: DSSpacing.m) {
                if let asOf = overview.offlineAsOf {
                    VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                        DSBanner(.offline, message: Text(L10n.vacOfflineAsOf(VacationFormat.asOf(asOf))))
                        Text(L10n.vacOfflineRequest).font(DSFont.caption).foregroundStyle(DSColor.ink2)
                            .padding(.horizontal, DSSpacing.xs)
                    }
                    .accessibilityIdentifier("vacation.offline")
                }
                switch overview.state {
                case .loading:
                    DSSkeleton(rows: 4).accessibilityIdentifier("vacation.loading")
                case let .content(balance, requests):
                    Balance(balance: balance)
                    Composition(balance: balance)
                    UpcomingSection(next: overview.next(today: today), isEmpty: requests.isEmpty)
                    historyLink
                    holidaysLink
                case .notProvisioned:
                    DSEmptyState(symbol: "person.crop.circle.badge.questionmark",
                                 title: L10n.vacNotProvisionedTitle, message: L10n.vacNotProvisionedMessage)
                        .accessibilityIdentifier("vacation.notprovisioned")
                case let .error(code, correlationId):
                    DSErrorState(
                        title: L10n.vacErrorTitle, message: L10n.vacErrorMessage, retryTitle: L10n.vacRetry,
                        correlationId: correlationId, code: code) { Task { await overview.refresh() } }
                        .accessibilityIdentifier("vacation.error")
                }
            }
            .padding(DSSpacing.gutter)
        }
        .refreshable { await overview.refresh() }
    }

    private var historyLink: some View {
        DSGroupedSection {
            NavigationLink(value: VacationView.Route.mine) {
                DSListRow(
                    title: Text(L10n.vacMineTitle),
                    leading: .icon(systemName: "tray.full", tint: DSColor.orange), showsChevron: true)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("vacation.mine")
        }
    }

    private var holidaysLink: some View {
        DSGroupedSection {
            NavigationLink(value: VacationView.Route.holidays) {
                DSListRow(
                    title: Text(L10n.vacHolidaysRow),
                    leading: .icon(systemName: "calendar.badge.clock", tint: DSColor.orange), showsChevron: true)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("vacation.holidays")
        }
    }
}

/// The remaining days, big: the one number most people open this tab for.
private struct Balance: View {
    let balance: VacationBalance

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            Text(L10n.vacRemaining(balance.year)).font(DSFont.body).foregroundStyle(DSColor.ink2)
            HStack(alignment: .firstTextBaseline, spacing: DSSpacing.xs) {
                Text(verbatim: "\(balance.remaining)").dsHeroNumber()
                Text(L10n.vacDaysUnit(balance.remaining)).font(DSFont.cardTitle)
            }
            Text(L10n.vacOverviewHint).font(DSFont.body).foregroundStyle(DSColor.ink2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DSSpacing.m)
        .background(DSColor.card, in: RoundedRectangle(cornerRadius: DSRadius.card))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(L10n.vacRemaining(balance.year)))
        .accessibilityValue(Text(L10n.vacDays(balance.remaining)))
        .accessibilityIdentifier("vacation.remaining")
    }
}

private struct Composition: View {
    let balance: VacationBalance

    var body: some View {
        DSGroupedSection(header: L10n.vacOverviewComposition) {
            row(Text(L10n.vacEntitlement(balance.year)), "\(balance.entitlement)", id: "entitlement")
            DSRowDivider()
            row(Text(L10n.vacCarried(balance.year - 1)), "\(balance.carriedOver)", id: "carried")
            DSRowDivider()
            row(Text(L10n.vacApproved), VacationFormat.minus(balance.approved), id: "approved")
            DSRowDivider()
            row(Text(L10n.vacPending), VacationFormat.minus(balance.pending), id: "pending")
        }
    }

    private func row(_ title: Text, _ value: String, id: String) -> some View {
        DSListRow(title: title, trailing: Text(verbatim: value))
            .accessibilityIdentifier("vacation.\(id)")
    }
}

private struct UpcomingSection: View {
    let next: VacationRequestSummary?
    let isEmpty: Bool

    var body: some View {
        if let next {
            DSGroupedSection(header: L10n.vacNext) {
                HStack(alignment: .center, spacing: DSSpacing.s) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: VacationFormat.range(next.start, next.end)).font(DSFont.body)
                        Text(verbatim: "\(VacationFormat.days(next.countedDays)) · \(String(localized: L10n.vacNextApprover(next.approver)))")
                            .font(DSFont.secondary).foregroundStyle(DSColor.ink2)
                    }
                    Spacer(minLength: DSSpacing.xs)
                    DSStatusChip(next.status.chipKind, label: Text(L10n.vacStatus(next.status)))
                }
                .padding(.horizontal, DSSpacing.m)
                .padding(.vertical, DSSpacing.xs)
                .frame(minHeight: DSSize.rowMin)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("vacation.next")
            }
        } else if isEmpty {
            DSEmptyState(symbol: "sun.max", title: L10n.vacEmptyTitle, message: L10n.vacEmptyMessage)
                .accessibilityIdentifier("vacation.empty")
        }
    }
}

extension VacationStatus {
    var chipKind: DSStatusKind {
        switch self {
        case .pending: .pending
        case .approved: .approved
        case .rejected: .rejected
        case .cancelled: .neutral
        }
    }
}

/// Holidays of the user's own canton for the year; a sub-view of the overview (FR-VAC-006.3).
struct HolidaysView: View {
    let model: HolidaysModel

    var body: some View {
        ScrollView {
            VStack(spacing: DSSpacing.m) {
                switch model.state {
                case .loading:
                    DSSkeleton(rows: 5).accessibilityIdentifier("holidays.loading")
                case let .content(holidays):
                    note(holidays)
                    DSGroupedSection {
                        ForEach(Array(holidays.items.enumerated()), id: \.element.id) { index, holiday in
                            DSListRow(title: Text(verbatim: holiday.name),
                                      trailing: Text(verbatim: VacationFormat.short(holiday.day)))
                                .accessibilityIdentifier("holidays.row.\(holiday.day.iso)")
                            if index < holidays.items.count - 1 { DSRowDivider() }
                        }
                    }
                case let .empty(holidays):
                    note(holidays)
                    DSEmptyState(symbol: "calendar", title: L10n.vacHolidaysEmptyTitle,
                                 message: L10n.vacHolidaysEmptyMessage)
                        .accessibilityIdentifier("holidays.empty")
                case .cantonMissing:
                    DSEmptyState(symbol: "mappin.slash", title: L10n.vacCantonTitle, message: L10n.vacCantonMessage)
                        .accessibilityIdentifier("holidays.canton_missing")
                case .offline:
                    DSBanner(.offline, message: Text(L10n.vacRequestOffline),
                             actionTitle: L10n.vacRetry) { Task { await model.load() } }
                        .accessibilityIdentifier("holidays.offline")
                case let .error(code, correlationId):
                    DSErrorState(
                        title: L10n.vacErrorTitle, message: L10n.vacErrorMessage, retryTitle: L10n.vacRetry,
                        correlationId: correlationId, code: code) { Task { await model.load() } }
                        .accessibilityIdentifier("holidays.error")
                }
            }
            .padding(DSSpacing.gutter)
        }
        .background(DSColor.bg)
        .navigationTitle(Text(L10n.vacHolidaysTitle(model.year)))
        .vacInlineTitle()
        .task { await model.load() }
        .refreshable { await model.load() }
    }

    @ViewBuilder private func note(_ holidays: VacationHolidays) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            if let canton = holidays.canton {
                Text(L10n.vacHolidaysCanton(canton)).font(DSFont.sectionHeader).foregroundStyle(DSColor.ink2)
                    .accessibilityAddTraits(.isHeader)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if holidays.needsConfirmation {
                DSBanner(.info, message: Text(L10n.vacHolidaysNote)).accessibilityIdentifier("holidays.note")
            }
        }
    }
}
