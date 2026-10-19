import Foundation

/// `GET /v1/me` with the user's bearer token. 401/403 mean the API refused this account.
public struct URLSessionMeService: MeService {
    private struct Payload: Decodable {
        let oid: String
        let displayName: String
        let upn: String
        let roles: [String]
        let tenantId: String

        enum CodingKeys: String, CodingKey {
            case oid, upn, roles
            case displayName = "display_name"
            case tenantId = "tenant_id"
        }
    }

    private let baseURL: URL
    private let session: URLSession

    public init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    public func me(accessToken: String) async throws -> Session {
        var request = URLRequest(url: baseURL.appending(path: "v1/me"))
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        TaskRun.tag(&request)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where Self.offlineCodes.contains(error.code) {
            throw AuthError.offline
        } catch {
            throw AuthError.failed(.generic)
        }
        guard let http = response as? HTTPURLResponse else { throw AuthError.failed(.generic) }
        switch http.statusCode {
        case 200:
            guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
                throw AuthError.failed(.generic)
            }
            // Unknown role strings are ignored: the API stays the authority.
            return Session(
                oid: payload.oid, displayName: payload.displayName, upn: payload.upn,
                roles: Set(payload.roles.compactMap(Role.init(rawValue:))), tenantID: payload.tenantId)
        case 401, 403:
            throw AuthError.failed(.accountNotAllowed)
        default:
            throw AuthError.failed(.generic)
        }
    }

    private static let offlineCodes: Set<URLError.Code> = [
        .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost, .timedOut, .dataNotAllowed,
    ]
}
