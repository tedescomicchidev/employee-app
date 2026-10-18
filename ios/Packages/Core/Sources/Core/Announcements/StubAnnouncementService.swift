#if DEBUG
import Foundation

public enum AnnouncementStubScenario: String, Sendable, CaseIterable {
    case ok, validation, publishFails, publishOffline, offline, forbidden
}

/// Stub for UI tests and screenshots (DEBUG only). Counts publish calls so tests can assert "once".
public actor StubAnnouncementService: AnnouncementService {
    public private(set) var publishCalls = 0
    private let scenario: AnnouncementStubScenario
    private let recipients: Int

    public init(scenario: AnnouncementStubScenario = .ok, recipients: Int = 11) {
        self.scenario = scenario
        self.recipients = recipients
    }

    public func propose(_ draft: AnnouncementDraft, accessToken: String) throws -> AnnouncementProposal {
        switch scenario {
        case .forbidden: throw AnnouncementError.forbidden
        case .offline: throw AnnouncementError.offline
        default: break
        }
        if draft.title.isEmpty { throw AnnouncementError.validation(.title) }
        if draft.body.isEmpty { throw AnnouncementError.validation(.body) }
        if scenario == .validation { throw AnnouncementError.validation(.title) }
        return AnnouncementProposal(id: "stub-proposal", draft: draft, recipientCount: recipients)
    }

    public func confirm(_ proposal: AnnouncementProposal, accessToken: String) throws -> String {
        "stub-token"
    }

    public func publish(
        _ draft: AnnouncementDraft, confirmationToken: String, accessToken: String
    ) throws -> PublishedAnnouncement {
        publishCalls += 1
        switch scenario {
        case .publishFails: throw AnnouncementError.failed(code: "INTERNAL", correlationId: "stub-corr-1234")
        case .offline, .publishOffline: throw AnnouncementError.offline
        default: return PublishedAnnouncement(id: "stub-announcement", recipientCount: recipients)
        }
    }
}
#endif
