import Core
import Foundation
import Observation

/// One calendar week of the team view.
struct TeamWeek: Equatable, Identifiable {
    let year: Int
    let number: Int
    let days: [CoverageDay]
    var id: String { "\(year)-\(number)" }

    /// Each absent request once, in the order the API listed it, however many days it covers.
    var absences: [CoverageAbsence] {
        var seen = Set<String>()
        return days.flatMap(\.absent).filter { seen.insert($0.requestId).inserted }
    }
}

/// Team coverage for managers (FR-VAC-005): per day, how many direct reports are present and who
/// is out. All numbers are the API's; this groups them by week and reports the T-VAC-COV flow.
@MainActor @Observable
public final class TeamCoverageModel {
    public enum State: Equatable {
        case loading
        case content([CoverageDay])
        /// The API said `FORBIDDEN`: not a manager (the tab is hidden, this is the safety net).
        case forbidden
        case error(code: String?, correlationId: String?)
    }

    /// The API allows this many days at most; the app never asks for more.
    public static let maxDays = 93
    public static let defaultDays = 28

    public private(set) var state: State = .loading
    public private(set) var start: CalendarDay
    public private(set) var end: CalendarDay
    /// True while a changed range loads; the previous result stays on screen.
    public private(set) var isReloading = false
    /// Set while showing the last result because the network is gone: when it was fetched.
    public private(set) var offlineAsOf: Date?

    private let service: any VacationService
    private let access: VacationAccess
    private let makeFlow: @MainActor () -> TaskFlow
    private let now: @Sendable () -> Date
    private var flow: TaskFlow?

    init(
        service: any VacationService, access: VacationAccess, today: CalendarDay,
        makeFlow: @escaping @MainActor () -> TaskFlow, now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.service = service
        self.access = access
        self.makeFlow = makeFlow
        self.now = now
        start = today
        end = today.addingDays(Self.defaultDays - 1)
    }

    public convenience init(
        service: any VacationService,
        accessToken: @escaping @Sendable () async throws -> String,
        onReauthNeeded: @escaping @MainActor () -> Void,
        today: CalendarDay,
        makeFlow: @escaping @MainActor () -> TaskFlow,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.init(
            service: service, access: VacationAccess(accessToken: accessToken, onReauthNeeded: onReauthNeeded),
            today: today, makeFlow: makeFlow, now: now)
    }

    public var days: [CoverageDay] {
        if case let .content(days) = state { days } else { [] }
    }

    /// No absence anywhere in the range, or no direct reports at all.
    public var isEmpty: Bool { !days.isEmpty ? days.allSatisfy { $0.absent.isEmpty } : true }

    var weeks: [TeamWeek] {
        var order: [String] = []
        var groups: [String: (year: Int, number: Int, days: [CoverageDay])] = [:]
        for day in days {
            let parts = Self.isoWeek(day.day)
            let key = "\(parts.year)-\(parts.week)"
            if groups[key] == nil {
                order.append(key)
                groups[key] = (parts.year, parts.week, [])
            }
            groups[key]?.days.append(day)
        }
        return order.compactMap { key in
            groups[key].map { TeamWeek(year: $0.year, number: $0.number, days: $0.days) }
        }
    }

    static func isoWeek(_ day: CalendarDay) -> (year: Int, week: Int) {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = Calendar.zurich.timeZone
        let parts = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: day.date(in: calendar))
        return (parts.yearForWeekOfYear ?? day.year, parts.weekOfYear ?? 1)
    }

    // MARK: Loading

    /// The team view was opened: `task_started` for T-VAC-COV, then load.
    public func begin() async {
        if flow == nil || flow?.isFinished == true {
            flow = makeFlow()
            flow?.start()
        }
        await load()
    }

    public func refresh() async {
        flow?.tap()
        await load()
    }

    /// A new range, kept to the API's limits (end not before start, at most 93 days).
    public func setRange(start newStart: CalendarDay, end newEnd: CalendarDay) async {
        let last = max(newStart, newEnd)
        let limit = newStart.addingDays(Self.maxDays - 1)
        start = newStart
        end = min(last, limit)
        flow?.tap()
        await load()
    }

    private func load() async {
        isReloading = true
        defer { isReloading = false }
        do {
            let days = try await access.call { [start, end] token in
                try await service.coverage(start: start, end: end, accessToken: token)
            }
            offlineAsOf = nil
            state = .content(days)
            flow?.complete(outcomeValid: true)
        } catch VacationError.forbidden {
            flow?.error(code: "FORBIDDEN", recovered: false)
            state = .forbidden
        } catch VacationError.offline {
            if case .content = state {
                offlineAsOf = offlineAsOf ?? now()
                flow?.error(code: "OFFLINE", recovered: true)
            } else {
                flow?.error(code: "OFFLINE", recovered: false)
                state = .error(code: "OFFLINE", correlationId: nil)
            }
        } catch let VacationError.failed(code, correlationId) {
            flow?.error(code: code ?? "UNKNOWN", recovered: false)
            keepContentOr(.error(code: code, correlationId: correlationId))
        } catch let error as VacationError {
            flow?.error(code: error.code, recovered: false)
            keepContentOr(.error(code: error.code, correlationId: nil))
        } catch {
            keepContentOr(.error(code: nil, correlationId: nil))
        }
    }

    private func keepContentOr(_ fallback: State) {
        if case .content = state { return }
        state = fallback
    }
}
