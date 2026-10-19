import Core
import Foundation
import Observation

/// Request detail (FR-VAC-003, FR-VAC-004): the request as the API has it. The owner can cancel a
/// pending one; the assigned approver can approve or reject it, each behind a confirmation.
/// The seed (from the list) keeps the screen useful offline, with the actions disabled.
@MainActor @Observable
public final class RequestDetailModel {
    public enum Role: Equatable, Sendable { case owner, approver }

    public enum State: Equatable {
        case loading
        case content(VacationRequestSummary)
        case notFound
        case error(code: String?, correlationId: String?)
    }

    public enum Notice: Equatable {
        case cancelFailed
        case alreadyDecided
        case offline
        case decisionFailed
        case forbidden
        /// Approving would now break R5-R7; the request stays pending (FR-VAC-004.2).
        case blocked(VacationViolation)
        /// Shown after this approver's own decision succeeded.
        case decided(VacationStatus)
    }

    public static let maxReason = 500

    public let role: Role
    public private(set) var state: State
    public private(set) var isOffline = false
    public private(set) var isCancelling = false
    public private(set) var isDeciding = false
    public private(set) var notice: Notice?
    /// Team presence on the request's days, for the approver (FR-VAC-005.3); empty if unavailable.
    public private(set) var presence: [CoverageDay] = []
    /// Drives the confirmation dialogs and the reject sheet.
    public var isConfirmingCancel = false
    public var isConfirmingApprove = false
    public var isRejecting = false
    public var reason = ""

    private let id: String
    private let service: any VacationService
    private let access: VacationAccess
    /// The list behind this screen is stale after a write.
    private let onChanged: @MainActor () -> Void
    /// The approval task (T-VAC-APR) this decision belongs to, if the inbox started one.
    private let flow: @MainActor () -> TaskFlow?
    /// Kept after a failed attempt so a retry carries the same token (idempotent, FR-VAC-003.3, 004.3).
    private var cancelToken: String?
    private var decisionToken: (key: String, token: String)?
    private var rejectResolved = false

    init(
        id: String, role: Role = .owner, seed: VacationRequestSummary?, service: any VacationService,
        access: VacationAccess, flow: @escaping @MainActor () -> TaskFlow? = { nil },
        onChanged: @escaping @MainActor () -> Void = {}
    ) {
        self.id = id
        self.role = role
        self.onChanged = onChanged
        self.flow = flow
        self.service = service
        var access = access
        access.runId = { flow()?.activeRunId }
        self.access = access
        state = seed.map(State.content) ?? .loading
    }

    public convenience init(
        id: String, role: Role = .owner, seed: VacationRequestSummary?, service: any VacationService,
        accessToken: @escaping @Sendable () async throws -> String,
        onReauthNeeded: @escaping @MainActor () -> Void,
        flow: @escaping @MainActor () -> TaskFlow? = { nil },
        onChanged: @escaping @MainActor () -> Void = {}
    ) {
        self.init(
            id: id, role: role, seed: seed, service: service,
            access: VacationAccess(accessToken: accessToken, onReauthNeeded: onReauthNeeded), flow: flow,
            onChanged: onChanged)
    }

    public var request: VacationRequestSummary? {
        if case let .content(request) = state { request } else { nil }
    }

    /// Only a pending request can be cancelled (R11) and only with a connection (the API decides).
    public var canCancel: Bool {
        role == .owner && request?.status == .pending && !isOffline && !isCancelling
    }

    public var canDecide: Bool {
        role == .approver && request?.status == .pending && !isOffline && !isDeciding
    }

    public var reasonTooLong: Bool { reason.count > Self.maxReason }

    /// Other direct reports' absences on these days, each request once, without this request.
    public var otherAbsences: [CoverageAbsence] {
        var seen = Set<String>([id])
        return presence.flatMap(\.absent).filter { seen.insert($0.requestId).inserted }
    }

    public func load() async {
        do {
            let fresh = try await access.call { [id] token in try await service.request(id: id, accessToken: token) }
            isOffline = false
            state = .content(fresh)
            if role == .approver { await loadPresence(fresh) }
        } catch VacationError.notFound {
            state = .notFound
        } catch VacationError.offline {
            isOffline = true
            if case .loading = state { state = .error(code: "OFFLINE", correlationId: nil) }
        } catch let VacationError.failed(code, correlationId) {
            if case .content = state { return }
            state = .error(code: code, correlationId: correlationId)
        } catch let error as VacationError {
            if case .content = state { return }
            state = .error(code: error.code, correlationId: nil)
        } catch {
            if case .content = state { return }
            state = .error(code: nil, correlationId: nil)
        }
    }

