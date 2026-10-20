import Foundation

/// FR-BRF-001: whether the weekly briefing is on for this user. Off by default.
public struct BriefingStatus: Sendable, Equatable {
    public let optedIn: Bool

    public init(optedIn: Bool) { self.optedIn = optedIn }
}

/// One event as `api/` returned it from Work IQ (FR-BRF-002). Times are absolute instants; they are shown
/// in Europe/Zurich. The title is somebody else's text: show it as inert text, never as markup or a link.
public struct BriefingEvent: Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let start: Date
    public let end: Date
    public let allDay: Bool
    public let location: String
    public let online: Bool
    public let attendeeCount: Int
    /// Ids of the events this one overlaps (flagged by `api/` from the same data).
    public let conflictsWith: [String]

    public init(
        id: String, title: String, start: Date, end: Date, allDay: Bool = false, location: String = "",
        online: Bool = false, attendeeCount: Int = 0, conflictsWith: [String] = []
    ) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.allDay = allDay
        self.location = location
        self.online = online
        self.attendeeCount = attendeeCount
        self.conflictsWith = conflictsWith
    }

    public var hasConflict: Bool { !conflictsWith.isEmpty }
}

public struct BriefingFreeBlock: Sendable, Equatable {
    public let start: Date
    public let end: Date
    public let minutes: Int

    public init(start: Date, end: Date, minutes: Int) {
        self.start = start
        self.end = end
        self.minutes = minutes
    }
}

public struct BriefingDay: Sendable, Equatable, Identifiable {
    public let day: CalendarDay
    public let events: [BriefingEvent]
    public let freeBlocks: [BriefingFreeBlock]
    /// Work IQ did not answer for this day (FR-BRF-005.3): nothing is known about it, not "free".
    public let missing: Bool

    public var id: String { day.iso }

    public init(day: CalendarDay, events: [BriefingEvent], freeBlocks: [BriefingFreeBlock], missing: Bool = false) {
        self.day = day
        self.events = events
        self.freeBlocks = freeBlocks
        self.missing = missing
    }
}

/// The week as `api/` computed it. The app only displays it: grouping, conflicts and free blocks are `api/`'s.
public struct BriefingWeek: Sendable, Equatable {
    public let start: CalendarDay
    public let end: CalendarDay
    public let days: [BriefingDay]
    public let eventCount: Int
    public let conflictCount: Int

    public init(start: CalendarDay, end: CalendarDay, days: [BriefingDay], eventCount: Int, conflictCount: Int) {
        self.start = start
        self.end = end
        self.days = days
        self.eventCount = eventCount
        self.conflictCount = conflictCount
    }

    public var missingDays: [BriefingDay] { days.filter(\.missing) }
    /// Labelled partial in the UI, with the missing days named (FR-BRF-005.3).
    public var isPartial: Bool { days.contains(where: \.missing) }
    /// "No events this week" is a briefing, not an error (FR-BRF-005.2).
    public var isEmpty: Bool { eventCount == 0 && !isPartial }
}

/// The confirm step for turning the briefing on or off (FR-BRF-001, FR-AUTH-006): a proposal the server
/// stores, then a token minted from the user's tap, then the write.
public struct BriefingOptInProposal: Sendable, Equatable {
    public let id: String
    public let enabled: Bool

    public init(id: String, enabled: Bool) {
        self.id = id
        self.enabled = enabled
    }
}

public protocol BriefingService: Sendable {
    func status(accessToken: String) async throws -> BriefingStatus
    /// The signed-in user's own week. Can take 40-60 s (Work IQ). There is no user parameter (FR-BRF-004).
    func week(accessToken: String) async throws -> BriefingWeek
    func proposeOptIn(enabled: Bool, accessToken: String) async throws -> BriefingOptInProposal
    /// The tap on the opt-in screen's button: the only call that mints the confirmation token.
    func confirmOptIn(_ proposal: BriefingOptInProposal, accessToken: String) async throws -> String
    func setOptIn(enabled: Bool, confirmationToken: String, accessToken: String) async throws -> BriefingStatus
}

public enum BriefingError: Error, Sendable, Equatable {
    case offline
    case unauthenticated
    /// `NOT_OPTED_IN`: the briefing is off (or was turned off elsewhere).
    case notOptedIn
    /// `NOT_PROVISIONED`: the account has no employee record.
    case notProvisioned
    /// `WORKIQ_UNAVAILABLE` (503): try again later.
    case workIQUnavailable
    /// `NO_LICENCE` (403): the account has no access, or the organisation has not enabled Work IQ billing.
    case noLicence
    /// `CONSENT_REQUIRED` (403): the administrator has not approved Work IQ access. The user cannot fix it.
    case consentRequired
    /// The request ran out of time: Work IQ is slow, not the network.
    case timedOut
    case invalidConfirmation
    case failed(code: String?, correlationId: String?)

    /// Stable code for `task_error` events; never content.
    public var code: String {
        switch self {
        case .offline: "OFFLINE"
        case .unauthenticated: "UNAUTHENTICATED"
        case .notOptedIn: "NOT_OPTED_IN"
        case .notProvisioned: "NOT_PROVISIONED"
        case .workIQUnavailable: "WORKIQ_UNAVAILABLE"
        case .noLicence: "NO_LICENCE"
        case .consentRequired: "CONSENT_REQUIRED"
        case .timedOut: "TIMEOUT"
        case .invalidConfirmation: "INVALID_CONFIRMATION"
        case let .failed(code, _): code ?? "UNKNOWN"
        }
    }
}

/// Used where the app has no API address (unconfigured builds).
public struct UnconfiguredBriefingService: BriefingService {
    public init() {}

    public func status(accessToken: String) async throws -> BriefingStatus { throw Self.failure }
    public func week(accessToken: String) async throws -> BriefingWeek { throw Self.failure }
    public func proposeOptIn(enabled: Bool, accessToken: String) async throws -> BriefingOptInProposal {
        throw Self.failure
    }
    public func confirmOptIn(_ proposal: BriefingOptInProposal, accessToken: String) async throws -> String {
        throw Self.failure
    }
    public func setOptIn(enabled: Bool, confirmationToken: String, accessToken: String) async throws -> BriefingStatus {
        throw Self.failure
    }
    private static var failure: BriefingError { .failed(code: "NOT_CONFIGURED", correlationId: nil) }
}
