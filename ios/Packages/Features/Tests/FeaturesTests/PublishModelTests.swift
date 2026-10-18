import Core
import Foundation
import Testing
@testable import Features

#if DEBUG
/// Scriptable service: records calls, fails on demand.
private actor FakeService: AnnouncementService {
    var calls: [String] = []
    var tokens: [String] = []
    var proposeError: AnnouncementError?
    var publishErrors: [AnnouncementError] = []
    private var minted = 0

    func fail(propose error: AnnouncementError?) { proposeError = error }
    func failPublish(_ errors: [AnnouncementError]) { publishErrors = errors }

    func propose(_ draft: AnnouncementDraft, accessToken: String) throws -> AnnouncementProposal {
        calls.append("propose")
        if let proposeError { throw proposeError }
        return AnnouncementProposal(id: "p1", draft: draft, recipientCount: 11)
    }

    func confirm(_ proposal: AnnouncementProposal, accessToken: String) -> String {
        calls.append("confirm")
        minted += 1
        return "token-\(minted)"
    }

    func publish(_ draft: AnnouncementDraft, confirmationToken: String, accessToken: String) throws
        -> PublishedAnnouncement
    {
        calls.append("publish")
        tokens.append(confirmationToken)
        if !publishErrors.isEmpty { throw publishErrors.removeFirst() }
        return PublishedAnnouncement(id: "a1", recipientCount: 11)
    }
}

@MainActor
private func make(
    _ service: FakeService, sink: MemoryEventSink = MemoryEventSink(),
    token: @escaping @Sendable () async throws -> String = { "bearer" },
    reauth: @escaping @MainActor () -> Void = {}, drafts: DraftStore = DraftStore()
) -> PublishModel {
    let flow = TaskFlow(
        taskId: "T-ANN-PUB", feature: "ann", mode: .classic,
        context: TaskContext(participantId: UUID()), sink: sink)
    return PublishModel(
        service: service, accessToken: token, onReauthNeeded: reauth, drafts: drafts, userKey: "u1",
        flow: flow, initial: AnnouncementDraft(title: "Store hours", body: "Open 8:00", language: .de))
}

@MainActor
@Suite("FR-ANN-001 publish flow")
struct PublishModelTests {
    @Test("FR-ANN-001: review then publish ends in success with the recipient count")
    func happyPath() async {
        let service = FakeService()
        let model = make(service)
        await model.begin()
        await model.review()
        #expect(model.phase == .reviewing(AnnouncementProposal(id: "p1", draft: model.draft, recipientCount: 11)))
        await model.publish()
        #expect(model.phase == .published(PublishedAnnouncement(id: "a1", recipientCount: 11)))
        #expect(await service.calls == ["propose", "confirm", "publish"])
    }

    @Test("FR-ANN-001.3: reviewing alone never publishes")
    func reviewDoesNotPublish() async {
        let service = FakeService()
        let model = make(service)
        await model.review()
        #expect(await !service.calls.contains("publish"))
    }

    @Test("FR-ANN-001.5: a retry after a failed publish replays the same token, no second mint")
    func retryReusesToken() async {
        let service = FakeService()
        await service.failPublish([.failed(code: "INTERNAL", correlationId: nil)])
        let model = make(service)
        await model.review()
        await model.publish()
        #expect(model.failure == .failed(code: "INTERNAL", correlationId: nil))
        #expect(model.draft.title == "Store hours")
        await model.retry()
        #expect(await service.tokens == ["token-1", "token-1"])
        #expect(await service.calls.filter { $0 == "confirm" }.count == 1)
        #expect(model.phase == .published(PublishedAnnouncement(id: "a1", recipientCount: 11)))
    }

    @Test("FR-ANN-001.5: double tap on Publish sends one write")
    func doubleTap() async {
        let service = FakeService()
        let model = make(service)
        await model.review()
        async let first: Void = model.publish()
        async let second: Void = model.publish()
        _ = await (first, second)
        #expect(await service.tokens.count == 1)
    }

