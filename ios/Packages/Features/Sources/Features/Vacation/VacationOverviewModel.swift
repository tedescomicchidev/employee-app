import Core
import Foundation
import Observation

/// CLASSIC overview for FR-VAC-001. Every number is the API's (R1-R3); this keeps the last good
/// response for offline display and reports the balance flow (T-VAC-BAL).
@MainActor @Observable
public final class VacationOverviewModel {
    public enum State: Equatable {
        case loading
        case content(VacationBalance, requests: [VacationRequestSummary])
        case notProvisioned
        case error(code: String?, correlationId: String?)
    }

    public private(set) var state: State = .loading
    /// Set while showing the cached overview because the network is gone: when it was fetched.
    public private(set) var offlineAsOf: Date?

    private let service: any VacationService
    private var access: VacationAccess
    private let cache: VacationCache
    private let userKey: String
    private let makeFlow: @MainActor () -> TaskFlow
    private let now: @Sendable () -> Date
    private var flow: TaskFlow?

    init(
        service: any VacationService, access: VacationAccess, cache: VacationCache, userKey: String,
        makeFlow: @escaping @MainActor () -> TaskFlow, now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.service = service
        self.access = access
        self.cache = cache
        self.userKey = userKey
        self.makeFlow = makeFlow
        self.now = now
        self.access.runId = { [weak self] in self?.flow?.taskRunId }
    }

    public convenience init(
        service: any VacationService,
        accessToken: @escaping @Sendable () async throws -> String,
        onReauthNeeded: @escaping @MainActor () -> Void,
        cache: VacationCache, userKey: String,
        makeFlow: @escaping @MainActor () -> TaskFlow,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.init(
            service: service, access: VacationAccess(accessToken: accessToken, onReauthNeeded: onReauthNeeded),
            cache: cache, userKey: userKey, makeFlow: makeFlow, now: now)
    }

    public var isOffline: Bool { offlineAsOf != nil }
    /// The request button needs the network: the API is the only place a request can be validated.
    public var canRequest: Bool {
        if case .content = state { !isOffline } else { false }
    }

    public var balance: VacationBalance? {
        if case let .content(balance, _) = state { balance } else { nil }
    }

    public var requests: [VacationRequestSummary] {
        if case let .content(_, requests) = state { requests } else { [] }
    }

    /// The next request that has not ended yet and still counts (pending or approved).
    public func next(today: CalendarDay) -> VacationRequestSummary? {
        requests.filter { ($0.status == .pending || $0.status == .approved) && $0.end >= today }
            .min { $0.start < $1.start }
    }

    // MARK: Loading

    /// Starts (or restarts, after a finished view) the T-VAC-BAL flow when the overview is opened.
    public func begin() async {
        if flow == nil || flow?.isFinished == true {
            flow = makeFlow()
            flow?.start()
        }
        await load()
    }

    public func refresh() async {
        flow?.tap()
        await load()
    }

    private func load() async {
        if case .content = state {} else { state = .loading }
        do {
            let (balance, requests) = try await access.call { token in
                async let balance = service.balance(accessToken: token)
                async let requests = service.requests(accessToken: token)
                return try await (balance, requests)
            }
            offlineAsOf = nil
            state = .content(balance, requests: requests)
            await cache.save(VacationSnapshot(userKey: userKey, fetchedAt: now(), balance: balance, requests: requests))
            // The five numbers are on screen and came from the API in this very load.
            flow?.complete(outcomeValid: true)
        } catch let error as VacationError {
            flow?.error(code: error.code, recovered: error == .offline)
            await show(error)
        } catch {
            await show(.failed(code: nil, correlationId: nil))
        }
    }

    /// Last good overview with its as-of time when the network is gone; an error state when there is none.
    private func show(_ error: VacationError) async {
        switch error {
        case .offline:
            if let snapshot = await cache.load(userKey: userKey) {
                offlineAsOf = snapshot.fetchedAt
                state = .content(snapshot.balance, requests: snapshot.requests)
            } else if case .content = state {
                offlineAsOf = offlineAsOf ?? now()
            } else {
                state = .error(code: "OFFLINE", correlationId: nil)
            }
        case .notProvisioned:
            state = .notProvisioned
        case let .failed(code, correlationId):
            keepContentOr(.error(code: code, correlationId: correlationId))
        default:
            keepContentOr(.error(code: error.code, correlationId: nil))
        }
    }

    private func keepContentOr(_ fallback: State) {
        if case .content = state { return }
        offlineAsOf = nil
        state = fallback
    }
}
