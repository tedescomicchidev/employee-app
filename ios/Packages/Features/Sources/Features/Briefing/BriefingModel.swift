import Core
import Foundation
import Observation

/// CLASSIC briefing screen (FR-BRF-001/002/003/005; T-BRF-VIEW). Every event, conflict and free block is
/// `api/`'s answer to the user's own delegated token; this holds it in memory for the screen only: nothing
/// is cached or written to disk (PRIV-003), so a stale calendar can never be shown offline.
@MainActor @Observable
public final class BriefingModel {
    public enum OptInPhase: Equatable, Sendable {
        case ready
        /// The tap on "Turn on" is in flight: propose, confirm, write.
        case working
        case failed(code: String?)
        case offline
    }

    /// FR-BRF-005.1: one specific, actionable message per cause, and never any briefing content.
    public enum Problem: Equatable, Sendable {
        case unavailable, noLicence, consentRequired, offline, timedOut, signedOut, stopped, notProvisioned
        case failed(code: String?, correlationId: String?)

        public var code: String {
            switch self {
            case .unavailable: "WORKIQ_UNAVAILABLE"
            case .noLicence: "NO_LICENCE"
            case .consentRequired: "CONSENT_REQUIRED"
            case .offline: "OFFLINE"
            case .timedOut: "TIMEOUT"
            case .signedOut: "UNAUTHENTICATED"
            case .stopped: "STOPPED"
            case .notProvisioned: "NOT_PROVISIONED"
            case let .failed(code, _): code ?? "UNKNOWN"
            }
        }
    }

    public enum State: Equatable, Sendable {
        /// Asking `api/` whether the briefing is on. No Work IQ call happens before the answer.
        case checking
        case optIn(OptInPhase)
        /// Work IQ is reading the calendar (40-60 s). `stillWorking` appears after a few seconds.
        case reading(stillWorking: Bool)
        case content(BriefingWeek)
        case problem(Problem)
    }

    public enum ReminderOffer: Equatable, Sendable {
        /// Right after opt-in: ask, in context, whether to remind on Monday at 07:00.
        case ask
        case none
    }

    public private(set) var state: State = .checking
    public private(set) var reminderOffer: ReminderOffer = .none
    /// Whether the weekly reminder is pending in the system (shown on the week screen).
    public private(set) var reminderScheduled = false
    /// "Not now" on the opt-in screen: the briefing stays off and the tab says so, quietly.
    public private(set) var declined = false

    private let service: any BriefingService
    private var access: BriefingAccess
    private let reminder: BriefingReminder
    private let reminderTitle: @Sendable () -> String
    private let makeFlow: (@MainActor () -> TaskFlow)?
    private let stillWorkingAfter: Duration
    private var flow: TaskFlow?
    private var readTask: Task<Void, Never>?
    private var slowTask: Task<Void, Never>?
    private var optInShown = false

    init(
        service: any BriefingService, access: BriefingAccess, reminder: BriefingReminder,
        reminderTitle: @escaping @Sendable () -> String,
        makeFlow: (@MainActor () -> TaskFlow)?, stillWorkingAfter: Duration = .seconds(8)
    ) {
        self.service = service
        self.access = access
        self.reminder = reminder
        self.reminderTitle = reminderTitle
        self.makeFlow = makeFlow
        self.stillWorkingAfter = stillWorkingAfter
        self.access.runId = { [weak self] in self?.flow?.activeRunId }
    }

    public convenience init(
        service: any BriefingService,
        accessToken: @escaping @Sendable () async throws -> String,
        onReauthNeeded: @escaping @MainActor () -> Void,
        reminder: BriefingReminder,
        reminderTitle: @escaping @Sendable () -> String,
        makeFlow: (@MainActor () -> TaskFlow)?,
        stillWorkingAfter: Duration = .seconds(8)
    ) {
        self.init(
            service: service, access: BriefingAccess(accessToken: accessToken, onReauthNeeded: onReauthNeeded),
            reminder: reminder, reminderTitle: reminderTitle, makeFlow: makeFlow,
            stillWorkingAfter: stillWorkingAfter)
    }

    public var week: BriefingWeek? {
        if case let .content(week) = state { week } else { nil }
    }

    public var isReading: Bool {
        if case .reading = state { true } else { false }
    }

    // MARK: Loading

    /// Opens the screen: starts the T-BRF-VIEW flow (once per visit), then asks whether the briefing is on.
    public func begin() async {
        if flow == nil || flow?.isFinished == true {
            flow = makeFlow?()
            flow?.start()
        }
        await load()
    }

    /// Pull to refresh, retry, and the tap on the Monday notification: always generated at that moment.
    public func refresh() async {
        flow?.tap()
        await load()
    }

    private func load() async {
        cancelReading()
        if week == nil { state = .checking }
        do {
            let status = try await access.call { token in try await service.status(accessToken: token) }
            if status.optedIn {
                await syncReminder(optedIn: true)
                await read()
            } else {
                await syncReminder(optedIn: false)
                showOptIn(.ready)
            }
        } catch {
            fail(error)
        }
    }

