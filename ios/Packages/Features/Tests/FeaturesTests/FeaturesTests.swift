import Core
import Foundation
import Testing
@testable import Features

private func session(_ roles: Set<Role>) -> Session {
    Session(oid: "o", displayName: "Anna Muster", upn: "a@x", roles: roles, tenantID: "t")
}

@Test("FR-AUTH-002: only managers get the Approvals tab")
func tabsFollowRoles() {
    #expect(AppTab.tabs(for: session([.employee])) == [.announcements, .vacation, .week, .more])
    #expect(AppTab.tabs(for: session([.employee, .manager])).contains(.approvals))
    #expect(AppTab.tabs(for: session([.communicator, .manager, .employee])).count == 5)
    #expect(!AppTab.tabs(for: nil).contains(.approvals))
}

#if DEBUG
private actor Flag {
    private(set) var value = false
    func set() { value = true }
}

@MainActor
private func makeModel(_ scenario: StubScenario, signedIn: Bool = false) -> (AppModel, StubAuthService) {
    let stub = StubAuthService(scenario: scenario, signedIn: signedIn)
    return (AppModel(auth: stub, me: stub, cleaner: SessionCleaner()), stub)
}

@MainActor
@Suite("FR-AUTH app model")
struct AppModelTests {
    @Test("FR-AUTH-001: no cached account shows sign-in; agent surface (tabs) unreachable")
    func startsSignedOut() async {
        let (model, _) = makeModel(.employee)
        await model.start()
        #expect(model.phase == .signedOut)
        #expect(model.session == nil)
    }

    @Test("FR-AUTH-001: cached account is restored silently with roles from /me")
    func restoresSession() async {
        let (model, _) = makeModel(.manager, signedIn: true)
        await model.start()
        #expect(model.session?.displayName == "Maria Keller")
        #expect(model.session?.has(.manager) == true)
    }

    @Test("FR-AUTH-001: sign-in lands on home with identity")
    func signInSucceeds() async {
        let (model, _) = makeModel(.publisher)
        await model.start()
        await model.signIn()
        #expect(model.session?.primaryRole == .communicator)
        #expect(model.issue == nil)
    }

    @Test("FR-AUTH-001: cancelled, failed, offline and not-allowed sign-ins show an issue")
    func failures() async {
        let expected: [(StubScenario, AppModel.Issue)] = [
            (.cancelled, .cancelled), (.failed, .failed), (.offline, .offline), (.notAllowed, .notAllowed),
        ]
        for (scenario, issue) in expected {
            let (model, _) = makeModel(scenario)
            await model.start()
            await model.signIn()
            #expect(model.phase == .signedOut)
            #expect(model.issue == issue)
        }
    }

    @Test("FR-AUTH-001: an unavailable auth SDK is reported as such, not as missing configuration")
    func unavailableIsDistinct() async {
        struct Unavailable: AuthService, MeService {
            func hasCachedAccount() async -> Bool { false }
            func signIn() async throws { throw AuthError.failed(.unavailable) }
            func accessToken() async throws -> String { throw AuthError.interactionRequired }
            func signOut() async throws {}
            func me(accessToken: String) async throws -> Session { throw AuthError.failed(.unavailable) }
        }
        let service = Unavailable()
        let model = AppModel(auth: service, me: service, cleaner: SessionCleaner())
        await model.start()
        await model.signIn()
        #expect(model.issue == .unavailable)
        #expect(model.issue != .misconfigured)
    }

    @Test("FR-AUTH-005: expired refresh asks to sign in again and keeps the session on screen")
    func expiry() async {
        let (model, stub) = makeModel(.employee, signedIn: true)
        await model.start()
        await stub.expireSession()
        await model.reload()
        #expect(model.needsReauth)
        #expect(model.session != nil)
        await model.reauthenticate()
        #expect(!model.needsReauth)
    }

    @Test("FR-AUTH-005: drafts survive re-sign-in and are cleared by sign-out")
    func draftsAndSignOut() async {
        let stub = StubAuthService(scenario: .employee, signedIn: true)
        let drafts = DraftStore()
        let cleaner = SessionCleaner()
        await cleaner.register { await drafts.clear() }
        let model = AppModel(auth: stub, me: stub, cleaner: cleaner)
        await model.start()
        await drafts.save(["title": "Entwurf"], key: "compose")

        await stub.expireSession()
        await model.reload()
        await model.reauthenticate()
        #expect(await drafts.draft(key: "compose") != nil)

        await model.signOut()
        #expect(model.phase == .signedOut)
        #expect(await drafts.draft(key: "compose") == nil)
        await #expect(throws: AuthError.interactionRequired) { try await stub.accessToken() }
    }

