import Core
import SwiftUI

/// The "Team" segment of Freigaben (FR-VAC-005): present of total per working day, by week.
struct TeamCoverageView: View {
    let model: TeamCoverageModel
    @State private var isPickingRange = false

    var body: some View {
        VStack(spacing: DSSpacing.m) {
            if let asOf = model.offlineAsOf {
                DSBanner(.offline, message: Text(L10n.vacOfflineAsOf(VacationFormat.asOf(asOf))))
                    .accessibilityIdentifier("team.offline")
            }
            switch model.state {
            case .loading:
                DSSkeleton(rows: 4).accessibilityIdentifier("team.loading")
            case .content:
                rangeRow
                if model.isEmpty {
                    DSEmptyState(symbol: "person.2", title: L10n.vacTeamEmptyTitle, message: L10n.vacTeamEmptyMessage)
                        .accessibilityIdentifier("team.empty")
                } else {
                    ForEach(Array(model.weeks.enumerated()), id: \.element.id) { index, week in
                        weekSection(week, first: index == 0)
                    }
                }
            case .forbidden:
                DSEmptyState(symbol: "lock", title: L10n.vacTeamTitle, message: L10n.vacTeamForbidden)
                    .accessibilityIdentifier("team.forbidden")
            case let .error(code, correlationId):
                DSErrorState(
                    title: L10n.vacErrorTitle, message: L10n.vacErrorMessage, retryTitle: L10n.vacRetry,
                    correlationId: correlationId, code: code) { Task { await model.refresh() } }
                    .accessibilityIdentifier("team.error")
            }
        }
        .opacity(model.isReloading && !model.days.isEmpty ? 0.5 : 1)
        .sheet(isPresented: $isPickingRange) { RangeSheet(model: model) }
    }

    private var rangeRow: some View {
        DSGroupedSection {
            Button { isPickingRange = true } label: {
                DSListRow(
                    title: Text(verbatim: VacationFormat.range(model.start, model.end)),
                    leading: .icon(systemName: "calendar", tint: DSColor.tint), showsChevron: true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(L10n.vacTeamRangeTitle))
            .accessibilityValue(Text(verbatim: VacationFormat.range(model.start, model.end, long: true)))
            .accessibilityIdentifier("team.range")
        }
    }

    private func weekSection(_ week: TeamWeek, first: Bool) -> some View {
        let total = week.days.first?.total ?? 0
        let header = first ? L10n.vacTeamWeekTotal(week.number, total: total) : L10n.vacTeamWeek(week.number)
        return DSGroupedSection(header: header) {
            VStack(alignment: .leading, spacing: DSSpacing.s) {
                CoverageChips(days: week.days)
                if !week.absences.isEmpty {
                    Text(verbatim: week.absences.map { L10n.vacTeamAbsent(name: $0.name, status: $0.status) }
                        .joined(separator: " · "))
                        .font(DSFont.secondary).foregroundStyle(DSColor.ink2)
                        .accessibilityIdentifier("team.absent.\(week.id)")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DSSpacing.s)
        }
        .accessibilityIdentifier("team.week.\(week.id)")
    }
}

/// Weekday and present count per day; days with an absence are highlighted (mockup: orange).
struct CoverageChips: View {
    let days: [CoverageDay]
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 140 : 52), spacing: DSSpacing.xs)],
            spacing: DSSpacing.xs
        ) {
            ForEach(days) { day in
                let absent = !day.absent.isEmpty
                VStack(spacing: DSSpacing.xxs) {
                    Text(verbatim: VacationFormat.weekday(day.day)).font(DSFont.secondary)
                    Text(verbatim: "\(day.present)").font(DSFont.cardTitle)
                }
                .foregroundStyle(absent ? DSColor.orange : DSColor.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, DSSpacing.xs)
                .background(absent ? DSColor.orangeSoft : DSColor.fill, in: RoundedRectangle(cornerRadius: DSRadius.chip))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(L10n.vacTeamDay(VacationFormat.short(day.day), present: day.present, total: day.total)))
                .accessibilityIdentifier("team.day.\(day.day.iso)")
            }
        }
    }
}

private struct RangeSheet: View {
    let model: TeamCoverageModel
    @Environment(\.dismiss) private var dismiss
    @State private var start: Date
    @State private var end: Date

    init(model: TeamCoverageModel) {
        self.model = model
        _start = State(initialValue: model.start.date())
        _end = State(initialValue: model.end.date())
    }

    var body: some View {
        NavigationStack {
            Form {
                DatePicker(selection: $start, displayedComponents: .date) { Text(L10n.vacRequestStart) }
                    .accessibilityIdentifier("team.range.start")
                DatePicker(selection: $end, in: start..., displayedComponents: .date) { Text(L10n.vacRequestEnd) }
                    .accessibilityIdentifier("team.range.end")
            }
            .environment(\.calendar, .zurich)
            .environment(\.timeZone, Calendar.zurich.timeZone)
            .navigationTitle(Text(L10n.vacTeamRangeTitle))
            .vacInlineTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        let from = CalendarDay(date: start), to = CalendarDay(date: end)
                        dismiss()
                        Task { await model.setRange(start: from, end: to) }
                    } label: { Text(L10n.vacDone) }
                    .accessibilityIdentifier("team.range.done")
                }
            }
        }
        .presentationDetents([.medium])
    }
}
