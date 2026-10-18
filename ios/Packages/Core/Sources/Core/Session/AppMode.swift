import Foundation
import Observation

/// Every feature exists in both modes with identical domain rules (CLAUDE.md invariant).
public enum AppMode: String, Sendable, CaseIterable, Codable {
    case classic
    case agent
}

/// Current mode. In Release the mode is fixed by the experiment assignment (EXP-004, not built yet,
/// so `.classic`); the setter exists only in DEBUG builds.
@MainActor @Observable
public final class ModeStore {
    public private(set) var current: AppMode

    public init(initial: AppMode = .classic) { current = initial }

    #if DEBUG
    public func setForDebug(_ mode: AppMode) { current = mode }
    #endif
}
