#if DEBUG
import Foundation

public enum BriefingStubScenario: String, Sendable, CaseIterable {
    /// Opted in, six events in the week of 2026-10-19 (two overlap on Monday).
    case ok
    /// Not opted in yet: the opt-in screen.
    case optIn
    /// Opted in, an empty calendar.
    case empty
    /// Opted in; Thursday and Friday could not be read.
    case partial
    case loading, offline
    case workIQUnavailable, noLicence, consentRequired
    /// The opt-in write fails.
    case optInFails
    /// The opt-in write never answers: the "turning on" state.
    case optInWorking
}

/// Stub for UI tests and screenshots (DEBUG only). `api/` stays the only real authority; this mirrors the
/// shape of its answers for the fixture week of docs/product/test-cases.md.
public actor StubBriefingService: BriefingService {
    private let scenario: BriefingStubScenario
    private var optedIn: Bool
    private let delay: Duration
    public private(set) var weekCalls = 0

    public init(scenario: BriefingStubScenario = .ok, delay: Duration = .zero) {
        self.scenario = scenario
        self.optedIn = scenario != .optIn && scenario != .optInWorking && scenario != .optInFails
        self.delay = delay
    }

    public func status(accessToken: String) async throws -> BriefingStatus {
        if scenario == .offline { throw BriefingError.offline }
        return BriefingStatus(optedIn: optedIn)
    }

    public func week(accessToken: String) async throws -> BriefingWeek {
        weekCalls += 1
        switch scenario {
        case .loading:
            try await Task.sleep(for: .seconds(3600))
            throw BriefingError.timedOut
        case .offline: throw BriefingError.offline
        case .workIQUnavailable: throw BriefingError.workIQUnavailable
        case .noLicence: throw BriefingError.noLicence
        case .consentRequired: throw BriefingError.consentRequired
        default: break
        }
        if delay > .zero { try await Task.sleep(for: delay) }
        guard optedIn else { throw BriefingError.notOptedIn }
        return Self.week(scenario)
    }

    public func proposeOptIn(enabled: Bool, accessToken: String) async throws -> BriefingOptInProposal {
        if scenario == .offline { throw BriefingError.offline }
        return BriefingOptInProposal(id: "stub-proposal", enabled: enabled)
    }

    public func confirmOptIn(_ proposal: BriefingOptInProposal, accessToken: String) async throws -> String {
        "stub-confirmation-token-0123456789"
    }

    public func setOptIn(enabled: Bool, confirmationToken: String, accessToken: String) async throws -> BriefingStatus {
        if scenario == .optInFails { throw BriefingError.failed(code: "INTERNAL", correlationId: nil) }
        if scenario == .optInWorking { try await Task.sleep(for: .seconds(3600)) }
        if scenario == .offline { throw BriefingError.offline }
        optedIn = enabled
        return BriefingStatus(optedIn: enabled)
    }

    // MARK: Fixture week (Monday 2026-10-19, Europe/Zurich)

    static let monday = CalendarDay(year: 2026, month: 10, day: 19)

    private static func at(_ offset: Int, _ hour: Int, _ minute: Int) -> Date {
        var calendar = Calendar.zurich
        calendar.timeZone = TimeZone(identifier: "Europe/Zurich") ?? .current
        let day = monday.addingDays(offset)
        return calendar.date(from: DateComponents(
            year: day.year, month: day.month, day: day.day, hour: hour, minute: minute)) ?? Date(timeIntervalSince1970: 0)
    }

    public static func week(_ scenario: BriefingStubScenario) -> BriefingWeek {
        let events: [Int: [BriefingEvent]] = scenario == .empty ? [:] : [
            0: [
                BriefingEvent(
                    id: "e1", title: "Team standup", start: at(0, 9, 0), end: at(0, 9, 30), online: true,
                    attendeeCount: 6, conflictsWith: ["e2"]),
                BriefingEvent(
                    id: "e2", title: "Budget review", start: at(0, 9, 15), end: at(0, 10, 15), location: "Room 4",
                    attendeeCount: 3, conflictsWith: ["e1"]),
            ],
            1: [BriefingEvent(
                id: "e3", title: "Store visit Zurich", start: at(1, 13, 0), end: at(1, 15, 0), location: "Zurich",
                attendeeCount: 2)],
            2: [
                BriefingEvent(
                    id: "e4", title: "One-to-one with manager", start: at(2, 10, 0), end: at(2, 10, 30),
                    attendeeCount: 1),
                BriefingEvent(
                    id: "e5", title: "Safety training", start: at(2, 14, 0), end: at(2, 16, 0), attendeeCount: 12),
            ],
            4: [BriefingEvent(
                id: "e6", title: "Quarterly planning", start: at(4, 11, 0), end: at(4, 12, 0), online: true,
                attendeeCount: 8)],
        ]
        let missing: Set<Int> = scenario == .partial ? [3, 4] : []
        let days = (0..<7).map { offset -> BriefingDay in
            let shown = missing.contains(offset) ? [] : events[offset] ?? []
            let free: [BriefingFreeBlock] = offset < 5 && !missing.contains(offset)
                ? [BriefingFreeBlock(start: at(offset, 10, 30), end: at(offset, 12, 0), minutes: 90)] : []
            return BriefingDay(
                day: monday.addingDays(offset), events: shown, freeBlocks: free, missing: missing.contains(offset))
        }
        let count = Set(days.flatMap(\.events).map(\.id)).count
        return BriefingWeek(
            start: monday, end: monday.addingDays(6), days: days, eventCount: count,
            conflictCount: days.flatMap(\.events).filter(\.hasConflict).count / 2)
    }
}
#endif

/// Notification centre for UI tests and screenshots (DEBUG only): no system prompt, nothing delivered.
public actor StubNotificationCentre: NotificationCentre {
    private var state: NotificationAuthorization
    private var pending: Set<String> = []

    public init(_ state: NotificationAuthorization = .notDetermined) { self.state = state }

    public func authorization() async -> NotificationAuthorization { state }

    public func requestAuthorization() async -> Bool {
        if state == .notDetermined { state = .allowed }
        return state == .allowed
    }

    public func scheduleWeekly(identifier: String, title: String) async throws { pending.insert(identifier) }
    public func cancel(identifiers: [String]) async { pending.subtract(identifiers) }
    public func pendingIdentifiers() async -> [String] { Array(pending) }
}
