import Foundation

public enum ContentLanguage: String, Sendable, CaseIterable, Codable {
    case de, fr, it, en
}

/// Informational counters only. `api/` owns and enforces the limits (FR-ANN-001.1).
public enum AnnouncementLimits {
    public static let title = 120
    public static let body = 5000
}

public enum AudienceDimension: String, Sendable, CaseIterable {
    case region, store, role
}

/// Who an announcement is for: everyone, or a union of regions, stores/HQ and roles (FR-ANN-002.1).
/// "All" is exclusive here as in the API; `api/` stays the authority and re-checks every rule.
public struct AudienceSelection: Sendable, Equatable, Codable {
    public private(set) var everyone: Bool
    public private(set) var regions: Set<String>
    public private(set) var stores: Set<String>
    public private(set) var roles: Set<String>

    public static let all = AudienceSelection()

    public init(everyone: Bool = true, regions: Set<String> = [], stores: Set<String> = [], roles: Set<String> = []) {
        self.everyone = everyone && regions.isEmpty && stores.isEmpty && roles.isEmpty
        self.regions = regions
        self.stores = stores
        self.roles = roles
    }

    public var isEmpty: Bool { !everyone && regions.isEmpty && stores.isEmpty && roles.isEmpty }

    public func contains(_ value: String, in dimension: AudienceDimension) -> Bool {
        switch dimension {
        case .region: regions.contains(value)
        case .store: stores.contains(value)
        case .role: roles.contains(value)
        }
    }

    public func values(_ dimension: AudienceDimension) -> [String] {
        switch dimension {
        case .region: regions.sorted()
        case .store: stores.sorted()
        case .role: roles.sorted()
        }
    }

    /// Picking any criterion leaves "all".
    public mutating func toggle(_ value: String, in dimension: AudienceDimension) {
        everyone = false
        switch dimension {
        case .region: regions.formSymmetricDifference([value])
        case .store: stores.formSymmetricDifference([value])
        case .role: roles.formSymmetricDifference([value])
        }
    }

    /// "All employees" on clears every other criterion; off leaves an empty selection to be filled.
    public mutating func setEveryone(_ on: Bool) {
        if on {
            self = .all
        } else {
            everyone = false
        }
    }
}

public struct AudienceOptions: Sendable, Equatable {
    public let regions: [String]
    public let stores: [String]
    public let roles: [String]

    public init(regions: [String], stores: [String], roles: [String]) {
        self.regions = regions
        self.stores = stores
        self.roles = roles
    }

    public func values(_ dimension: AudienceDimension) -> [String] {
        switch dimension {
        case .region: regions
        case .store: stores
        case .role: roles
        }
    }
}

public struct AnnouncementDraft: Sendable, Equatable {
    public var title: String
    public var body: String
    public var language: ContentLanguage
    public var audience: AudienceSelection

    public init(
        title: String = "", body: String = "", language: ContentLanguage = .de,
        audience: AudienceSelection = .all
    ) {
        self.title = title
        self.body = body
        self.language = language
        self.audience = audience
    }
}

/// One announcement as the feed shows it (FR-ANN-003.1). Text is data: never interpreted as markup.
public struct AnnouncementItem: Sendable, Equatable, Codable, Identifiable {
    public let id: String
    public let title: String
    public let body: String
    public let language: ContentLanguage
    public let author: String
    public let publishedAt: Date
    public var read: Bool
    /// "all" or the stored rule, as text for the detail chip.
    public let audience: AudienceSelection

    public init(
        id: String, title: String, body: String, language: ContentLanguage, author: String,
        publishedAt: Date, read: Bool, audience: AudienceSelection = .all
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.language = language
        self.author = author
        self.publishedAt = publishedAt
        self.read = read
        self.audience = audience
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
    /// `EMPTY_AUDIENCE`: the audience resolves to nobody (FR-ANN-002.4).
    case emptyAudience
    /// `NOT_FOUND`: unknown, withdrawn or not addressed to this user; deliberately indistinguishable.
    case notFound
    case failed(code: String?, correlationId: String?)

    /// Stable code for `task_error` events; never content.
    public var code: String {
        switch self {
        case .offline: "OFFLINE"
        case .unauthenticated: "UNAUTHENTICATED"
        case .forbidden: "FORBIDDEN"
        case .validation: "VALIDATION_ERROR"
        case .invalidConfirmation: "INVALID_CONFIRMATION"
        case .emptyAudience: "EMPTY_AUDIENCE"
        case .notFound: "NOT_FOUND"
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

    /// FR-ANN-003: the announcements addressed to the signed-in user, newest first.
    func list(accessToken: String) async throws -> [AnnouncementItem]
    /// Per-user read marking; idempotent. `notFound` if it is no longer addressed to the user.
    func markRead(id: String, accessToken: String) async throws
    /// FR-ANN-002: choices for the picker (Publisher only).
    func audienceOptions(accessToken: String) async throws -> AudienceOptions
    /// Live recipient count for a selection; throws `emptyAudience` for zero.
    func recipientCount(for audience: AudienceSelection, accessToken: String) async throws -> Int
}
