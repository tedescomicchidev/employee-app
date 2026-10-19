import Core
import Foundation
import Observation

/// CLASSIC feed and detail for FR-ANN-003. The API decides who sees what; this keeps the last
/// good list for offline display and reports the read flow (T-ANN-READ).
@MainActor @Observable
public final class FeedModel {
    public enum State: Equatable {
        case loading
        case empty
        case content([AnnouncementItem])
        case error(code: String?, correlationId: String?)
    }

    public private(set) var state: State = .loading
    /// Set while showing the cached list because the network is gone: when it was fetched.
    public private(set) var offlineAsOf: Date?
    /// NOT_FOUND on open: withdrawn, or never addressed to this user. Shown as "no longer available".
    public private(set) var unavailable: Set<String> = []

    private let service: any AnnouncementService
    private let accessToken: @Sendable () async throws -> String
    private let onReauthNeeded: @MainActor () -> Void
    private let cache: FeedCache
    private let userKey: String
    private let makeFlow: @MainActor () -> TaskFlow
    private let now: @Sendable () -> Date
    private var flow: TaskFlow?

    public init(
        service: any AnnouncementService,
        accessToken: @escaping @Sendable () async throws -> String,
        onReauthNeeded: @escaping @MainActor () -> Void,
        cache: FeedCache, userKey: String,
        makeFlow: @escaping @MainActor () -> TaskFlow,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.service = service
        self.accessToken = accessToken
        self.onReauthNeeded = onReauthNeeded
        self.cache = cache
        self.userKey = userKey
        self.makeFlow = makeFlow
        self.now = now
    }

    public var items: [AnnouncementItem] {
        if case let .content(items) = state { items } else { [] }
    }

    public var unreadCount: Int { items.filter { !$0.read }.count }
    public var isOffline: Bool { offlineAsOf != nil }

    public func item(id: String) -> AnnouncementItem? { items.first { $0.id == id } }

    // MARK: Loading

    /// Starts (or restarts, after a finished read) the T-ANN-READ flow when the feed is opened.
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
        let token: String
        do {
            token = try await accessToken()
        } catch AuthError.interactionRequired {
            onReauthNeeded()
            await showCachedOr(.error(code: "UNAUTHENTICATED", correlationId: nil), offline: false)
            return
        } catch AuthError.offline {
            await showCachedOr(.error(code: "OFFLINE", correlationId: nil), offline: true)
            return
        } catch {
            await showCachedOr(.error(code: "AUTH", correlationId: nil), offline: false)
            return
        }
        do {
            let fetched = try await TaskRun.$current.withValue(flow?.taskRunId) {
                try await service.list(accessToken: token)
            }
            offlineAsOf = nil
            unavailable = []
            state = fetched.isEmpty ? .empty : .content(fetched)
            await cache.save(FeedSnapshot(userKey: userKey, fetchedAt: now(), items: fetched))
        } catch let error as AnnouncementError {
            flow?.error(code: error.code, recovered: false)
            switch error {
            case .offline:
                await showCachedOr(.error(code: "OFFLINE", correlationId: nil), offline: true)
            case .unauthenticated:
                onReauthNeeded()
                await showCachedOr(.error(code: error.code, correlationId: nil), offline: false)
            case let .failed(code, correlationId):
                await showCachedOr(.error(code: code, correlationId: correlationId), offline: false)
            default:
                await showCachedOr(.error(code: error.code, correlationId: nil), offline: false)
            }
        } catch {
            await showCachedOr(.error(code: nil, correlationId: nil), offline: false)
        }
    }

    /// Last good list with its as-of time when the network is gone; an error state when there is none.
    /// Other failures keep what is on screen (items stay readable) and fall back to the error state otherwise.
    private func showCachedOr(_ fallback: State, offline: Bool) async {
        if offline, let snapshot = await cache.load(userKey: userKey) {
            offlineAsOf = snapshot.fetchedAt
            state = snapshot.items.isEmpty ? .empty : .content(snapshot.items)
            return
        }
        if case .content = state { return }
        offlineAsOf = nil
        state = fallback
    }

    // MARK: Reading

    /// Opening an announcement marks it read for this user only (FR-ANN-003.2). The local flag changes
    /// only after the API confirmed it, so the feed never claims a read the server does not know.
    public func open(id: String) async {
        flow?.tap()
        let token: String
        do { token = try await accessToken() } catch {
            if case AuthError.interactionRequired = error { onReauthNeeded() }
            return
        }
        do {
            try await TaskRun.$current.withValue(flow?.taskRunId) {
                try await service.markRead(id: id, accessToken: token)
            }
            markLocallyRead(id)
            flow?.complete(outcomeValid: true)
        } catch AnnouncementError.notFound {
            unavailable.insert(id)
            flow?.error(code: "NOT_FOUND", recovered: false)
        } catch AnnouncementError.unauthenticated {
            onReauthNeeded()
        } catch let error as AnnouncementError {
            // Offline or a server hiccup: the text stays readable, read state is not claimed.
            flow?.error(code: error.code, recovered: true)
        } catch {}
    }

    private func markLocallyRead(_ id: String) {
        guard case var .content(items) = state, let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].read = true
        state = .content(items)
        let snapshot = FeedSnapshot(userKey: userKey, fetchedAt: offlineAsOf ?? now(), items: items)
        let cache = cache
        Task { await cache.save(snapshot) }
    }
}
