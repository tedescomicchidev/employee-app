import Core
import Foundation
import Observation

/// CLASSIC request flow for FR-VAC-002: pick dates, review, submit. `api/` validates every rule
/// (R4-R8) on each dry run; this sequences the calls, keeps the confirmation token across retries and
/// reports the flow (T-VAC-REQ).
@MainActor @Observable
public final class VacationRequestModel {
    /// What the date picker knows about the current selection.
    public enum Check: Equatable {
        case idle
        case checking
        case valid(VacationProposal)
        /// R5-R8 broke: every failing code, first by precedence, and what a blocked review still shows.
        case violations([VacationViolation], review: VacationReview?)
        case cantonMissing
        case noApprover
        case offline
        case failed
    }

    public enum Phase: Equatable {
        case picking
        case reviewing(VacationProposal)
        /// INSUFFICIENT_BALANCE only: the review is shown with the shortfall and no way to submit.
        case blocked(VacationReview, [VacationViolation])
        case submitting(VacationProposal)
        case submitted(VacationRequestSummary)
    }

    public enum Failure: Equatable {
        case offline
        case invalidConfirmation
        case failed(code: String?, correlationId: String?)
    }

    public enum HolidayList: Equatable {
        case loading
        case loaded([VacationHoliday])
        case failed
    }

    public private(set) var phase: Phase = .picking
    public private(set) var check: Check = .idle
    public private(set) var start: CalendarDay?
    public private(set) var end: CalendarDay?
    public private(set) var failure: Failure?
    public private(set) var holidays: HolidayList = .loading
    public var usesTextEntry = false
    public let today: CalendarDay

    private let service: any VacationService
    private let access: VacationAccess
    private let flow: TaskFlow
    /// Non-sensitive picks (the two dates) survive a re-sign-in or a closed sheet (FR-AUTH-005, NFR-007).
    private let drafts: DraftStore?
    private let draftKey: String
    private var selectingEnd = false
    /// Kept across retries so a replayed submit is idempotent (FR-VAC-002.4).
    private var confirmationToken: String?
    private var shownForProposal: String?
    private var checkTask: Task<Void, Never>?

    init(
        service: any VacationService, access: VacationAccess, flow: TaskFlow, today: CalendarDay,
        drafts: DraftStore? = nil, userKey: String = ""
    ) {
        self.service = service
        var access = access
        access.runId = { flow.taskRunId }
        self.access = access
        self.flow = flow
        self.today = today
        self.drafts = drafts
        self.draftKey = "vacation.request.\(userKey)"
    }

    public convenience init(
        service: any VacationService,
        accessToken: @escaping @Sendable () async throws -> String,
        onReauthNeeded: @escaping @MainActor () -> Void,
        flow: TaskFlow, today: CalendarDay, drafts: DraftStore? = nil, userKey: String = ""
    ) {
        self.init(
            service: service, access: VacationAccess(accessToken: accessToken, onReauthNeeded: onReauthNeeded),
            flow: flow, today: today, drafts: drafts, userKey: userKey)
    }

    public var isBusy: Bool {
        if case .submitting = phase { return true }
        return false
    }

    public var holidayDays: [CalendarDay] {
        if case let .loaded(items) = holidays { items.map(\.day) } else { [] }
    }

    /// "Continue" is possible when the API accepted the dates, or when only the balance is short
    /// (the review then shows the shortfall, as in the mockup).
    public var canContinue: Bool {
        switch check {
        case .valid: true
        case let .violations(violations, review): review != nil && violations.map(\.code) == ["INSUFFICIENT_BALANCE"]
        default: false
        }
    }

    // MARK: Picking

    public func begin() async {
        flow.start()
        if start == nil, let saved = await drafts?.draft(key: draftKey),
           let first = saved["start"].flatMap(CalendarDay.init(iso:)),
           let last = saved["end"].flatMap(CalendarDay.init(iso:)), first >= today, last >= first {
            start = first
            end = last
            validate()
        }
        await loadHolidays()
    }

    public func select(_ day: CalendarDay) {
        flow.tap()
        if selectingEnd, let first = start, day >= first {
            end = day
            selectingEnd = false
        } else {
            start = day
            end = day
            selectingEnd = true
        }
        persistDraft()
        validate()
    }

    /// Text-entry alternative to the calendar (A11Y-005).
    public func setDates(start newStart: CalendarDay, end newEnd: CalendarDay) {
        guard newStart != start || newEnd != end else { return }
        start = newStart
        end = newEnd
        selectingEnd = false
        persistDraft()
        validate()
    }

    public func toggleTextEntry() {
        flow.tap()
        usesTextEntry.toggle()
        if usesTextEntry, start == nil { setDates(start: today, end: today) }
    }

    private func persistDraft() {
        guard let drafts, let start, let end else { return }
        let key = draftKey, fields = ["start": start.iso, "end": end.iso]
        Task { await drafts.save(fields, key: key) }
    }

