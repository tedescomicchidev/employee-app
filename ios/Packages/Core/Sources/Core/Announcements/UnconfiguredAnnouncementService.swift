/// Used when the API is not configured (same situation as `UnconfiguredAuthService`).
public struct UnconfiguredAnnouncementService: AnnouncementService {
    public init() {}
    public func propose(_ draft: AnnouncementDraft, accessToken: String) async throws -> AnnouncementProposal {
        throw AnnouncementError.failed(code: "NOT_CONFIGURED", correlationId: nil)
    }
    public func confirm(_ proposal: AnnouncementProposal, accessToken: String) async throws -> String {
        throw AnnouncementError.failed(code: "NOT_CONFIGURED", correlationId: nil)
    }
    public func publish(
        _ draft: AnnouncementDraft, confirmationToken: String, accessToken: String
    ) async throws -> PublishedAnnouncement {
        throw AnnouncementError.failed(code: "NOT_CONFIGURED", correlationId: nil)
    }
    public func list(accessToken: String) async throws -> [AnnouncementItem] {
        throw AnnouncementError.failed(code: "NOT_CONFIGURED", correlationId: nil)
    }
    public func markRead(id: String, accessToken: String) async throws {
        throw AnnouncementError.failed(code: "NOT_CONFIGURED", correlationId: nil)
    }
    public func audienceOptions(accessToken: String) async throws -> AudienceOptions {
        throw AnnouncementError.failed(code: "NOT_CONFIGURED", correlationId: nil)
    }
    public func recipientCount(for audience: AudienceSelection, accessToken: String) async throws -> Int {
        throw AnnouncementError.failed(code: "NOT_CONFIGURED", correlationId: nil)
    }
}
