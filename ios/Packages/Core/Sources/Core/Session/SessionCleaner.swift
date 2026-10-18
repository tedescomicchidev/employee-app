import Foundation

/// Sign-out clears tokens, cached data, scheduled notifications and agent conversation state
/// (FR-AUTH-005). Features register a hook for what they own. A re-sign-in after expiry does
/// not call this, so unsent drafts survive.
public actor SessionCleaner {
    public typealias Hook = @Sendable () async -> Void
    private var hooks: [Hook] = []

    public init() {}

    public func register(_ hook: @escaping Hook) { hooks.append(hook) }

    public func clearAll() async {
        for hook in hooks { await hook() }
    }
}

/// Unsent drafts: non-sensitive fields only, in memory, scoped by user. Cleared on sign-out.
public actor DraftStore {
    private var drafts: [String: [String: String]] = [:]

    public init() {}

    public func save(_ fields: [String: String], key: String) { drafts[key] = fields }
    public func draft(key: String) -> [String: String]? { drafts[key] }
    public func clear() { drafts.removeAll() }
}
