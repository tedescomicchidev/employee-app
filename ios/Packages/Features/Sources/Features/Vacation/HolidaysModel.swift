import Core
import Foundation
import Observation

/// Holidays of the user's own work canton for one year (FR-VAC-006.3). The canton and the list come from `api/`.
@MainActor @Observable
public final class HolidaysModel {
    public enum State: Equatable {
        case loading
        case content(VacationHolidays)
        case empty(VacationHolidays)
        case cantonMissing
        case offline
        case error(code: String?, correlationId: String?)
    }

    public private(set) var state: State = .loading
    public let year: Int

    private let service: any VacationService
    private let access: VacationAccess

    init(service: any VacationService, access: VacationAccess, year: Int) {
        self.service = service
        self.access = access
        self.year = year
    }

    public convenience init(
        service: any VacationService,
        accessToken: @escaping @Sendable () async throws -> String,
        onReauthNeeded: @escaping @MainActor () -> Void,
        year: Int
    ) {
        self.init(
            service: service, access: VacationAccess(accessToken: accessToken, onReauthNeeded: onReauthNeeded),
            year: year)
    }

    public func load() async {
        state = .loading
        do {
            let year = year
            let holidays = try await access.call { token in try await service.holidays(year: year, accessToken: token) }
            state = holidays.items.isEmpty ? .empty(holidays) : .content(holidays)
        } catch VacationError.cantonMissing {
            state = .cantonMissing
        } catch VacationError.offline {
            state = .offline
        } catch let error as VacationError {
            if case let .failed(code, correlationId) = error {
                state = .error(code: code, correlationId: correlationId)
            } else {
                state = .error(code: error.code, correlationId: nil)
            }
        } catch {
            state = .error(code: nil, correlationId: nil)
        }
    }
}
