import Core
import Foundation
import Testing
@testable import Features

#if DEBUG
private actor FeedService: AnnouncementService {
    var items: [AnnouncementItem]
    var listError: AnnouncementError?
    var readError: AnnouncementError?
    var readCalls: [String] = []

    init(items: [AnnouncementItem]) { self.items = items }

    func fail(list error: AnnouncementError?) { listError = error }
    func fail(read error: AnnouncementError?) { readError = error }

    func list(accessToken: String) throws -> [AnnouncementItem] {
        if let listError { throw listError }
        return items
    }

    func markRead(id: String, accessToken: String) throws {
        readCalls.append(id)
        if let readError { throw readError }
    }

    func propose(_ draft: AnnouncementDraft, accessToken: String) throws -> AnnouncementProposal {
        throw AnnouncementError.failed(code: nil, correlationId: nil)
    }
    func confirm(_ proposal: AnnouncementProposal, accessToken: String) throws -> String { "" }
    func publish(_ draft: AnnouncementDraft, confirmationToken: String, accessToken: String) throws
        -> PublishedAnnouncement { throw AnnouncementError.failed(code: nil, correlationId: nil) }
    func audienceOptions(accessToken: String) throws -> AudienceOptions {
        AudienceOptions(regions: [], stores: [], roles: [])
    }
    func recipientCount(for audience: AudienceSelection, accessToken: String) throws -> Int { 0 }
}

private let fetched = Date(timeIntervalSince1970: 1_800_000_000)

private func item(_ id: String, read: Bool = false) -> AnnouncementItem {
    AnnouncementItem(
        id: id, title: "T\(id)", body: "B\(id)", language: .it, author: "A",
        publishedAt: fetched, read: read)
}

@MainActor
private func make(
    _ service: FeedService, cache: FeedCache = FeedCache(), sink: MemoryEventSink = MemoryEventSink(),
    reauth: @escaping @MainActor () -> Void = {}
) -> FeedModel {
    let context = TaskContext(participantId: UUID())
    return FeedModel(
        service: service, accessToken: { "bearer" }, onReauthNeeded: reauth, cache: cache, userKey: "u1",
        makeFlow: { TaskFlow(taskId: "T-ANN-READ", feature: "ann", mode: .classic, context: context, sink: sink) },
        now: { fetched })
}

@MainActor
@Suite("FR-ANN-003 feed")
struct FeedModelTests {
    @Test("FR-ANN-003.1: shows what the API returned, in the API's order, with the unread count")
    func loadsItems() async {
        let model = make(FeedService(items: [item("2"), item("1", read: true)]))
        await model.begin()
        #expect(model.items.map(\.id) == ["2", "1"])
        #expect(model.unreadCount == 1)
        #expect(model.items.first?.language == .it)
    }

    @Test("FR-ANN-003.3: no announcements is the empty state")
    func empty() async {
        let model = make(FeedService(items: []))
        await model.begin()
        #expect(model.state == .empty)
    }

    @Test("FR-ANN-003.3: a server error is the error state with code and correlation id, not an empty list")
    func error() async {
        let service = FeedService(items: [])
        await service.fail(list: .failed(code: "INTERNAL", correlationId: "c-1"))
        let model = make(service)
        await model.begin()
        #expect(model.state == .error(code: "INTERNAL", correlationId: "c-1"))
    }

    @Test("FR-ANN-003.3 / NFR-007: offline shows the last fetched list with its as-of time")
    func offlineUsesCache() async {
        let cache = FeedCache()
        let service = FeedService(items: [item("1")])
        let online = make(service, cache: cache)
        await online.begin()
        await service.fail(list: .offline)
        let model = make(service, cache: cache)
        await model.begin()
        #expect(model.items.map(\.id) == ["1"])
        #expect(model.offlineAsOf == fetched)
        await service.fail(list: nil)
        await model.refresh()
        #expect(model.offlineAsOf == nil)
    }

    @Test("FR-ANN-003.3: offline with nothing cached is an error state, never an empty feed")
    func offlineWithoutCache() async {
        let service = FeedService(items: [item("1")])
        await service.fail(list: .offline)
        let model = make(service)
        await model.begin()
        #expect(model.state == .error(code: "OFFLINE", correlationId: nil))
    }

    @Test("FR-ANN-003.3: another user's cached feed is never shown")
    func cacheIsPerUser() async {
        let cache = FeedCache()
        await cache.save(FeedSnapshot(userKey: "someone-else", fetchedAt: fetched, items: [item("x")]))
        let service = FeedService(items: [])
        await service.fail(list: .offline)
        let model = make(service, cache: cache)
        await model.begin()
        #expect(model.items.isEmpty)
    }

    @Test("FR-AUTH-005: sign-out clears the cached feed")
    func clearRemovesSnapshot() async {
        let cache = FeedCache()
        await cache.save(FeedSnapshot(userKey: "u1", fetchedAt: fetched, items: [item("1")]))
        await cache.clear()
        #expect(await cache.load(userKey: "u1") == nil)
    }

    @Test("FR-ANN-003.2: opening marks it read after the API confirmed, and completes T-ANN-READ")
    func openMarksRead() async {
        let service = FeedService(items: [item("1"), item("2")])
        let sink = MemoryEventSink()
        let model = make(service, sink: sink)
        await model.begin()
        await model.open(id: "2")
        #expect(await service.readCalls == ["2"])
        #expect(model.item(id: "2")?.read == true)
        #expect(model.item(id: "1")?.read == false)
        try? await Task.sleep(for: .milliseconds(50))
        let names = await sink.events.map(\.event)
        #expect(names == [.taskStarted, .taskCompleted])
    }

    @Test("FR-ANN-003.2: a failed read call does not claim the item is read")
    func offlineOpenDoesNotClaimRead() async {
        let service = FeedService(items: [item("1")])
        await service.fail(read: .offline)
        let model = make(service)
        await model.begin()
        await model.open(id: "1")
        #expect(model.item(id: "1")?.read == false)
        #expect(model.unavailable.isEmpty)
    }

    @Test("FR-ANN-003: NOT_FOUND on open (withdrawn) shows 'no longer available'")
    func notFoundOnOpen() async {
        let service = FeedService(items: [item("1")])
        await service.fail(read: .notFound)
        let model = make(service)
        await model.begin()
        await model.open(id: "1")
        #expect(model.unavailable == ["1"])
    }

    @Test("FR-AUTH-005: an unauthenticated list opens the re-sign-in sheet")
    func reauth() async {
        let service = FeedService(items: [])
        await service.fail(list: .unauthenticated)
        var asked = false
        let model = make(service, reauth: { asked = true })
        await model.begin()
        #expect(asked)
    }
}
#endif
