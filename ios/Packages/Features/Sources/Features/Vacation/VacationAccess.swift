import Core
import Foundation

/// Gets a fresh access token for each API call and reports a lost session; shared by the vacation models.
/// A failed silent refresh opens the re-sign-in sheet and never lets a write go out with a stale token (FR-AUTH-005).
@MainActor
struct VacationAccess {
    let accessToken: @Sendable () async throws -> String
    let onReauthNeeded: @MainActor () -> Void
    /// The run id of the task flow this model reports into; its calls carry it (EXP-005).
    var runId: @MainActor () -> UUID? = { nil }

    func call<T: Sendable>(_ work: (String) async throws -> T) async throws -> T {
        let token: String
        do {
            token = try await accessToken()
        } catch AuthError.interactionRequired {
            onReauthNeeded()
            throw VacationError.unauthenticated
        } catch AuthError.offline {
            throw VacationError.offline
        } catch {
            throw VacationError.failed(code: "AUTH", correlationId: nil)
        }
        do {
            return try await TaskRun.$current.withValue(runId()) { try await work(token) }
        } catch VacationError.unauthenticated {
            onReauthNeeded()
            throw VacationError.unauthenticated
        }
    }
}