    @Test("FR-ANN-001.4: FORBIDDEN is surfaced and publishing stays disabled")
    func forbidden() async {
        let service = FakeService()
        await service.fail(propose: .forbidden)
        let model = make(service)
        await model.review()
        #expect(model.failure == .forbidden)
        #expect(model.phase == .editing)
    }

    @Test("FR-ANN-001.1: API validation error marks the field and clears when it is edited")
    func validation() async {
        let service = FakeService()
        await service.fail(propose: .validation(.title))
        let model = make(service)
        await model.review()
        #expect(model.fieldError == .title)
        model.editedTitle("Better")
        #expect(model.fieldError == nil)
    }

    @Test("NFR-007: offline keeps the draft and the review, nothing is queued")
    func offline() async {
        let service = FakeService()
        await service.failPublish([.offline])
        let model = make(service)
        await model.review()
        await model.publish()
        #expect(model.failure == .offline)
        guard case .reviewing = model.phase else { Issue.record("left review"); return }
        #expect(model.draft.body == "Open 8:00")
        #expect(await service.tokens.count == 1)
    }

    @Test("FR-AUTH-005: expired session opens re-sign-in, sends no write, keeps the draft")
    func staleToken() async {
        let service = FakeService()
        let counter = Counter()
        let model = make(service, token: { throw AuthError.interactionRequired }, reauth: { counter.bump() })
        await model.review()
        #expect(counter.value == 1)
        #expect(await service.calls.isEmpty)
        #expect(model.draft.title == "Store hours")
    }

    @Test("FR-AUTH-005: draft is stored for re-sign-in and restored")
    func draftPreserved() async {
        let drafts = DraftStore()
        let first = make(FakeService(), drafts: drafts)
        first.editedTitle("Changed")
        try? await Task.sleep(for: .milliseconds(50))
        let flow = TaskFlow(
            taskId: "T-ANN-PUB", feature: "ann", mode: .classic,
            context: TaskContext(participantId: UUID()), sink: MemoryEventSink())
        let second = PublishModel(
            service: FakeService(), accessToken: { "t" }, onReauthNeeded: {}, drafts: drafts,
            userKey: "u1", flow: flow)
        await second.begin()
        #expect(second.draft.title == "Changed")
    }

    @Test("EXP-001/003: one started, one terminal event, errors carry a code and never content")
    func events() async throws {
        let sink = MemoryEventSink()
        let service = FakeService()
        await service.failPublish([.failed(code: "INTERNAL", correlationId: nil)])
        let model = make(service, sink: sink)
        await model.begin()
        await model.review()
        await model.publish()
        await model.retry()
        try await Task.sleep(for: .milliseconds(100))
        let names = await sink.events.map(\.event)
        #expect(names.filter { $0 == .taskStarted }.count == 1)
        #expect(names.filter { $0 == .taskCompleted }.count == 1)
        #expect(!names.contains(.taskAbandoned))
        #expect(names.contains(.confirmShown) && names.contains(.confirmAccepted))
        let error = try #require(await sink.events.first { $0.event == .taskError })
        #expect(error.code == "INTERNAL")
        let json = String(data: try JSONEncoder().encode(await sink.events), encoding: .utf8) ?? ""
        #expect(!json.contains("Store hours") && !json.contains("Open 8:00"))
        let done = try #require(await sink.events.first { $0.event == .taskCompleted })
        #expect(done.outcomeValid == true && (done.tapCount ?? 0) >= 3)
    }

    @Test("EXP-001: leaving before publishing reports abandon once")
    func abandon() async throws {
        let sink = MemoryEventSink()
        let model = make(FakeService(), sink: sink)
        await model.begin()
        model.leave()
        model.leave()
        try await Task.sleep(for: .milliseconds(100))
        let abandoned = await sink.events.filter { $0.event == .taskAbandoned }
        #expect(abandoned.count == 1 && abandoned.first?.lastState == "compose")
    }
}

private final class Counter: @unchecked Sendable { // test-only, mutated on the main actor
    private(set) var value = 0
    func bump() { value += 1 }
}
#endif
