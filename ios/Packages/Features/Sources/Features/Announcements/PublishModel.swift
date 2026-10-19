import Core
import Observation

/// CLASSIC publish flow for FR-ANN-001: compose, review, publish. The API owns every rule;
/// this only sequences the calls, keeps the draft, and reports the flow (T-ANN-PUB).
@MainActor @Observable
public final class PublishModel {
    public enum Phase: Equatable {
        case editing
        case checking
        case reviewing(AnnouncementProposal)
        case publishing(AnnouncementProposal)
        case published(PublishedAnnouncement)
    }

    /// Live recipient count in the audience picker (FR-ANN-002.2).
    public enum AudienceCount: Equatable {
        case loading
        case recipients(Int)
        case empty
        case failed
    }

    public enum Failure: Equatable {
        case offline
        case forbidden
        case invalidConfirmation
        case failed(code: String?, correlationId: String?)
    }

    public var draft: AnnouncementDraft {
        didSet { if draft != oldValue { persistDraft() } }
    }
    public private(set) var phase: Phase = .editing
    /// Set by the API's `VALIDATION_ERROR`; cleared when that field is edited.
    public private(set) var fieldError: DraftField?
    public private(set) var failure: Failure?
    public private(set) var audienceOptions: AudienceOptions?
    public private(set) var audienceOptionsFailed = false
    public private(set) var audienceCount: AudienceCount = .loading

    private let service: any AnnouncementService
    private let accessToken: @Sendable () async throws -> String
    private let onReauthNeeded: @MainActor () -> Void
    private let drafts: DraftStore
    private let draftKey: String
    /// The latest draft write; awaited before the draft is removed so a late save cannot resurrect it.
    private var pendingSave: Task<Void, Never>?
    private let flow: TaskFlow
    /// Kept across retries so a replayed publish is idempotent (FR-ANN-001.5).
    private var confirmationToken: String?
    private var shownForProposal: String?
    private var countTask: Task<Void, Never>?

    public init(
        service: any AnnouncementService,
        accessToken: @escaping @Sendable () async throws -> String,
        onReauthNeeded: @escaping @MainActor () -> Void,
        drafts: DraftStore,
        userKey: String,
        flow: TaskFlow,
        initial: AnnouncementDraft = AnnouncementDraft()
    ) {
        self.service = service
        self.accessToken = accessToken
        self.onReauthNeeded = onReauthNeeded
        self.drafts = drafts
        self.draftKey = "announcements.compose.\(userKey)"
        self.flow = flow
        self.draft = initial
    }

    public var isBusy: Bool {
        switch phase {
        case .checking, .publishing: true
        default: false
        }
    }

    // MARK: Flow

    public func begin() async {
        flow.start()
        if let saved = await drafts.draft(key: draftKey), draft == AnnouncementDraft() {
            draft = AnnouncementDraft(
                title: saved["title"] ?? "", body: saved["body"] ?? "",
                language: saved["language"].flatMap(ContentLanguage.init) ?? .de)
        }
    }

    public func editedTitle(_ value: String) { edit(.title) { $0.title = value } }
    public func editedBody(_ value: String) { edit(.body) { $0.body = value } }

    public func selectLanguage(_ language: ContentLanguage) {
        guard language != draft.language else { return }
        flow.tap()
        edit(.language) { $0.language = language }
    }

    // MARK: Audience (FR-ANN-002)

    public func loadAudience() async {
        audienceOptionsFailed = false
        do {
            audienceOptions = try await call { token in try await service.audienceOptions(accessToken: token) }
        } catch {
            audienceOptionsFailed = true
        }
        await refreshCount()
    }

    /// Opening the picker is an explicit tap on the way to a recipient choice.
    public func openedAudience() { flow.tap() }

    public func toggleAudience(_ value: String, in dimension: AudienceDimension) {
        flow.tap()
        edit(.audience) { $0.audience.toggle(value, in: dimension) }
        scheduleCount()
    }

    public func setEveryone(_ on: Bool) {
        flow.tap()
        edit(.audience) { $0.audience.setEveryone(on) }
        scheduleCount()
    }

    private func scheduleCount() {
        countTask?.cancel()
        audienceCount = .loading
        countTask = Task { await refreshCount() }
    }

    private func refreshCount() async {
        let audience = draft.audience
        if audience.isEmpty {
            audienceCount = .empty
            return
        }
        audienceCount = .loading
        do {
            let count = try await call { token in
                try await service.recipientCount(for: audience, accessToken: token)
            }
            guard !Task.isCancelled, audience == draft.audience else { return }
            audienceCount = .recipients(count)
        } catch AnnouncementError.emptyAudience {
            guard !Task.isCancelled, audience == draft.audience else { return }
            audienceCount = .empty
        } catch {
            guard !Task.isCancelled, audience == draft.audience else { return }
            audienceCount = .failed
        }
    }

