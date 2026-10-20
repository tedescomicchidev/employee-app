import Core
import Foundation
import Observation

/// Settings row for the weekly briefing (FR-BRF-001.4): shows the current opt-in state and changes it.
/// Turning it on or off is a write, so the system alert that names what is accessed is its review screen
/// and only its confirm button mints the token (FR-AUTH-006).
@MainActor @Observable
public final class BriefingSettingsModel {
    public enum State: Equatable, Sendable {
        case loading
        case ready(optedIn: Bool)
        /// The state is unknown (offline or failed): the toggle is disabled, never guessed.
        case unavailable(offline: Bool)
    }

    public enum Reminder: Equatable, Sendable {
        case scheduled, off, denied
    }

    public private(set) var state: State = .loading
    /// The change the user asked for; the alert asks them to confirm it.
    public var pending: Bool?
    public private(set) var isWorking = false
    public private(set) var failedCode: String?
    public private(set) var reminder: Reminder = .off

    private let service: any BriefingService
    private var access: BriefingAccess
    private let reminderService: BriefingReminder
    private let reminderTitle: @Sendable () -> String

    public init(
        service: any BriefingService,
        accessToken: @escaping @Sendable () async throws -> String,
        onReauthNeeded: @escaping @MainActor () -> Void,
        reminder: BriefingReminder,
        reminderTitle: @escaping @Sendable () -> String
    ) {
        self.service = service
        self.access = BriefingAccess(accessToken: accessToken, onReauthNeeded: onReauthNeeded)
        self.reminderService = reminder
        self.reminderTitle = reminderTitle
    }

    public var optedIn: Bool? {
        if case let .ready(on) = state { on } else { nil }
    }

    public func load() async {
        do {
            let status = try await access.call { token in try await service.status(accessToken: token) }
            state = .ready(optedIn: status.optedIn)
        } catch BriefingError.offline {
            state = .unavailable(offline: true)
        } catch {
            state = .unavailable(offline: false)
        }
        await refreshReminder()
    }

    /// The toggle was flipped: ask for confirmation, change nothing yet.
    public func request(_ on: Bool) {
        guard case let .ready(current) = state, current != on, !isWorking else { return }
        failedCode = nil
        pending = on
    }

    public func cancelPending() { pending = nil }

    private var task: Task<Void, Never>?

    /// The alert's confirm button. The tap is taken at once (the alert dismissing must not cancel it);
    /// the write then runs: propose, mint the token from this tap, write.
    public func confirm() {
        guard let enabled = pending, !isWorking else { return }
        pending = nil
        isWorking = true
        task = Task { await apply(enabled) }
    }

    public func waitUntilIdle() async { await task?.value }

    private func apply(_ enabled: Bool) async {
        failedCode = nil
        defer { isWorking = false }
        do {
            let status = try await access.call { token in
                let proposal = try await service.proposeOptIn(enabled: enabled, accessToken: token)
                let confirmation = try await service.confirmOptIn(proposal, accessToken: token)
                return try await service.setOptIn(
                    enabled: enabled, confirmationToken: confirmation, accessToken: token)
            }
            state = .ready(optedIn: status.optedIn)
            if status.optedIn {
                // Asked in context, right after the user turned it on.
                if await reminderService.authorization() == .notDetermined {
                    _ = await reminderService.requestAuthorization()
                }
                await reminderService.schedule(title: reminderTitle())
            } else {
                await reminderService.cancel()  // FR-BRF-001.3, FR-BRF-003.3: removed at once
            }
        } catch BriefingError.offline {
            state = .unavailable(offline: true)
        } catch let error as BriefingError {
            failedCode = error.code
        } catch {
            failedCode = "UNKNOWN"
        }
        await refreshReminder()
    }

    public func refreshReminder() async {
        switch await reminderService.authorization() {
        case .denied: reminder = .denied
        case .notDetermined: reminder = .off
        case .allowed: reminder = await reminderService.isScheduled() ? .scheduled : .off
        }
    }
}
