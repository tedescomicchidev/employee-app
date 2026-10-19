import Foundation

/// A business date (Europe/Zurich calendar date), kept as year/month/day so no time zone can shift it.
public struct CalendarDay: Sendable, Hashable, Comparable, Codable {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// `YYYY-MM-DD`, the API's date format.
    public init?(iso: String) {
        let parts = iso.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1...12).contains(parts[1]), (1...31).contains(parts[2]) else { return nil }
        self.init(year: parts[0], month: parts[1], day: parts[2])
    }

    public init(date: Date, calendar: Calendar = .zurich) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: c.year ?? 1970, month: c.month ?? 1, day: c.day ?? 1)
    }

    public var iso: String { String(format: "%04d-%02d-%02d", year, month, day) }

    public func date(in calendar: Calendar = .zurich) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? Date(timeIntervalSince1970: 0)
    }

    public static func < (a: CalendarDay, b: CalendarDay) -> Bool { a.iso < b.iso }

    public func addingDays(_ days: Int, calendar: Calendar = .zurich) -> CalendarDay {
        CalendarDay(date: calendar.date(byAdding: .day, value: days, to: date(in: calendar)) ?? date(in: calendar), calendar: calendar)
    }
}

public extension Calendar {
    /// Business dates are Europe/Zurich calendar dates (requirements.md conventions).
    static let zurich: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Zurich") ?? .current
        calendar.firstWeekday = 2
        return calendar
    }()
}

/// The five numbers of FR-VAC-001. All computed by `api/` (R1-R3); the app only displays them.
public struct VacationBalance: Sendable, Equatable, Codable {
    public let year: Int
    public let entitlement: Int
    public let carriedOver: Int
    public let approved: Int
    public let pending: Int
    public let remaining: Int

    public init(year: Int, entitlement: Int, carriedOver: Int, approved: Int, pending: Int, remaining: Int) {
        self.year = year
        self.entitlement = entitlement
        self.carriedOver = carriedOver
        self.approved = approved
        self.pending = pending
        self.remaining = remaining
    }
}

public enum VacationStatus: String, Sendable, Codable {
    case pending, approved, rejected, cancelled
}

public enum VacationDecision: String, Sendable, Equatable {
    case approve, reject
}

/// A day that was not counted, with the holiday name when it is one (FR-VAC-006.2).
public struct ExcludedDay: Sendable, Equatable, Codable, Hashable {
    public enum Kind: String, Sendable, Codable { case weekend, holiday }
    public let day: CalendarDay
    public let kind: Kind
    public let name: String?

    public init(day: CalendarDay, kind: Kind, name: String? = nil) {
        self.day = day
        self.kind = kind
        self.name = name
    }
}

public struct VacationRequestSummary: Sendable, Equatable, Codable, Identifiable {
    public let id: String
    public let status: VacationStatus
    public let start: CalendarDay
    public let end: CalendarDay
    public let countedDays: Int
    public let approver: String
    /// Set for a manager's view of a report's request (FR-VAC-004); empty for the owner's own.
    public let ownerName: String
    /// When the request was approved, rejected or cancelled; nil while pending.
    public let decidedAt: Date?
    /// The rejection reason, shown to the owner (FR-VAC-007.1). Never logged.
    public let reason: String?
    public let submittedAt: Date?
    /// The report's balance, only in the detail an approver opens (FR-VAC-001.3).
    public let ownerBalance: VacationBalance?

    public init(
        id: String, status: VacationStatus, start: CalendarDay, end: CalendarDay, countedDays: Int, approver: String,
        ownerName: String = "", decidedAt: Date? = nil, reason: String? = nil, submittedAt: Date? = nil,
        ownerBalance: VacationBalance? = nil
    ) {
        self.id = id
        self.status = status
        self.start = start
        self.end = end
        self.countedDays = countedDays
        self.approver = approver
        self.ownerName = ownerName
        self.decidedAt = decidedAt
        self.reason = reason
        self.submittedAt = submittedAt
        self.ownerBalance = ownerBalance
    }
}

public struct VacationHoliday: Sendable, Equatable, Codable, Identifiable {
    public var id: CalendarDay { day }
    public let day: CalendarDay
    public let name: String

    public init(day: CalendarDay, name: String) {
        self.day = day
        self.name = name
    }
}

public struct VacationHolidays: Sendable, Equatable, Codable {
    public let year: Int
    public let canton: String?
    public let items: [VacationHoliday]
    /// The seed is `HUMAN_CONFIRMATION_REQUIRED`: HR has not confirmed these dates yet.
    public let needsConfirmation: Bool

