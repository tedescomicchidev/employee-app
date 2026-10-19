import Core
import SwiftUI

/// Dates, Review and Success for FR-VAC-002 (CLASSIC). Switches on the model's phase.
struct RequestFlowView: View {
    let model: VacationRequestModel
    let dismiss: () -> Void

    private var isSubmitted: Bool {
        if case .submitted = model.phase { true } else { false }
    }

    var body: some View {
        NavigationStack {
            Group {
                switch model.phase {
                case .picking:
                    DatesView(model: model)
                case let .reviewing(proposal), let .submitting(proposal):
                    VacationReviewView(model: model, proposal: proposal)
                case let .blocked(review, violations):
                    BlockedReviewView(model: model, review: review, violations: violations)
                case let .submitted(request):
                    SubmittedView(request: request, done: dismiss)
                }
            }
            .background(DSColor.bg)
            .toolbar {
                if !isSubmitted {
                    ToolbarItem(placement: .cancellationAction) {
                        Button { dismiss() } label: { Text(L10n.cancel) }
                            .disabled(model.isBusy)
                            .accessibilityIdentifier("request.cancel")
                    }
                }
            }
        }
        .task { await model.begin() }
        .onDisappear { model.leave() }
    }
}

// MARK: Dates

private struct DatesView: View {
    let model: VacationRequestModel

    private var months: [CalendarDay] {
        (0..<13).map { offset in
            let first = CalendarDay(year: model.today.year, month: model.today.month, day: 1)
            let date = Calendar.zurich.date(byAdding: .month, value: offset, to: first.date()) ?? first.date()
            return CalendarDay(date: date)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: DSSpacing.m) {
                    summary
                    problems
                    if model.usesTextEntry { textEntry } else { calendar }
                }
                .padding(DSSpacing.gutter)
            }
            footer
        }
        .navigationTitle(Text(L10n.vacRequestTitle))
        .vacInlineTitle()
    }

    // The selected range and, once the API has checked it, the counted days.
    private var summary: some View {
        HStack(alignment: .center, spacing: DSSpacing.s) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.vacRequestPeriod).font(DSFont.secondary).foregroundStyle(DSColor.ink2)
                if let start = model.start, let end = model.end {
                    Text(verbatim: VacationFormat.range(start, end)).font(DSFont.cardTitle)
                } else {
                    Text(L10n.vacRequestNone).font(DSFont.body).foregroundStyle(DSColor.ink2)
                }
            }
            Spacer(minLength: DSSpacing.xs)
            switch model.check {
            case .checking:
                ProgressView().accessibilityLabel(Text(L10n.vacRequestChecking))
            case let .valid(proposal):
                DSStatusChip(.info, label: Text(L10n.vacWorkdays(proposal.review.countedDays)), symbol: "briefcase")
                    .accessibilityIdentifier("request.workdays")
            case let .violations(_, review?):
                DSStatusChip(.rejected, label: Text(L10n.vacWorkdays(review.countedDays)), symbol: "briefcase")
            default:
                EmptyView()
            }
        }
        .padding(DSSpacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DSColor.card, in: RoundedRectangle(cornerRadius: DSRadius.card))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("request.summary")
    }

    /// Reason codes inline, every failing code listed (FR-VAC-002.2); a short balance is explained on Review.
    @ViewBuilder private var problems: some View {
        switch model.check {
        case let .violations(violations, _) where !model.canContinue:
            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                ForEach(Array(violations.enumerated()), id: \.offset) { _, violation in
                    DSBanner(.error, message: Text(verbatim: L10n.vacRule(violation)))
                        .accessibilityIdentifier("request.violation.\(violation.code)")
                }
            }
        case .violations:
            EmptyView()
        case .cantonMissing:
            DSBanner(.error, message: Text(L10n.vacCantonMessage)).accessibilityIdentifier("request.canton_missing")
        case .noApprover:
            DSBanner(.error, message: Text(L10n.vacNoApprover)).accessibilityIdentifier("request.no_approver")
        case .offline:
            DSBanner(.offline, message: Text(L10n.vacRequestOffline)).accessibilityIdentifier("request.offline")
        case .failed:
            DSBanner(.error, message: Text(L10n.vacRequestFailed)).accessibilityIdentifier("request.failed")
        case .idle, .checking, .valid:
            EmptyView()
        }
        if case .failed = model.holidays {
            DSBanner(.info, message: Text(L10n.vacHolidaysFailed)).accessibilityIdentifier("request.holidays_failed")
        }
    }

    private var calendar: some View {
        VStack(alignment: .leading, spacing: DSSpacing.m) {
            HStack(spacing: DSSpacing.xs) {
                Circle().fill(DSColor.orange).frame(width: 8, height: 8).accessibilityHidden(true)
                Text(L10n.vacLegendHoliday).font(DSFont.caption).foregroundStyle(DSColor.ink2)
                if model.holidays == .loading {
                    Text(L10n.vacHolidaysLoading).font(DSFont.caption).foregroundStyle(DSColor.ink2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .accessibilityElement(children: .combine)
            LazyVStack(alignment: .leading, spacing: DSSpacing.l) {
                ForEach(months, id: \.iso) { month in
                    DSCalendarMonth(
                        month: month.date(), selection: selection,
                        holidays: model.holidayDays.map { $0.date() }, dimsWeekends: true,
                        calendar: .zurich
                    ) { model.select(CalendarDay(date: $0)) }
                }
            }
        }
        .accessibilityIdentifier("request.calendar")
    }

    private var selection: ClosedRange<Date>? {
        guard let start = model.start, let end = model.end, start <= end else { return nil }
        return start.date()...end.date()
    }

    /// Text-entry alternative to the calendar (A11Y-005).
    private var textEntry: some View {
        VStack(spacing: 0) {
            dateRow(L10n.vacRequestStart, id: "request.start", value: model.start ?? model.today) { day in
                model.setDates(start: day, end: model.end ?? day)
            }
            DSRowDivider()
            dateRow(L10n.vacRequestEnd, id: "request.end", value: model.end ?? model.today) { day in
                model.setDates(start: model.start ?? day, end: day)
            }
        }
        .background(DSColor.card, in: RoundedRectangle(cornerRadius: DSRadius.card))
    }

    private func dateRow(
        _ title: LocalizedStringResource, id: String, value: CalendarDay, set: @escaping (CalendarDay) -> Void
    ) -> some View {
        DatePicker(
            selection: Binding(get: { value.date() }, set: { set(CalendarDay(date: $0)) }),
            displayedComponents: .date
        ) {
            Text(title).font(DSFont.body)
        }
        .environment(\.calendar, .zurich)
        .environment(\.timeZone, Calendar.zurich.timeZone)
        .padding(.horizontal, DSSpacing.m)
        .padding(.vertical, DSSpacing.xs)
        .frame(minHeight: DSSize.rowMin)
        .accessibilityIdentifier(id)
    }

    private var footer: some View {
        VStack(spacing: DSSpacing.xs) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: DSSpacing.xxs) { footerNote }
                VStack(spacing: DSSpacing.xxs) { footerNote }
            }
            .font(DSFont.caption)
            .multilineTextAlignment(.center)
            DSButton(L10n.vacRequestContinue) { model.goToReview() }
                .disabled(!model.canContinue)
                .accessibilityIdentifier("request.continue")
        }
        .padding(DSSpacing.gutter)
        .background(DSColor.bg)
    }

    @ViewBuilder private var footerNote: some View {
        Text(L10n.vacRequestNote).foregroundStyle(DSColor.ink2)
        Button { model.toggleTextEntry() } label: {
            Text(model.usesTextEntry ? L10n.vacRequestCalendar : L10n.vacRequestEnter)
                .frame(minHeight: DSSize.touch)
        }
        .accessibilityIdentifier("request.toggle_entry")
    }
}

