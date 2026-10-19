import Core
import SwiftUI

/// "My requests" (FR-VAC-007): pending first, then the decided ones per year. The statuses and
/// the order are the API's list (the manager sees the same rows); this only groups them.
enum MyRequestsGrouping {
    struct Group: Equatable, Identifiable {
        enum Kind: Equatable { case pending, decided(year: Int) }
        let kind: Kind
        let items: [VacationRequestSummary]
        var id: String {
            switch kind {
            case .pending: "pending"
            case let .decided(year): "decided-\(year)"
            }
        }
    }

    static func groups(_ requests: [VacationRequestSummary]) -> [Group] {
        var result: [Group] = []
        let pending = requests.filter { $0.status == .pending }.sorted { $0.start < $1.start }
        if !pending.isEmpty { result.append(Group(kind: .pending, items: pending)) }
        let decided = requests.filter { $0.status != .pending }
        for year in Set(decided.map(\.start.year)).sorted(by: >) {
            let items = decided.filter { $0.start.year == year }.sorted { $0.start < $1.start }
            result.append(Group(kind: .decided(year: year), items: items))
        }
        return result
    }
}

struct MyRequestsView: View {
    let overview: VacationOverviewModel

    var body: some View {
        ScrollView {
            VStack(spacing: DSSpacing.m) {
                if let asOf = overview.offlineAsOf {
                    DSBanner(.offline, message: Text(L10n.vacOfflineAsOf(VacationFormat.asOf(asOf))))
                        .accessibilityIdentifier("mine.offline")
                }
                switch overview.state {
                case .loading:
                    DSSkeleton(rows: 4).accessibilityIdentifier("mine.loading")
                case let .content(_, requests):
                    if requests.isEmpty {
                        DSEmptyState(symbol: "tray", title: L10n.vacMineEmptyTitle, message: L10n.vacMineEmptyMessage)
                            .accessibilityIdentifier("mine.empty")
                    } else {
                        ForEach(MyRequestsGrouping.groups(requests)) { group in
                            section(group)
                        }
                    }
                case .notProvisioned:
                    DSEmptyState(symbol: "person.crop.circle.badge.questionmark",
                                 title: L10n.vacNotProvisionedTitle, message: L10n.vacNotProvisionedMessage)
                        .accessibilityIdentifier("mine.notprovisioned")
                case let .error(code, correlationId):
                    DSErrorState(
                        title: L10n.vacErrorTitle, message: L10n.vacErrorMessage, retryTitle: L10n.vacRetry,
                        correlationId: correlationId, code: code) { Task { await overview.refresh() } }
                        .accessibilityIdentifier("mine.error")
                }
            }
            .padding(DSSpacing.gutter)
        }
        .background(DSColor.bg)
        .navigationTitle(Text(L10n.vacMineTitle))
        .vacInlineTitle()
        .refreshable { await overview.refresh() }
        .accessibilityIdentifier("mine.list")
    }

    private func section(_ group: MyRequestsGrouping.Group) -> some View {
        let header: LocalizedStringResource = switch group.kind {
        case .pending: L10n.vacMineGroupPending
        case let .decided(year): L10n.vacMineGroupDecided(year)
        }
        return DSGroupedSection(header: header) {
            ForEach(Array(group.items.enumerated()), id: \.element.id) { index, item in
                NavigationLink(value: VacationView.Route.detail(item.id)) {
                    MyRequestRow(item: item)
                }
                .buttonStyle(.plain)
                if index < group.items.count - 1 { DSRowDivider() }
            }
        }
    }
}

private struct MyRequestRow: View {
    let item: VacationRequestSummary
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // At accessibility sizes the chip goes below the text so neither column is squeezed.
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: DSSpacing.xs))
            : AnyLayout(HStackLayout(alignment: .top, spacing: DSSpacing.s))
        layout {
            VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                Text(verbatim: VacationFormat.range(item.start, item.end)).font(DSFont.body)
                Text(verbatim: subtitle).font(DSFont.secondary).foregroundStyle(DSColor.ink2)
                if let reason = item.reason, !reason.isEmpty {
                    Text(L10n.vacMineReason(reason)).font(DSFont.body)
                }
            }
            if !typeSize.isAccessibilitySize { Spacer(minLength: DSSpacing.xs) }
            DSStatusChip(item.status.chipKind, label: Text(L10n.vacStatus(item.status)))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DSSpacing.m)
        .padding(.vertical, DSSpacing.xs)
        .frame(minHeight: DSSize.rowMin)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("mine.row.\(item.id)")
    }

    private var subtitle: String {
        let days = VacationFormat.days(item.countedDays)
        if item.status == .pending { return "\(days) · \(String(localized: L10n.vacNextApprover(item.approver)))" }
        guard let decided = item.decidedAt else { return days }
        let day = CalendarDay(date: decided)
        return "\(days) · \(String(localized: L10n.vacMineDecidedOn(VacationFormat.shortMonth(day))))"
    }
}