    public init(year: Int, canton: String?, items: [VacationHoliday], needsConfirmation: Bool = false) {
        self.year = year
        self.canton = canton
        self.items = items
        self.needsConfirmation = needsConfirmation
    }
}

/// What the user sees before confirming (FR-VAC-002.3). Every number is the API's.
public struct VacationReview: Sendable, Equatable {
    public let countedDays: Int
    public let perYear: [Int: Int]
    public let excluded: [ExcludedDay]
    public let remaining: Int
    public let remainingAfter: Int?
    public let balanceYear: Int
    public let approver: String?

    public init(
        countedDays: Int, perYear: [Int: Int], excluded: [ExcludedDay], remaining: Int,
        remainingAfter: Int?, balanceYear: Int, approver: String?
    ) {
        self.countedDays = countedDays
        self.perYear = perYear
        self.excluded = excluded
        self.remaining = remaining
        self.remainingAfter = remainingAfter
        self.balanceYear = balanceYear
        self.approver = approver
    }
}

public struct VacationProposal: Sendable, Equatable {
    public let id: String
    public let start: CalendarDay
    public let end: CalendarDay
    public let review: VacationReview

    public init(id: String, start: CalendarDay, end: CalendarDay, review: VacationReview) {
        self.id = id
        self.start = start
        self.end = end
        self.review = review
    }
}

/// Stable reason codes of R5-R8, listed in the API's precedence order (FR-VAC-002.2).
public enum VacationRuleCode: String, Sendable, CaseIterable {
    case invalidRange = "INVALID_RANGE"
    case pastDate = "PAST_DATE"
    case zeroDays = "ZERO_DAYS"
    case blackout = "BLACKOUT"
    case overlap = "OVERLAP"
    case insufficientBalance = "INSUFFICIENT_BALANCE"
}

public struct DayRange: Sendable, Equatable {
    public let start: CalendarDay
    public let end: CalendarDay
    public init(start: CalendarDay, end: CalendarDay) {
        self.start = start
        self.end = end
    }
}

public struct VacationViolation: Sendable, Equatable {
    public let code: String
    public let remaining: Int?
    public let requested: Int?
    public let range: DayRange?
    public let conflicts: [DayRange]

    public init(code: String, remaining: Int? = nil, requested: Int? = nil, range: DayRange? = nil, conflicts: [DayRange] = []) {
        self.code = code
        self.remaining = remaining
        self.requested = requested
        self.range = range
        self.conflicts = conflicts
    }

    public var rule: VacationRuleCode? { VacationRuleCode(rawValue: code) }
}

public enum VacationError: Error, Sendable, Equatable {
    case offline
    case unauthenticated
    case forbidden
    /// The account has no employee record (`NOT_PROVISIONED`).
    case notProvisioned
    /// `CANTON_MISSING`: "Ask HR to set your canton".
    case cantonMissing
    case noApprover
    /// `NOT_FOUND`: unknown or not yours (FR-VAC-003, 004).
    case notFound
    /// `INVALID_STATE`: the request is no longer pending (FR-VAC-003.2, 004.3).
    case invalidState
    /// `SELF_APPROVAL` (R10).
    case selfApproval
    /// R5-R8: every failing code, first by precedence, plus what a blocked review still shows.
    case rules([VacationViolation], review: VacationReview?)
    case invalidConfirmation
    case validation
    case failed(code: String?, correlationId: String?)

    /// Stable code for `task_error` events; never content.
    public var code: String {
        switch self {
        case .offline: "OFFLINE"
        case .unauthenticated: "UNAUTHENTICATED"
        case .forbidden: "FORBIDDEN"
        case .notProvisioned: "NOT_PROVISIONED"
        case .cantonMissing: "CANTON_MISSING"
        case .noApprover: "NO_APPROVER"
        case .notFound: "NOT_FOUND"
        case .invalidState: "INVALID_STATE"
        case .selfApproval: "SELF_APPROVAL"
        case let .rules(violations, _): violations.first?.code ?? "RULE"
        case .invalidConfirmation: "INVALID_CONFIRMATION"
        case .validation: "VALIDATION_ERROR"
        case let .failed(code, _): code ?? "UNKNOWN"
        }
    }
}