// MARK: Review

private struct ReviewCard: View {
    let start: CalendarDay
    let end: CalendarDay
    let review: VacationReview
    var countedIsProblem = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            block(L10n.vacRequestPeriod) {
                Text(verbatim: VacationFormat.range(start, end, long: true)).font(DSFont.body)
                    .accessibilityIdentifier("review.range")
            }
            DSRowDivider()
            block(L10n.vacReviewCounted) {
                Text(L10n.vacWorkdays(review.countedDays)).font(DSFont.cardTitle)
                    .foregroundStyle(countedIsProblem ? DSColor.red : DSColor.ink)
                    .accessibilityIdentifier("review.counted")
                if review.perYear.count > 1 {
                    Text(verbatim: review.perYear.sorted { $0.key < $1.key }
                        .map { "\($0.key): \(VacationFormat.days($0.value))" }.joined(separator: " · "))
                        .font(DSFont.secondary).foregroundStyle(DSColor.ink2)
                        .accessibilityIdentifier("review.peryear")
                }
            }
            DSRowDivider()
            block(L10n.vacReviewExcluded) { excluded }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DSColor.card, in: RoundedRectangle(cornerRadius: DSRadius.card))
    }

    private func block<Content: View>(
        _ title: LocalizedStringResource, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.xxs) {
            Text(title).font(DSFont.secondary).foregroundStyle(DSColor.ink2)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DSSpacing.m)
    }

    /// Weekends neutral, holidays named; every chip has text and an icon, never colour alone (A11Y-003).
    @ViewBuilder private var excluded: some View {
        if review.excluded.isEmpty {
            Text(L10n.vacReviewExcludedNone).font(DSFont.body).accessibilityIdentifier("review.excluded.none")
        } else {
            FlowLayout(spacing: DSSpacing.xs) {
                ForEach(review.excluded, id: \.day) { day in
                    switch day.kind {
                    case .weekend:
                        DSStatusChip(.neutral, label: Text(verbatim: VacationFormat.weekdayDay(day.day)), symbol: "moon.zzz")
                            .accessibilityLabel(Text(verbatim: "\(VacationFormat.short(day.day)), \(String(localized: L10n.vacReviewWeekend))"))
                    case .holiday:
                        let name = day.name ?? String(localized: L10n.vacReviewHoliday)
                        DSStatusChip(.pending, label: Text(verbatim: "\(VacationFormat.short(day.day)) · \(name)"), symbol: "calendar")
                            .accessibilityLabel(Text(verbatim: "\(VacationFormat.short(day.day)), \(String(localized: L10n.vacReviewHoliday)): \(name)"))
                            .accessibilityIdentifier("review.excluded.holiday")
                    }
                }
            }
            .accessibilityIdentifier("review.excluded")
        }
    }
}

