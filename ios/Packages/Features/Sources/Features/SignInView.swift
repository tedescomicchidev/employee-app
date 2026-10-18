import Core
import SwiftUI

/// Sign-in: idle, in progress (system web auth sheet), cancelled, failed, not allowed, offline.
/// No mockup exists; built from tokens and system components.
struct SignInView: View {
    let model: AppModel

    var body: some View {
        ScrollView {
            VStack(spacing: DSSpacing.l) {
                Image(systemName: "person.badge.key.fill")
                    .font(.largeTitle)
                    .foregroundStyle(DSColor.tint)
                    .frame(width: DSSize.emptyIconDisc, height: DSSize.emptyIconDisc)
                    .background(DSColor.tintSoft, in: Circle())
                    .accessibilityHidden(true)
                VStack(spacing: DSSpacing.xs) {
                    Text(L10n.signInTitle).font(DSFont.largeTitle).accessibilityIdentifier("signin.title")
                    Text(L10n.signInSubtitle).font(DSFont.body).foregroundStyle(DSColor.ink2)
                }
                .multilineTextAlignment(.center)

                if let issue = model.issue {
                    DSBanner(issue.bannerKind, message: Text(issue.message))
                        .accessibilityIdentifier("signin.banner")
                }

                if model.phase == .signingIn {
                    DSButton(L10n.signInProgress, isBusy: true, action: {})
                        .accessibilityIdentifier("signin.button")
                } else {
                    DSButton(model.issue == nil ? L10n.signInButton : L10n.signInRetry) {
                        Task { await model.signIn() }
                    }
                    .accessibilityIdentifier("signin.button")
                }
            }
            .padding(DSSpacing.gutter)
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity)
            .padding(.top, DSSpacing.xl)
        }
        .background(DSColor.bg)
    }
}

extension AppModel.Issue {
    var message: LocalizedStringResource {
        switch self {
        case .cancelled: L10n.signInCancelled
        case .offline: L10n.signInOffline
        case .failed: L10n.signInFailed
        case .notAllowed: L10n.signInNotAllowed
        case .misconfigured: L10n.signInMisconfigured
        case .unavailable: L10n.signInUnavailable
        }
    }

    var bannerKind: DSBannerKind {
        switch self {
        case .cancelled: .info
        case .offline: .offline
        case .failed, .notAllowed, .misconfigured, .unavailable: .error
        }
    }
}

struct LoadingView: View {
    var body: some View {
        VStack(spacing: DSSpacing.m) {
            DSSkeleton(rows: 2)
        }
        .padding(DSSpacing.gutter)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(DSColor.bg)
        .accessibilityIdentifier("loading")
    }
}

#Preview("Sign in") {
    SignInView(model: AppModel(
        auth: PreviewAuth(), me: PreviewAuth(), cleaner: SessionCleaner()))
}

/// Preview-only auth that never signs in.
struct PreviewAuth: AuthService, MeService {
    func hasCachedAccount() async -> Bool { false }
    func signIn() async throws { throw AuthError.cancelled }
    func accessToken() async throws -> String { throw AuthError.interactionRequired }
    func signOut() async throws {}
    func me(accessToken: String) async throws -> Session {
        Session(oid: "p", displayName: "Anna Muster", upn: "a@x", roles: [.manager, .employee], tenantID: "t")
    }
}