    private func loadHolidays() async {
        holidays = .loading
        let years = [today.year, today.year + 1]
        do {
            var all: [VacationHoliday] = []
            for year in years {
                let result = try await access.call { token in try await service.holidays(year: year, accessToken: token) }
                all += result.items
            }
            holidays = .loaded(all)
        } catch VacationError.cantonMissing {
            holidays = .loaded([])
            check = .cantonMissing
        } catch {
            holidays = .failed
        }
    }

    /// Dry run on the API; nothing is created (FR-VAC-002.2). Stale answers are dropped.
    private func validate() {
        checkTask?.cancel()
        guard let start, let end else {
            check = .idle
            return
        }
        confirmationToken = nil
        check = .checking
        checkTask = Task { [weak self] in await self?.runCheck(start, end) }
    }

    private func runCheck(_ start: CalendarDay, _ end: CalendarDay) async {
        do {
            let proposal = try await access.call { token in
                try await service.propose(start: start, end: end, accessToken: token)
            }
            guard !Task.isCancelled, start == self.start, end == self.end else { return }
            check = .valid(proposal)
        } catch let error as VacationError {
            guard !Task.isCancelled, start == self.start, end == self.end else { return }
            flow.error(code: error.code, recovered: false)
            switch error {
            case let .rules(violations, review): check = .violations(violations, review: review)
            case .cantonMissing: check = .cantonMissing
            case .noApprover: check = .noApprover
            case .offline: check = .offline
            default: check = .failed
            }
        } catch {
            guard !Task.isCancelled else { return }
            check = .failed
        }
    }

    /// Resolves when the dry run for the current selection has finished (tests and screenshots).
    func waitForCheck() async { await checkTask?.value }

    // MARK: Review and submit

    public func goToReview() {
        guard phase == .picking else { return }
        flow.tap()
        switch check {
        case let .valid(proposal):
            phase = .reviewing(proposal)
            if shownForProposal != proposal.id {
                shownForProposal = proposal.id
                flow.confirmShown()
            }
        case let .violations(violations, review?) where canContinue:
            phase = .blocked(review, violations)
        default:
            break
        }
    }

    /// "Request": the user's own tap mints the token, then the write runs with it (FR-AUTH-006).
    public func submit() async {
        guard case let .reviewing(proposal) = phase else { return }
        flow.tap()
        flow.confirmAccepted()
        await runSubmit(proposal)
    }

    /// Retry after a failed submit: same token if we have one, so the server replays instead of duplicating.
    public func retry() async {
        guard case let .reviewing(proposal) = phase else { return }
        flow.tap()
        await runSubmit(proposal)
    }

    public func backToPicking() {
        switch phase {
        case .reviewing:
            flow.tap()
            flow.confirmRejected()
        case .blocked:
            flow.tap()
        default:
            return
        }
        confirmationToken = nil
        failure = nil
        phase = .picking
    }

    /// Called when the flow screen goes away. Reports abandon unless the task completed.
    public func leave() {
        checkTask?.cancel()
        switch phase {
        case .submitted: break
        case .picking: flow.abandon(lastState: "dates")
        case .reviewing, .blocked, .submitting: flow.abandon(lastState: "review")
        }
    }

    private func runSubmit(_ proposal: VacationProposal) async {
        guard !isBusy else { return }
        failure = nil
        phase = .submitting(proposal)
        do {
            let request = try await access.call { token in
                let confirmation: String
                if let existing = confirmationToken {
                    confirmation = existing
                } else {
                    confirmation = try await service.confirm(proposal, accessToken: token)
                    confirmationToken = confirmation
                }
                return try await service.submit(
                    start: proposal.start, end: proposal.end, confirmationToken: confirmation, accessToken: token)
            }
            phase = .submitted(request)
            flow.complete(outcomeValid: true)
            await drafts?.remove(key: draftKey)
        } catch let error as VacationError {
            flow.error(code: error.code, recovered: false)
            switch error {
            case .offline:
                failure = .offline
                phase = .reviewing(proposal)
            case .invalidConfirmation:
                confirmationToken = nil
                failure = .invalidConfirmation
                phase = .reviewing(proposal)
            case let .rules(violations, review):
                // Something changed since the dry run (R5-R8 are checked again at write time): back to the dates.
                confirmationToken = nil
                check = .violations(violations, review: review)
                phase = .picking
            case .unauthenticated:
                phase = .reviewing(proposal)
            case let .failed(code, correlationId):
                failure = .failed(code: code, correlationId: correlationId)
                phase = .reviewing(proposal)
            default:
                failure = .failed(code: error.code, correlationId: nil)
                phase = .reviewing(proposal)
            }
        } catch {
            phase = .reviewing(proposal)
        }
    }
}