    @Test("FR-AUTH-005: returning to the foreground with a dead refresh token opens re-sign-in")
    func foregroundCheck() async {
        let (model, stub) = makeModel(.employee, signedIn: true)
        await model.start()
        await model.checkSession()
        #expect(!model.needsReauth)
        await stub.expireSession()
        await model.checkSession()
        #expect(model.needsReauth)
        #expect(model.session != nil)
    }

    @Test("FR-AUTH-005: sign-out clears local state even when removing the account fails, and says so")
    func signOutFailureStillClears() async {
        struct FailingSignOut: AuthService {
            func hasCachedAccount() async -> Bool { true }
            func signIn() async throws {}
            func accessToken() async throws -> String { "t" }
            func signOut() async throws { throw AuthError.failed(.generic) }
        }
        let stub = StubAuthService(scenario: .employee, signedIn: true)
        let drafts = DraftStore()
        let cleaner = SessionCleaner()
        await cleaner.register { await drafts.clear() }
        await drafts.save(["title": "x"], key: "k")
        let model = AppModel(auth: FailingSignOut(), me: stub, cleaner: cleaner)
        await model.start()
        await model.signOut()
        #expect(model.phase == .signedOut)
        #expect(model.issue == .failed)
        #expect(await drafts.draft(key: "k") == nil)
    }

    @Test("FR-AUTH-005: sign-out empties drafts, the cached feed, the cached balance and runs the app's hooks")
    func signOutClearsEveryStore() async {
        let stub = StubAuthService(scenario: .employee, signedIn: true)
        let environment = AppEnvironment(auth: stub, me: stub, mode: ModeStore())
        let ran = Flag()
        await environment.registerSessionCleanup(also: [{ await ran.set() }])
        await environment.drafts.save(["title": "x"], key: "k")
        await environment.feedCache.save(FeedSnapshot(userKey: "u1", fetchedAt: Date(), items: []))
        await environment.vacationCache.save(VacationSnapshot(
            userKey: "u1", fetchedAt: Date(),
            balance: VacationBalance(year: 2026, entitlement: 25, carriedOver: 0, approved: 5, pending: 0, remaining: 20),
            requests: []))
        let model = AppModel(auth: stub, me: stub, cleaner: environment.cleaner)
        await model.start()
        await model.signOut()
        #expect(await environment.drafts.draft(key: "k") == nil)
        #expect(await environment.feedCache.load(userKey: "u1") == nil)
        #expect(await environment.vacationCache.load(userKey: "u1") == nil)
        #expect(await ran.value)
    }

    @Test("FR-AUTH-005: offline reload keeps the cached session and flags offline")
    func offlineReload() async {
        actor FlakyMe: MeService {
            private var calls = 0
            func me(accessToken: String) async throws -> Session {
                calls += 1
                if calls > 1 { throw AuthError.offline }
                return .stub(.employee)
            }
        }
        let stub = StubAuthService(scenario: .employee, signedIn: true)
        let model = AppModel(auth: stub, me: FlakyMe(), cleaner: SessionCleaner())
        await model.start()
        #expect(model.session != nil)
        await model.reload()
        #expect(model.session != nil)
        #expect(model.isOffline)
        #expect(!model.needsReauth)
    }
}
#endif

@Suite("Localisation")
struct LocalisationTests {
    @Test("NFR-009: every key in the Features catalog has DE, FR, IT and EN")
    func catalogComplete() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Sources/Features/Resources/Localizable.xcstrings")
        let json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let strings = try #require(json["strings"] as? [String: [String: Any]])
        #expect(!strings.isEmpty)
        // Xcode adds an empty "" entry for `Text("")` literals; it has nothing to translate.
        for (key, entry) in strings where !key.isEmpty {
            let locs = try #require(entry["localizations"] as? [String: [String: Any]], "\(key)")
            #expect(Set(locs.keys) == ["en", "de", "fr", "it"], "\(key)")
            for (lang, loc) in locs {
                // A plain string has one unit; a plural has one per category (one, other).
                var units = [loc["stringUnit"] as? [String: String]]
                if let plural = (loc["variations"] as? [String: Any])?["plural"] as? [String: [String: Any]] {
                    units = plural.values.map { $0["stringUnit"] as? [String: String] }
                }
                #expect(!units.isEmpty, "\(key) \(lang)")
                for unit in units {
                    #expect(unit?["state"] == "translated", "\(key) \(lang)")
                    #expect((unit?["value"] ?? "").isEmpty == false, "\(key) \(lang)")
                }
            }
        }
    }
}