    /// Same data as the team view (FR-VAC-005.3). It is context, not part of the decision: a failure
    /// just leaves the strip out.
    private func loadPresence(_ request: VacationRequestSummary) async {
        presence = (try? await access.call { token in
            try await service.coverage(start: request.start, end: request.end, accessToken: token)
        }) ?? []
    }

    // MARK: Cancel (owner, FR-VAC-003)

    public func askToCancel() {
        guard canCancel else { return }
        notice = nil
        isConfirmingCancel = true
    }

    /// The user confirmed in the dialog: mint the token once, then cancel (idempotent on it).
    public func confirmCancel() async {
        guard canCancel else { return }
        isCancelling = true
        notice = nil
        defer { isCancelling = false }
        do {
            let updated = try await access.call { [id] token in
                let confirmation: String
                if let kept = cancelToken {
                    confirmation = kept
                } else {
                    confirmation = try await service.confirmCancel(id: id, accessToken: token)
                    cancelToken = confirmation
                }
                return try await service.cancel(id: id, confirmationToken: confirmation, accessToken: token)
            }
            cancelToken = nil
            state = .content(updated)
            onChanged()
        } catch VacationError.invalidState {
            cancelToken = nil
            notice = .alreadyDecided
            await load()
        } catch VacationError.notFound {
            state = .notFound
        } catch VacationError.offline {
            notice = .offline
        } catch {
            notice = .cancelFailed
        }
    }

    // MARK: Decide (approver, FR-VAC-004)

    /// Approve needs one confirmation; the dialog is the review.
    public func askToApprove() {
        guard canDecide else { return }
        notice = nil
        flow()?.tap()
        flow()?.confirmShown()
        isConfirmingApprove = true
    }

    public func dismissApprove() {
        flow()?.confirmRejected()
        isConfirmingApprove = false
    }

    public func confirmApprove() async {
        isConfirmingApprove = false
        flow()?.confirmAccepted()
        await perform(.approve, reason: nil)
    }

    /// Reject collects an optional reason (<= 500) in a sheet; "Reject" there is the confirmation.
    public func askToReject() {
        guard canDecide else { return }
        notice = nil
        reason = ""
        rejectResolved = false
        flow()?.tap()
        flow()?.confirmShown()
        isRejecting = true
    }

    /// Cancel or swipe-down on the reject sheet.
    public func dismissReject() {
        isRejecting = false
        guard !rejectResolved else { return }
        rejectResolved = true
        flow()?.confirmRejected()
    }

    public func confirmReject() async {
        guard !reasonTooLong else { return }
        rejectResolved = true
        isRejecting = false
        flow()?.confirmAccepted()
        let text = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        await perform(.reject, reason: text.isEmpty ? nil : text)
    }

    private func perform(_ decision: VacationDecision, reason: String?) async {
        guard canDecide else { return }
        isDeciding = true
        notice = nil
        defer { isDeciding = false }
        let key = "\(decision.rawValue)|\(reason ?? "")"
        do {
            let updated = try await access.call { [id] token in
                let confirmation: String
                if let kept = decisionToken, kept.key == key {
                    confirmation = kept.token
                } else {
                    confirmation = try await service.confirmDecision(
                        id: id, decision: decision, reason: reason, accessToken: token)
                    decisionToken = (key, confirmation)
                }
                return try await service.decide(
                    id: id, decision: decision, reason: reason, confirmationToken: confirmation, accessToken: token)
            }
            decisionToken = nil
            state = .content(updated)
            notice = .decided(updated.status)
            flow()?.complete(outcomeValid: true)
            onChanged()
        } catch let error as VacationError {
            await handle(error)
        } catch {
            flow()?.error(code: "UNKNOWN", recovered: false)
            notice = .decisionFailed
        }
    }

    private func handle(_ error: VacationError) async {
        switch error {
        case .invalidState:
            decisionToken = nil
            flow()?.error(code: error.code, recovered: false)
            notice = .alreadyDecided
            await load()
            onChanged()
        case let .rules(violations, _):
            decisionToken = nil
            flow()?.error(code: error.code, recovered: false)
            if let first = violations.first { notice = .blocked(first) } else { notice = .decisionFailed }
        case .offline:
            flow()?.error(code: error.code, recovered: true)
            notice = .offline
        case .forbidden, .selfApproval:
            flow()?.error(code: error.code, recovered: false)
            notice = .forbidden
        case .notFound:
            flow()?.error(code: error.code, recovered: false)
            state = .notFound
        default:
            flow()?.error(code: error.code, recovered: false)
            notice = .decisionFailed
        }
    }
}
