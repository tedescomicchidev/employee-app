import Core
import SwiftUI

/// "Freigaben" tab: requests waiting for the manager; tap one to decide (FR-VAC-004).
struct ManagerInboxView: View {
    enum Segment: Hashable { case requests, team }

    let inbox: ManagerInboxModel
    let team: TeamCoverageModel
    let makeDetail: (VacationRequestSummary) -> RequestDetailModel
    let autopilot: DetailAutopilot?
    /// Screenshots: push the first request right after the list loaded.
    var opensFirst = false
    /// Screenshots: open on the Team segment.
    var opensTeam = false
    @State private var path: [String] = []
    @State private var segment: Segment = .requests

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: DSSpacing.m) {
                    DSSegmentedControl(
                        [.init(.requests, L10n.vacInboxSegmentRequests), .init(.team, L10n.vacTeamTitle)],
                        selection: $segment)
                        .accessibilityIdentifier("approvals.segment")
                    if segment == .team {
                        TeamCoverageView(model: team)
                    } else {
                        requestsContent
                    }
                }
                .padding(DSSpacing.gutter)
            }
            .background(DSColor.bg)
            .navigationTitle(Text(L10n.tabApprovals))
            .refreshable { segment == .team ? await team.refresh() : await inbox.refresh() }
            .navigationDestination(for: String.self) { id in
                RequestDetailHost(autopilot: autopilot) {
                    makeDetail(inbox.items.first { $0.id == id } ?? placeholder(id))
                }
            }
            .task(id: segment) { if segment == .team { await team.begin() } }
        }
        .task {
            await inbox.begin()
            #if DEBUG
            if opensTeam {
                segment = .team
                await team.begin()
                await team.setRange(start: CalendarDay(year: 2026, month: 11, day: 9), end: CalendarDay(year: 2026, month: 11, day: 27))
            }
            if opensFirst, let first = inbox.items.first { path = [first.id] }
            #endif
        }
        .accessibilityIdentifier("inbox.list")
    }

    @ViewBuilder private var requestsContent: some View {
        VStack(spacing: DSSpacing.m) {
            if let asOf = inbox.offlineAsOf {
                DSBanner(.offline, message: Text(L10n.vacOfflineAsOf(VacationFormat.asOf(asOf))))
                    .accessibilityIdentifier("inbox.offline")
            }
            switch inbox.state {
            case .loading:
                DSSkeleton(rows: 3).accessibilityIdentifier("inbox.loading")
            case let .content(items):
                if items.isEmpty {
                    DSEmptyState(symbol: "checkmark.circle", title: L10n.vacInboxEmptyTitle,
                                 message: L10n.vacInboxEmptyMessage)
                        .accessibilityIdentifier("inbox.empty")
                } else {
                    list(items)
                }
            case .forbidden:
                DSEmptyState(symbol: "lock", title: L10n.tabApprovals, message: L10n.vacInboxForbidden)
                    .accessibilityIdentifier("inbox.forbidden")
            case let .error(code, correlationId):
                DSErrorState(
                    title: L10n.vacErrorTitle, message: L10n.vacErrorMessage, retryTitle: L10n.vacRetry,
                    correlationId: correlationId, code: code) { Task { await inbox.refresh() } }
                    .accessibilityIdentifier("inbox.error")
            }
        }
    }

    private func placeholder(_ id: String) -> VacationRequestSummary {
        VacationRequestSummary(
            id: id, status: .pending, start: CalendarDay(year: 1970, month: 1, day: 1),
            end: CalendarDay(year: 1970, month: 1, day: 1), countedDays: 0, approver: "")
    }

    private func list(_ items: [VacationRequestSummary]) -> some View {
        DSGroupedSection(header: L10n.vacInboxGroup(items.count)) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                NavigationLink(value: item.id) {
                    DSListRow(
                        title: Text(verbatim: item.ownerName),
                        subtitle: Text(verbatim: "\(VacationFormat.range(item.start, item.end)) · \(VacationFormat.days(item.countedDays))"),
                        leading: .avatar(initials: VacationFormat.initials(item.ownerName)), showsChevron: true)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("inbox.row.\(item.id)")
                if index < items.count - 1 { DSRowDivider() }
            }
        }
    }
}
