import Core
import Foundation
import Observation

/// Request detail for the owner (FR-VAC-003): the request as the API has it, and the cancel of a
/// pending one behind a confirmation. The seed (from the list) keeps the screen useful offline,
/// with the actions disabled.
@MainActor @Observable
public final class RequestDetailModel {
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
    }

    public private(set) var state: State
    public private(set) var isOffline = false
    public private(set) var isCancelling = false
    public private(set) var notice: Notice?
    /// Drives the confirmation dialog.
    public var isConfirmingCancel = false

    private let id: String
    private let service: any VacationService
    private let access: VacationAccess
    /// The list behind this screen is stale after a write.
    private let onChanged: @MainActor () -> Void
    /// Kept after a failed attempt so a retry carries the same token (idempotent, FR-VAC-003.3).
    private var cancelToken: String?

    init(
        id: String, seed: VacationRequestSummary?, service: any VacationService, access: VacationAccess,
        onChanged: @escaping @MainActor () -> Void = {}
    ) {
        self.id = id
        self.onChanged = onChanged
        self.service = service
        self.access = access
        state = seed.map(State.content) ?? .loading
    }

    public convenience init(
        id: String, seed: VacationRequestSummary?, service: any VacationService,
        accessToken: @escaping @Sendable () async throws -> String,
        onReauthNeeded: @escaping @MainActor () -> Void,
        onChanged: @escaping @MainActor () -> Void = {}
    ) {
        self.init(
            id: id, seed: seed, service: service,
            access: VacationAccess(accessToken: accessToken, onReauthNeeded: onReauthNeeded), onChanged: onChanged)
    }

    public var request: VacationRequestSummary? {
        if case let .content(request) = state { request } else { nil }
    }

    /// Only a pending request can be cancelled (R11) and only with a connection (the API decides).
    public var canCancel: Bool {
        request?.status == .pending && !isOffline && !isCancelling
    }

    public func load() async {
        do {
            let fresh = try await access.call { [id] token in try await service.request(id: id, accessToken: token) }
            isOffline = false
            state = .content(fresh)
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
}
