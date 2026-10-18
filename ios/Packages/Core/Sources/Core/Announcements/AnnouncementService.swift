import Foundation

public enum ContentLanguage: String, Sendable, CaseIterable, Codable {
    case de, fr, it, en
}

/// Informational counters only. `api/` owns and enforces the limits (FR-ANN-001.1).
public enum AnnouncementLimits {
    public static let title = 120
    public static let body = 5000
}

public struct AnnouncementDraft: Sendable, Equatable {
    public var title: String
    public var body: String
    public var language: ContentLanguage

    public init(title: String = "", body: String = "", language: ContentLanguage = .de) {
        self.title = title
        self.body = body
        self.language = language
    }
}

public enum DraftField: String, Sendable, Equatable {
    case title, body, language, audience, payload
}

/// Dry-run result from `POST /v1/proposals`: what Review shows, exactly as the API will publish it.
public struct AnnouncementProposal: Sendable, Equatable {
    public let id: String
    public let draft: AnnouncementDraft
    public let recipientCount: Int

    public init(id: String, draft: AnnouncementDraft, recipientCount: Int) {
        self.id = id
        self.draft = draft
        self.recipientCount = recipientCount
    }
}

public struct PublishedAnnouncement: Sendable, Equatable {
    public let id: String
    public let recipientCount: Int

    public init(id: String, recipientCount: Int) {
        self.id = id
        self.recipientCount = recipientCount
    }
}

public enum AnnouncementError: Error, Sendable, Equatable {
    case offline
    case unauthenticated
    case forbidden
    case validation(DraftField)
    /// `CONFIRMATION_REQUIRED` / `INVALID_CONFIRMATION` (expired, reused, tampered).
    case invalidConfirmation
    case failed(code: String?, correlationId: String?)

    /// Stable code for `task_error` events; never content.
    public var code: String {
        switch self {
        case .offline: "OFFLINE"
        case .unauthenticated: "UNAUTHENTICATED"
        case .forbidden: "FORBIDDEN"
        case .validation: "VALIDATION_ERROR"
        case .invalidConfirmation: "INVALID_CONFIRMATION"
        case let .failed(code, _): code ?? "UNKNOWN"
        }
    }
}

/// CLASSIC publish path. Review mints the token through the same endpoint agents use (FR-AUTH-006),
/// and the token is kept by the caller so a retry replays the same token (idempotent, FR-ANN-001.5).
public protocol AnnouncementService: Sendable {
    func propose(_ draft: AnnouncementDraft, accessToken: String) async throws -> AnnouncementProposal
    func confirm(_ proposal: AnnouncementProposal, accessToken: String) async throws -> String
    func publish(
        _ draft: AnnouncementDraft, confirmationToken: String, accessToken: String
    ) async throws -> PublishedAnnouncement
}
