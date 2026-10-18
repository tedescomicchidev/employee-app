import Foundation
import Testing
@testable import EmployeeApp

@Suite("FR-AUTH-001 auth configuration")
struct AuthConfigurationTests {
    private let real: [String: Any] = [
        "EntraClientID": "11111111-1111-1111-1111-111111111111",
        "EntraTenantID": "22222222-2222-2222-2222-222222222222",
        "ApiClientID": "33333333-3333-3333-3333-333333333333",
        "ApiBaseURL": "https://api.contoso.test",
    ]

    @Test("placeholder ids mean not configured")
    func placeholders() {
        var info = real
        info["EntraClientID"] = "00000000-0000-0000-0000-000000000000"
        #expect(AuthConfiguration(info: info) == nil)
        info = real
        info["ApiBaseURL"] = "https://api.example.invalid"
        #expect(AuthConfiguration(info: info) == nil)
        #expect(AuthConfiguration(info: ["EntraClientID": "$(ENTRA_CLIENT_ID)"]) == nil)
    }

    @Test("real ids produce the API scope and tenant authority")
    func configured() throws {
        let config = try #require(AuthConfiguration(info: real))
        #expect(config.scopes == ["api://33333333-3333-3333-3333-333333333333/access_as_user"])
        #expect(config.authorityURL.absoluteString == "https://login.microsoftonline.com/22222222-2222-2222-2222-222222222222")
    }

    @Test("no secret keys are read from Info.plist")
    func noSecrets() {
        let source = ["EntraClientID", "EntraTenantID", "ApiClientID", "ApiBaseURL"]
        #expect(!source.contains { $0.localizedCaseInsensitiveContains("secret") })
    }
}
