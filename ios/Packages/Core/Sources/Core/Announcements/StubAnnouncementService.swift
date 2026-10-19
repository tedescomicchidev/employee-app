#if DEBUG
import Foundation

public enum AnnouncementStubScenario: String, Sendable, CaseIterable {
    case ok, validation, publishFails, publishOffline, offline, forbidden
    case feedEmpty, feedError, feedLoading, feedOffline
    /// The first review gets a 401 (revoked token); after signing in again calls succeed (FR-AUTH-005).
    case sessionRevoked
}

/// Stub for UI tests and screenshots (DEBUG only). Counts publish calls so tests can assert "once".
public actor StubAnnouncementService: AnnouncementService {
    public private(set) var publishCalls = 0
    private var revoked = false
    public private(set) var markReadCalls: [String] = []
    private let scenario: AnnouncementStubScenario
    private let recipients: Int
    private var items: [AnnouncementItem]

    public init(scenario: AnnouncementStubScenario = .ok, recipients: Int = 11, now: Date = Date()) {
        self.scenario = scenario
        self.recipients = recipients
        self.items = scenario == .feedEmpty ? [] : Self.feed(now: now)
    }

    /// Mirrors the mockup feed: two unread, two read, one in Italian.
    public static func feed(now: Date) -> [AnnouncementItem] {
        func ago(_ hours: Double) -> Date { now.addingTimeInterval(-hours * 3600) }
        return [
            AnnouncementItem(
                id: "a4", title: "Neue Öffnungszeiten ab November",
                body: "Liebe Kolleginnen und Kollegen\n\nAb Montag, 2. November, gelten in allen Filialen angepasste Öffnungszeiten. Die Details zu Schichtplänen und Pausen findet ihr in der Filialleitung.\n\nMehr dazu: https://intranet.example/oeffnungszeiten\n\nBesten Dank für euren Einsatz.",
                language: .de, author: "Geschäftsleitung", publishedAt: ago(1), read: false),
            AnnouncementItem(
                id: "a3", title: "Inventario filiale di Lugano",
                body: "Venerdì l'inventario inizia alle 18:00. Si prega di completare il rifornimento prima.",
                language: .it, author: "Logistica", publishedAt: ago(26), read: false,
                audience: AudienceSelection(everyone: false, stores: ["Store-Lugano"])),
            AnnouncementItem(
                id: "a2", title: "Sicherheitsunterweisung im Lager",
                body: "Die jährliche Unterweisung findet in den kommenden zwei Wochen statt.",
                language: .de, author: "Logistik", publishedAt: ago(24 * 6), read: true),
            AnnouncementItem(
                id: "a1", title: "Herbstaktion: Plakate ab Montag",
                body: "Das Material liegt ab Montag in den Filialen bereit.",
                language: .de, author: "Marketing", publishedAt: ago(24 * 10), read: true),
        ]
    }

    public func propose(_ draft: AnnouncementDraft, accessToken: String) throws -> AnnouncementProposal {
        switch scenario {
        case .forbidden: throw AnnouncementError.forbidden
        case .offline: throw AnnouncementError.offline
        case .sessionRevoked where !revoked:
            revoked = true
            throw AnnouncementError.unauthenticated
        default: break
        }
        if draft.title.isEmpty { throw AnnouncementError.validation(.title) }
        if draft.body.isEmpty { throw AnnouncementError.validation(.body) }
        if scenario == .validation { throw AnnouncementError.validation(.title) }
        return AnnouncementProposal(
            id: "stub-proposal", draft: draft, recipientCount: try Self.count(draft.audience, all: recipients))
    }

    public func confirm(_ proposal: AnnouncementProposal, accessToken: String) throws -> String {
        "stub-token"
    }

    public func publish(
        _ draft: AnnouncementDraft, confirmationToken: String, accessToken: String
    ) throws -> PublishedAnnouncement {
        publishCalls += 1
        switch scenario {
        case .publishFails: throw AnnouncementError.failed(code: "INTERNAL", correlationId: "stub-corr-1234")
        case .offline, .publishOffline: throw AnnouncementError.offline
        default: return PublishedAnnouncement(id: "stub-announcement", recipientCount: recipients)
        }
    }

    public func list(accessToken: String) async throws -> [AnnouncementItem] {
        switch scenario {
        case .feedError: throw AnnouncementError.failed(code: "INTERNAL", correlationId: "stub-corr-5678")
        case .offline, .feedOffline: throw AnnouncementError.offline
        case .feedLoading:
            try await Task.sleep(for: .seconds(3600))
            return []
        default: return items
        }
    }

    public func markRead(id: String, accessToken: String) throws {
        markReadCalls.append(id)
        guard let index = items.firstIndex(where: { $0.id == id }) else { throw AnnouncementError.notFound }
        items[index].read = true
    }

    public func audienceOptions(accessToken: String) throws -> AudienceOptions {
        AudienceOptions(
            regions: ["DE", "FR", "IT"],
            stores: ["HQ", "Store-Bern", "Store-Geneva", "Store-Lausanne", "Store-Lugano", "Store-Zurich"],
            roles: ["Employee", "Manager", "Publisher"])
    }

    public func recipientCount(for audience: AudienceSelection, accessToken: String) throws -> Int {
        try Self.count(audience, all: recipients)
    }

    /// The fixture directory from docs/product/test-cases.md: (region, store, role) per active user.
    private static let directory: [(String, String, String)] = [
        ("DE", "HQ", "Publisher"), ("DE", "HQ", "Manager"), ("IT", "Store-Lugano", "Manager"),
        ("DE", "HQ", "Employee"), ("DE", "HQ", "Employee"), ("DE", "Store-Bern", "Employee"),
        ("IT", "Store-Lugano", "Employee"), ("IT", "Store-Lugano", "Employee"),
        ("FR", "Store-Lausanne", "Employee"), ("FR", "Store-Geneva", "Employee"),
        ("DE", "Store-Zurich", "Employee"),
    ]

    private static func count(_ audience: AudienceSelection, all: Int) throws -> Int {
        if audience.everyone { return all }
        let matching = directory.filter {
            audience.regions.contains($0.0) || audience.stores.contains($0.1) || audience.roles.contains($0.2)
        }.count
        if matching == 0 { throw AnnouncementError.emptyAudience }
        return matching
    }
}
#endif
