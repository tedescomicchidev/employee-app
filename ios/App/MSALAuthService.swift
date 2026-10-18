import Core
import Foundation
import MSAL
import UIKit

/// MSAL sign-in. Tokens live only in MSAL's Keychain cache (access group com.microsoft.adalcache);
/// nothing is persisted or logged by the app. Pattern per
/// https://learn.microsoft.com/entra/msal/objc/acquire-tokens (silent first, interactive on
/// `interactionRequired`) and https://learn.microsoft.com/entra/msal/objc/howto-v2-keychain-objc.
@MainActor
final class MSALAuthService: AuthService {
    private let application: MSALPublicClientApplication
    private let scopes: [String]

    init(configuration: AuthConfiguration) throws {
        let authority = try MSALAADAuthority(url: configuration.authorityURL)
        // nil redirect URI: MSAL uses the default msauth.<bundle-id>://auth.
        let config = MSALPublicClientApplicationConfig(
            clientId: configuration.clientID, redirectUri: nil, authority: authority)
        application = try MSALPublicClientApplication(configuration: config)
        scopes = configuration.scopes
    }

    func hasCachedAccount() -> Bool {
        ((try? application.allAccounts()) ?? []).isEmpty == false
    }

    func signIn() async throws {
        guard let presenter = Self.topViewController() else { throw AuthError.failed(.generic) }
        let webview = MSALWebviewParameters(authPresentationViewController: presenter)
        let parameters = MSALInteractiveTokenParameters(scopes: scopes, webviewParameters: webview)
        parameters.promptType = .selectAccount
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            application.acquireToken(with: parameters) { result, error in
                if let error {
                    continuation.resume(throwing: Self.map(error))
                } else if result != nil {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: AuthError.failed(.generic))
                }
            }
        }
    }

    func accessToken() async throws -> String {
        guard let account = try? application.allAccounts().first else { throw AuthError.interactionRequired }
        let parameters = MSALSilentTokenParameters(scopes: scopes, account: account)
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            application.acquireTokenSilent(with: parameters) { result, error in
                if let token = result?.accessToken {
                    continuation.resume(returning: token)
                } else {
                    continuation.resume(throwing: error.map(Self.map) ?? AuthError.failed(.generic))
                }
            }
        }
    }

    /// Removes the cached accounts and their tokens from the Keychain.
    func signOut() async throws {
        for account in try application.allAccounts() {
            try application.remove(account)
        }
    }

    private nonisolated static func map(_ error: Error) -> AuthError {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorNotConnectedToInternet {
            return .offline
        }
        guard nsError.domain == MSALErrorDomain else { return .failed(.generic) }
        switch MSALError(rawValue: nsError.code) {
        case .userCanceled: return .cancelled
        case .interactionRequired: return .interactionRequired
        default:
            let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError
            if underlying?.domain == NSURLErrorDomain, underlying?.code == NSURLErrorNotConnectedToInternet {
                return .offline
            }
            return .failed(.generic)
        }
    }

    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        var controller = scene?.keyWindow?.rootViewController
        while let presented = controller?.presentedViewController { controller = presented }
        return controller
    }
}

/// Used when the Entra ids are still placeholders: sign-in explains it instead of crashing.
struct UnconfiguredAuthService: AuthService, MeService {
    func hasCachedAccount() async -> Bool { false }
    func signIn() async throws { throw AuthError.failed(.misconfigured) }
    func accessToken() async throws -> String { throw AuthError.interactionRequired }
    func signOut() async throws {}
    func me(accessToken: String) async throws -> Session { throw AuthError.failed(.misconfigured) }
}