    /// "Review": dry run on the API. Nothing is visible to anyone yet (FR-ANN-001.3).
    public func review() async {
        guard !isBusy else { return }
        flow.tap()
        fieldError = nil
        failure = nil
        phase = .checking
        do {
            let proposal = try await call { token in try await service.propose(draft, accessToken: token) }
            confirmationToken = nil
            phase = .reviewing(proposal)
            if shownForProposal != proposal.id {
                shownForProposal = proposal.id
                flow.confirmShown()
            }
        } catch let error as AnnouncementError {
            phase = .editing
            handle(error, recovered: false)
        } catch {
            phase = .editing
        }
    }

    /// "Publish": the user's own tap mints the token, then the write runs with it.
    public func publish() async {
        guard case let .reviewing(proposal) = phase else { return }
        flow.tap()
        flow.confirmAccepted()
        await runPublish(proposal)
    }

    /// Retry after a failed publish: same token if we have one, so the server replays instead of duplicating.
    public func retry() async {
        guard case let .reviewing(proposal) = phase else { return }
        flow.tap()
        await runPublish(proposal)
    }

    public func backToEditing() {
        guard case .reviewing = phase else { return }
        flow.tap()
        flow.confirmRejected()
        confirmationToken = nil
        failure = nil
        phase = .editing
    }

    /// Called when the flow screen goes away. Reports abandon unless the task completed.
    public func leave() {
        switch phase {
        case .published: break
        case .editing, .checking: flow.abandon(lastState: "compose")
        case .reviewing, .publishing: flow.abandon(lastState: "review")
        }
    }

    // MARK: Internals

    private func runPublish(_ proposal: AnnouncementProposal) async {
        guard !isBusy else { return }
        failure = nil
        phase = .publishing(proposal)
        do {
            let result = try await call { token in
                let confirmation: String
                if let existing = confirmationToken {
                    confirmation = existing
                } else {
                    confirmation = try await service.confirm(proposal, accessToken: token)
                    confirmationToken = confirmation
                }
                return try await service.publish(
                    proposal.draft, confirmationToken: confirmation, accessToken: token)
            }
            phase = .published(result)
            flow.complete(outcomeValid: true)
            await pendingSave?.value
            await drafts.remove(key: draftKey)
        } catch let error as AnnouncementError {
            phase = .reviewing(proposal)
            handle(error, recovered: false)
        } catch {
            phase = .reviewing(proposal)
        }
    }

    /// Never sends a write with a stale token: if silent refresh fails the re-sign-in sheet opens
    /// and the draft stays (FR-AUTH-005).
    private func call<T: Sendable>(_ work: (String) async throws -> T) async throws -> T {
        let token: String
        do {
            token = try await accessToken()
        } catch AuthError.interactionRequired {
            throw AnnouncementError.unauthenticated  // handle() opens the sheet
        } catch AuthError.offline {
            throw AnnouncementError.offline
        } catch {
            throw AnnouncementError.failed(code: "AUTH", correlationId: nil)
        }
        let runId = flow.activeRunId
        return try await TaskRun.$current.withValue(runId) { try await work(token) }
    }

    private func handle(_ error: AnnouncementError, recovered: Bool) {
        flow.error(code: error.code, recovered: recovered)
        switch error {
        case .offline: failure = .offline
        case .forbidden: failure = .forbidden
        case .unauthenticated:
            // A 401 from the API (revoked token) behaves like a failed silent refresh; the draft stays.
            failure = nil
            onReauthNeeded()
        case let .validation(field): fieldError = field
        case .invalidConfirmation:
            confirmationToken = nil
            failure = .invalidConfirmation
        case .emptyAudience: fieldError = .audience
        case .notFound: failure = .failed(code: error.code, correlationId: nil)
        case let .failed(code, correlationId): failure = .failed(code: code, correlationId: correlationId)
        }
    }

    private func edit(_ field: DraftField, _ change: (inout AnnouncementDraft) -> Void) {
        change(&draft)
        if fieldError == field { fieldError = nil }
    }

    private func persistDraft() {
        let fields = ["title": draft.title, "body": draft.body, "language": draft.language.rawValue]
        let store = drafts, key = draftKey
        let previous = pendingSave
        pendingSave = Task {
            await previous?.value
            await store.save(fields, key: key)
        }
    }
}