private struct VacationReviewView: View {
    let model: VacationRequestModel
    let proposal: VacationProposal

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DSSpacing.m) {
                failureBanner
                Text(L10n.vacReviewSectionRequest).font(DSFont.sectionHeader).foregroundStyle(DSColor.ink2)
                    .padding(.leading, DSSpacing.xs).accessibilityAddTraits(.isHeader)
                ReviewCard(start: proposal.start, end: proposal.end, review: proposal.review)
                Text(L10n.vacReviewSectionBalance(proposal.review.balanceYear)).font(DSFont.sectionHeader)
                    .foregroundStyle(DSColor.ink2).padding(.leading, DSSpacing.xs).accessibilityAddTraits(.isHeader)
                balance
            }
            .padding(DSSpacing.gutter)
        }
        .safeAreaInset(edge: .bottom) { actions }
        .navigationTitle(Text(L10n.vacReviewTitle))
        .vacInlineTitle()
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button { model.backToPicking() } label: {
                    Label { Text(L10n.vacRequestPeriod) } icon: { Image(systemName: "chevron.backward") }
                }
                .disabled(model.isBusy)
                .accessibilityIdentifier("review.back")
            }
        }
    }

    private var balance: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                Text(L10n.vacReviewAfter).font(DSFont.secondary).foregroundStyle(DSColor.ink2)
                HStack(alignment: .firstTextBaseline, spacing: DSSpacing.xs) {
                    if let after = proposal.review.remainingAfter {
                        Text(verbatim: "\(after)").font(DSFont.cardTitle)
                        Text(L10n.vacDaysUnit(after)).font(DSFont.cardTitle)
                    }
                    Text(L10n.vacReviewBefore(proposal.review.remaining)).font(DSFont.body).foregroundStyle(DSColor.ink2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DSSpacing.m)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("review.balanceAfter")
            if let approver = proposal.review.approver {
                DSRowDivider()
                VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                    Text(L10n.vacReviewApprover).font(DSFont.secondary).foregroundStyle(DSColor.ink2)
                    Text(verbatim: approver).font(DSFont.body)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(DSSpacing.m)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("review.approver")
            }
        }
        .background(DSColor.card, in: RoundedRectangle(cornerRadius: DSRadius.card))
    }

    private var actions: some View {
        VStack(spacing: DSSpacing.xs) {
            DSButton(L10n.vacRequestButton, isBusy: model.isBusy) { Task { await model.submit() } }
                .disabled(model.failure == .offline)
                .accessibilityIdentifier("review.submit")
            if let approver = proposal.review.approver {
                Text(L10n.vacReviewHint(approver)).font(DSFont.caption).foregroundStyle(DSColor.ink2)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(DSSpacing.gutter)
        .background(DSColor.bg)
    }

    @ViewBuilder private var failureBanner: some View {
        switch model.failure {
        case .offline:
            DSBanner(.offline, message: Text(L10n.vacReviewOffline), actionTitle: L10n.vacRetry) {
                Task { await model.retry() }
            }
            .accessibilityIdentifier("review.offline")
        case .invalidConfirmation:
            DSBanner(.error, message: Text(L10n.vacReviewExpired)).accessibilityIdentifier("review.expired")
        case let .failed(code, correlationId):
            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                DSBanner(.error, message: Text(L10n.vacReviewFailed), actionTitle: L10n.vacRetry) {
                    Task { await model.retry() }
                }
                if code != nil || correlationId != nil {
                    DisclosureGroup {
                        Text(verbatim: [code, correlationId].compactMap { $0 }.joined(separator: " · "))
                            .font(DSFont.code).foregroundStyle(DSColor.ink2).textSelection(.enabled)
                    } label: { Text(L10n.annDetails).font(DSFont.secondary) }
                }
            }
            .accessibilityIdentifier("review.failed")
        case nil:
            EmptyView()
        }
    }
}

