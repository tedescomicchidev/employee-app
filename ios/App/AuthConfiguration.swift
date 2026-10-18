import Foundation

/// Non-secret Entra identifiers from Info.plist (fed by Config/*.xcconfig).
struct AuthConfiguration: Equatable {
    let clientID: String
    let tenantID: String
    let apiClientID: String
    let apiBaseURL: URL

    var scopes: [String] { ["api://\(apiClientID)/access_as_user"] }
    var authorityURL: URL { URL(string: "https://login.microsoftonline.com/\(tenantID)")! }

    /// `nil` while any identifier is still the checked-in placeholder.
    init?(info: [String: Any]) {
        func value(_ key: String) -> String? {
            guard let raw = info[key] as? String, !raw.isEmpty, !raw.hasPrefix("$("),
                  raw != "00000000-0000-0000-0000-000000000000"
            else { return nil }
            return raw
        }
        guard let clientID = value("EntraClientID"), let tenantID = value("EntraTenantID"),
              let apiClientID = value("ApiClientID"),
              let base = value("ApiBaseURL"), let url = URL(string: base), url.host() != "api.example.invalid"
        else { return nil }
        self.clientID = clientID
        self.tenantID = tenantID
        self.apiClientID = apiClientID
        self.apiBaseURL = url
    }

    static func load(bundle: Bundle = .main) -> AuthConfiguration? {
        AuthConfiguration(info: bundle.infoDictionary ?? [:])
    }
}
