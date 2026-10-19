import Foundation

/// What the feed last fetched, kept for offline display with an "as of" time (NFR-007, FR-ANN-003.3).
public struct FeedSnapshot: Sendable, Equatable, Codable {
    public let userKey: String
    public let fetchedAt: Date
    public let items: [AnnouncementItem]

    public init(userKey: String, fetchedAt: Date, items: [AnnouncementItem]) {
        self.userKey = userKey
        self.fetchedAt = fetchedAt
        self.items = items
    }
}

/// One snapshot per device, tagged with the user it belongs to so another account never sees it.
/// Cleared on sign-out (FR-AUTH-005). A nil `fileURL` keeps it in memory (tests, previews).
public actor FeedCache {
    private let fileURL: URL?
    private var memory: FeedSnapshot?

    public init(fileURL: URL? = nil) { self.fileURL = fileURL }

    public static func defaultFileURL() -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appending(path: "announcements-feed.json")
    }

    public func save(_ snapshot: FeedSnapshot) {
        memory = snapshot
        guard let fileURL else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }

    public func load(userKey: String) -> FeedSnapshot? {
        if memory == nil, let fileURL, let data = try? Data(contentsOf: fileURL) {
            memory = try? JSONDecoder().decode(FeedSnapshot.self, from: data)
        }
        guard let memory, memory.userKey == userKey else { return nil }
        return memory
    }

    public func clear() {
        memory = nil
        if let fileURL { try? FileManager.default.removeItem(at: fileURL) }
    }
}