/// CLASSIC vacation path (FR-VAC-001/002/006). `api/` owns every rule; this only carries requests.
public protocol VacationService: Sendable {
    func balance(accessToken: String) async throws -> VacationBalance
    func requests(accessToken: String) async throws -> [VacationRequestSummary]
    func holidays(year: Int, accessToken: String) async throws -> VacationHolidays
    /// Dry run through the same validation as the write; creates nothing (FR-VAC-002.2/.3).
    func propose(start: CalendarDay, end: CalendarDay, accessToken: String) async throws -> VacationProposal
    func confirm(_ proposal: VacationProposal, accessToken: String) async throws -> String
    /// Idempotent on the confirmation token (FR-VAC-002.4).
    func submit(
        start: CalendarDay, end: CalendarDay, confirmationToken: String, accessToken: String
    ) async throws -> VacationRequestSummary
    /// One request, for its owner or its approver (`NOT_FOUND` for anyone else).
    func request(id: String, accessToken: String) async throws -> VacationRequestSummary
    /// Dry run and confirmation of a cancel in one step; call it after the user confirmed (FR-VAC-003.3).
    func confirmCancel(id: String, accessToken: String) async throws -> String
    /// Idempotent on the confirmation token; `INVALID_STATE` unless the request is pending (FR-VAC-003.2).
    func cancel(id: String, confirmationToken: String, accessToken: String) async throws -> VacationRequestSummary
    /// Requests waiting for the signed-in manager (FR-VAC-004.1); `forbidden` for non-managers.
    func inbox(accessToken: String) async throws -> [VacationRequestSummary]
    /// Dry run and confirmation of a decision in one step; call it after the user confirmed.
    /// An approval that would now break R5-R7 throws `.rules` and the request stays pending (FR-VAC-004.2).
    func confirmDecision(
        id: String, decision: VacationDecision, reason: String?, accessToken: String
    ) async throws -> String
    /// Final and idempotent on the confirmation token (FR-VAC-004.3).
    func decide(
        id: String, decision: VacationDecision, reason: String?, confirmationToken: String, accessToken: String
    ) async throws -> VacationRequestSummary
}

/// Last good overview for offline display with an "as of" time (NFR-007).
public struct VacationSnapshot: Sendable, Equatable, Codable {
    public let userKey: String
    public let fetchedAt: Date
    public let balance: VacationBalance
    public let requests: [VacationRequestSummary]

    public init(userKey: String, fetchedAt: Date, balance: VacationBalance, requests: [VacationRequestSummary]) {
        self.userKey = userKey
        self.fetchedAt = fetchedAt
        self.balance = balance
        self.requests = requests
    }
}

/// One snapshot per device, tagged with its user and cleared on sign-out (FR-AUTH-005).
public actor VacationCache {
    private let fileURL: URL?
    private var memory: VacationSnapshot?

    public init(fileURL: URL? = nil) { self.fileURL = fileURL }

    public static func defaultFileURL() -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appending(path: "vacation-overview.json")
    }

    public func save(_ snapshot: VacationSnapshot) {
        memory = snapshot
        guard let fileURL else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }

    public func load(userKey: String) -> VacationSnapshot? {
        if memory == nil, let fileURL, let data = try? Data(contentsOf: fileURL) {
            memory = try? JSONDecoder().decode(VacationSnapshot.self, from: data)
        }
        guard let memory, memory.userKey == userKey else { return nil }
        return memory
    }

    public func clear() {
        memory = nil
        if let fileURL { try? FileManager.default.removeItem(at: fileURL) }
    }
}

/// Used when the API is not configured.
public struct UnconfiguredVacationService: VacationService {
    public init() {}
    public func balance(accessToken: String) async throws -> VacationBalance { throw Self.failure }
    public func requests(accessToken: String) async throws -> [VacationRequestSummary] { throw Self.failure }
    public func holidays(year: Int, accessToken: String) async throws -> VacationHolidays { throw Self.failure }
    public func propose(start: CalendarDay, end: CalendarDay, accessToken: String) async throws -> VacationProposal {
        throw Self.failure
    }
    public func confirm(_ proposal: VacationProposal, accessToken: String) async throws -> String { throw Self.failure }
    public func submit(
        start: CalendarDay, end: CalendarDay, confirmationToken: String, accessToken: String
    ) async throws -> VacationRequestSummary { throw Self.failure }
    public func request(id: String, accessToken: String) async throws -> VacationRequestSummary { throw Self.failure }
    public func confirmCancel(id: String, accessToken: String) async throws -> String { throw Self.failure }
    public func cancel(id: String, confirmationToken: String, accessToken: String) async throws
        -> VacationRequestSummary { throw Self.failure }
    public func inbox(accessToken: String) async throws -> [VacationRequestSummary] { throw Self.failure }
    public func confirmDecision(
        id: String, decision: VacationDecision, reason: String?, accessToken: String
    ) async throws -> String { throw Self.failure }
    public func decide(
        id: String, decision: VacationDecision, reason: String?, confirmationToken: String, accessToken: String
    ) async throws -> VacationRequestSummary { throw Self.failure }
    private static var failure: VacationError { .failed(code: "NOT_CONFIGURED", correlationId: nil) }
}
