import Foundation
import Testing
@testable import Core

private final class MockURLProtocol: URLProtocol, @unchecked Sendable { // static handler is set per test
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) -> (Int, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let (status, data) = Self.handler?(request) ?? (500, Data())
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite("FR-AUTH me service", .serialized)
struct MeServiceTests {
    private func service() -> URLSessionMeService {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSessionMeService(baseURL: URL(string: "https://api.example.test")!,
                                   session: URLSession(configuration: config))
    }

    @Test("FR-AUTH-001/002: /me payload becomes a Session with roles")
    func decodesRoles() async throws {
        MockURLProtocol.handler = { request in
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer tok")
            #expect(request.url?.path == "/v1/me")
            let json = #"{"oid":"o1","display_name":"Anna","upn":"a@x","roles":["Manager","Employee","Bogus"],"tenant_id":"t"}"#
            return (200, Data(json.utf8))
        }
        let session = try await service().me(accessToken: "tok")
        #expect(session.displayName == "Anna")
        #expect(session.roles == [.manager, .employee])
        #expect(session.primaryRole == .manager)
    }

    @Test("FR-AUTH-001: 401 and 403 mean the account is not allowed")
    func rejected() async {
        for status in [401, 403] {
            MockURLProtocol.handler = { _ in (status, Data()) }
            await #expect(throws: AuthError.failed(.accountNotAllowed)) {
                try await service().me(accessToken: "tok")
            }
        }
    }
}

@Suite("FR-AUTH session")
struct SessionTests {
    @Test("FR-AUTH-002: primary role is the highest privilege")
    func primaryRole() {
        func session(_ roles: Set<Role>) -> Session {
            Session(oid: "o", displayName: "n", upn: "u", roles: roles, tenantID: "t")
        }
        #expect(session([.employee]).primaryRole == .employee)
        #expect(session([.employee, .manager]).primaryRole == .manager)
        #expect(session([.employee, .manager, .communicator]).primaryRole == .communicator)
        #expect(session([]).primaryRole == .employee)
    }

    @Test("FR-AUTH-005: sign-out hooks run, drafts are cleared")
    func cleanerRunsHooks() async {
        let drafts = DraftStore()
        await drafts.save(["title": "Früher Start"], key: "compose")
        let cleaner = SessionCleaner()
        await cleaner.register { await drafts.clear() }
        #expect(await drafts.draft(key: "compose") != nil)
        await cleaner.clearAll()
        #expect(await drafts.draft(key: "compose") == nil)
    }

    @Test("FR-AUTH-005: drafts survive until clearAll (re-sign-in keeps them)")
    func draftsSurviveWithoutClear() async {
        let drafts = DraftStore()
        await drafts.save(["a": "b"], key: "k")
        #expect(await drafts.draft(key: "k") == ["a": "b"])
    }
}

#if DEBUG
@Suite("FR-AUTH stub auth")
struct StubAuthTests {
    @Test("FR-AUTH-001: stub scenarios map to the expected outcomes")
    func scenarios() async throws {
        let ok = StubAuthService(scenario: .manager)
        await #expect(throws: AuthError.interactionRequired) { try await ok.accessToken() }
        try await ok.signIn()
        #expect(try await ok.accessToken() == "stub-token")
        #expect(await ok.me(accessToken: "x").has(.manager))

        await #expect(throws: AuthError.cancelled) { try await StubAuthService(scenario: .cancelled).signIn() }
        await #expect(throws: AuthError.offline) { try await StubAuthService(scenario: .offline).signIn() }
        await #expect(throws: AuthError.failed(.generic)) { try await StubAuthService(scenario: .failed).signIn() }
    }

    @Test("FR-AUTH-005: expired session needs a new sign-in")
    func expiry() async throws {
        let stub = StubAuthService(scenario: .employee, signedIn: true)
        _ = try await stub.accessToken()
        await stub.expireSession()
        await #expect(throws: AuthError.interactionRequired) { try await stub.accessToken() }
        try await stub.signIn()
        _ = try await stub.accessToken()
    }
}
#endif