/// INSUFFICIENT_BALANCE: the review with the shortfall; nothing can be submitted (mockup #7).
private struct BlockedReviewView: View {
    let model: VacationRequestModel
    let review: VacationReview
    let violations: [VacationViolation]

    private var shortfall: Int? {
        guard let violation = violations.first, let requested = violation.requested, let remaining = violation.remaining
        else { return nil }
        return max(requested - remaining, 0)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DSSpacing.m) {
                ForEach(Array(violations.enumerated()), id: \.offset) { _, violation in
                    VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                        DSBanner(.error, message: Text(verbatim: L10n.vacRule(violation)))
                        Text(verbatim: violation.code).font(DSFont.code).foregroundStyle(DSColor.ink2)
                            .padding(.leading, DSSpacing.s)
                    }
                    .accessibilityIdentifier("review.violation.\(violation.code)")
                }
                Text(L10n.vacReviewSectionRequest).font(DSFont.sectionHeader).foregroundStyle(DSColor.ink2)
                    .padding(.leading, DSSpacing.xs).accessibilityAddTraits(.isHeader)
                if let start = model.start, let end = model.end {
                    ReviewCard(start: start, end: end, review: review, countedIsProblem: true)
                }
                VStack(alignment: .leading, spacing: 0) {
                    figure(L10n.vacReviewAvailable, L10n.vacDays(review.remaining), problem: false)
                    if let shortfall {
                        DSRowDivider()
                        figure(L10n.vacReviewMissing, L10n.vacDays(shortfall), problem: true)
                    }
                }
                .background(DSColor.card, in: RoundedRectangle(cornerRadius: DSRadius.card))
            }
            .padding(DSSpacing.gutter)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: DSSpacing.xs) {
                DSButton(L10n.vacRequestButton) {}
                    .disabled(true)
                    .accessibilityIdentifier("review.submit")
                DSButton(L10n.vacReviewChange, kind: .soft) { model.backToPicking() }
                    .accessibilityIdentifier("review.change")
            }
            .padding(DSSpacing.gutter)
            .background(DSColor.bg)
        }
        .navigationTitle(Text(L10n.vacReviewTitle))
        .vacInlineTitle()
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button { model.backToPicking() } label: {
                    Label { Text(L10n.vacRequestPeriod) } icon: { Image(systemName: "chevron.backward") }
                }
                .accessibilityIdentifier("review.back")
            }
        }
    }

    private func figure(_ title: LocalizedStringResource, _ value: LocalizedStringResource, problem: Bool) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.xxs) {
            Text(title).font(DSFont.secondary).foregroundStyle(DSColor.ink2)
            Text(value).font(DSFont.cardTitle).foregroundStyle(problem ? DSColor.red : DSColor.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DSSpacing.m)
        .accessibilityElement(children: .combine)
    }
}

// MARK: Success

private struct SubmittedView: View {
    let request: VacationRequestSummary
    let done: () -> Void
    @AccessibilityFocusState private var focused: Bool

    var body: some View {
        VStack(spacing: DSSpacing.l) {
            VStack(spacing: DSSpacing.xs) {
                DSEmptyState(
                    symbol: "checkmark.circle.fill", title: L10n.vacSuccessTitle,
                    message: L10n.vacSuccessDetail(request.approver))
                Text(verbatim: "\(VacationFormat.range(request.start, request.end, long: true)) · \(VacationFormat.days(request.countedDays))")
                    .font(DSFont.body).multilineTextAlignment(.center)
                    .accessibilityIdentifier("submitted.summary")
            }
            .accessibilityFocused($focused)
            .accessibilityIdentifier("submitted.title")
            DSButton(L10n.vacDone) { done() }
                .padding(.horizontal, DSSpacing.gutter)
                .accessibilityIdentifier("submitted.done")
        }
        .frame(maxHeight: .infinity)
        .onAppear {
            focused = true
            AccessibilityNotification.Announcement(String(localized: L10n.vacSuccessTitle)).post()
        }
        .navigationBarBackButtonHidden()
    }
}
