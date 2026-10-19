import Core
import Foundation
import Observation

/// The manager's inbox (FR-VAC-004.1): requests waiting for the signed-in approver. Also the
/// source of the tab badge. Holds the T-VAC-APR flow that the decision screens report into.
@MainActor @Observable
public final class ManagerInboxModel {
    public enum State: Equatable {
        case loading
        case content([VacationRequestSummary])
        /// The API said `FORBIDDEN`: not a manager (the tab is hidden, this is the safety net).
        case forbidden
        case error(code: String?, correlationId: String?)
    }

    public private(set) var state: State = .loading
    /// Set while showing the last list because the network is gone: when it was fetched.
    public private(set) var offlineAsOf: Date?

    private let service: any VacationService
    private var access: VacationAccess
    private let makeFlow: @MainActor () -> TaskFlow
    private let now: @Sendable () -> Date
    private var flow: TaskFlow?

    init(
        service: any VacationService, access: VacationAccess,
        makeFlow: @escaping @MainActor () -> TaskFlow, now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.service = service
        self.access = access
        self.makeFlow = makeFlow
        self.now = now
        self.access.runId = { [weak self] in self?.flow?.taskRunId }
    }

    public convenience init(
        service: any VacationService,
        accessToken: @escaping @Sendable () async throws -> String,
        onReauthNeeded: @escaping @MainActor () -> Void,
        makeFlow: @escaping @MainActor () -> TaskFlow,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.init(
            service: service, access: VacationAccess(accessToken: accessToken, onReauthNeeded: onReauthNeeded),
            makeFlow: makeFlow, now: now)
    }

    public var isOffline: Bool { offlineAsOf != nil }

    public var items: [VacationRequestSummary] {
        if case let .content(items) = state { items } else { [] }
    }

    /// The number on the tab badge.
    public var count: Int { items.count }

    /// The flow decisions report into; a new one starts when the previous one finished.
    func currentFlow() -> TaskFlow? {
        if flow == nil || flow?.isFinished == true {
            flow = makeFlow()
            flow?.start()
        }
        return flow
    }

    /// The inbox was opened: `task_started` for T-VAC-APR, then load.
    public func begin() async {
        _ = currentFlow()
        await load()
    }

    public func refresh() async {
        flow?.tap()
        await load()
    }

    /// Badge refresh without touching the task flow.
    public func loadQuietly() async { await load() }

    private func load() async {
        do {
            let items = try await access.call { token in try await service.inbox(accessToken: token) }
            offlineAsOf = nil
            state = .content(items)
        } catch VacationError.forbidden {
            state = .forbidden
        } catch VacationError.offline {
            if case .content = state { offlineAsOf = offlineAsOf ?? now() } else {
                flow?.error(code: "OFFLINE", recovered: false)
                state = .error(code: "OFFLINE", correlationId: nil)
            }
        } catch let VacationError.failed(code, correlationId) {
            keepContentOr(.error(code: code, correlationId: correlationId))
        } catch let error as VacationError {
            keepContentOr(.error(code: error.code, correlationId: nil))
        } catch {
            keepContentOr(.error(code: nil, correlationId: nil))
        }
    }

    private func keepContentOr(_ fallback: State) {
        if case .content = state { return }
        state = fallback
    }
}