    /// One read of the week. Cancellable: "Stop" ends the wait, the user can try again.
    private func read() async {
        state = .reading(stillWorking: false)
        slowTask = Task { [weak self, stillWorkingAfter] in
            try? await Task.sleep(for: stillWorkingAfter)
            guard !Task.isCancelled else { return }
            self?.markStillWorking()
        }
        let task = Task { [weak self] in
            guard let self else { return }
            do {
                let week = try await access.call { token in try await service.week(accessToken: token) }
                guard !Task.isCancelled else { return }
                slowTask?.cancel()
                state = .content(week)
                // Content, an empty week and a partial week are all outcomes Work IQ delivered (metrics.md).
                flow?.complete(outcomeValid: true)
            } catch {
                guard !Task.isCancelled, !(error is CancellationError) else { return }
                slowTask?.cancel()
                fail(error)
            }
        }
        readTask = task
        await task.value
    }

    private func markStillWorking() {
        if case .reading = state { state = .reading(stillWorking: true) }
    }

    /// "Stop" while Work IQ is working.
    public func stopReading() {
        guard isReading else { return }
        cancelReading()
        state = .problem(.stopped)
    }

    private func cancelReading() {
        readTask?.cancel()
        slowTask?.cancel()
        readTask = nil
        slowTask = nil
    }

    private func fail(_ error: Error) {
        let briefingError = (error as? BriefingError) ?? .failed(code: nil, correlationId: nil)
        switch briefingError {
        case .notOptedIn:
            showOptIn(.ready)  // turned off elsewhere: back to the opt-in screen, no error
            return
        case .offline: state = .problem(.offline)
        case .unauthenticated: state = .problem(.signedOut)
        case .workIQUnavailable: state = .problem(.unavailable)
        case .noLicence: state = .problem(.noLicence)
        case .consentRequired: state = .problem(.consentRequired)
        case .timedOut: state = .problem(.timedOut)
        case .notProvisioned: state = .problem(.notProvisioned)
        case let .failed(code, correlationId): state = .problem(.failed(code: code, correlationId: correlationId))
        case .invalidConfirmation: state = .problem(.failed(code: briefingError.code, correlationId: nil))
        }
        flow?.error(code: briefingError.code, recovered: briefingError == .offline)
    }

    private func showOptIn(_ phase: OptInPhase) {
        state = .optIn(phase)
        if !optInShown {
            optInShown = true
            flow?.confirmShown()  // the opt-in screen is the review screen of this write
        }
    }

    // MARK: Opt-in (FR-BRF-001)

    /// The tap on "Turn on": the explicit action that names what is accessed. It asks `api/` for a
    /// proposal, mints the confirmation token from this tap, and only then turns the briefing on.
    public func turnOn() async {
        guard case .optIn = state, state != .optIn(.working) else { return }
        flow?.tap()
        flow?.confirmAccepted()
        state = .optIn(.working)
        do {
            try await access.call { token in
                let proposal = try await service.proposeOptIn(enabled: true, accessToken: token)
                let confirmation = try await service.confirmOptIn(proposal, accessToken: token)
                _ = try await service.setOptIn(enabled: true, confirmationToken: confirmation, accessToken: token)
            }
            declined = false
            let authorization = await reminder.authorization()
            reminderOffer = authorization == .notDetermined ? .ask : .none  // asked once, in context
            if reminderOffer == .none { await syncReminder(optedIn: true) }
            optInShown = false
            if reminderOffer == .none { await read() } else { state = .optIn(.ready) }
        } catch BriefingError.offline {
            state = .optIn(.offline)
        } catch let error as BriefingError {
            state = .optIn(.failed(code: error.code))
            flow?.error(code: error.code, recovered: false)
        } catch {
            state = .optIn(.failed(code: nil))
        }
    }

    public func notNow() {
        flow?.confirmRejected()
        flow?.abandon(lastState: "opt_in")
        declined = true
    }

    /// Back from "Not now" to the opt-in screen.
    public func reconsider() { declined = false }

    /// "Remind me on Mondays": the in-context ask, then the first read of the week.
    public func allowReminder() async {
        flow?.tap()
        if await reminder.requestAuthorization() { await syncReminder(optedIn: true) }
        reminderOffer = .none
        await read()
    }

    public func skipReminder() async {
        flow?.tap()
        reminderOffer = .none
        await read()
    }

    /// Keeps the Monday reminder in step with the opt-in: scheduled when on and allowed, removed when off.
    private func syncReminder(optedIn: Bool) async {
        if optedIn {
            reminderScheduled = await reminder.schedule(title: reminderTitle())
        } else {
            await reminder.cancel()
            reminderScheduled = false
        }
    }

    /// The screen is gone: an unfinished flow is abandoned, and a read in flight stops.
    public func end() {
        cancelReading()
        if flow?.isFinished == false { flow?.abandon(lastState: stateLabel) }
    }

    private var stateLabel: String {
        switch state {
        case .checking: "checking"
        case .optIn: "opt_in"
        case .reading: "reading"
        case .content: "content"
        case .problem: "problem"
        }
    }
}
