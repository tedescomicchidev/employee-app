import Core
import Foundation

/// Typed keys for Resources/Localizable.xcstrings (DE/FR/IT/EN). No string literals in views.
enum L10n {
    private static var bundle: LocalizedStringResource.BundleDescription {
        .atURL(Bundle.module.bundleURL)
    }

    static var signInTitle: LocalizedStringResource { .init("signin.title", bundle: bundle) }
    static var signInSubtitle: LocalizedStringResource { .init("signin.subtitle", bundle: bundle) }
    static var signInButton: LocalizedStringResource { .init("signin.button", bundle: bundle) }
    static var signInProgress: LocalizedStringResource { .init("signin.in_progress", bundle: bundle) }
    static var signInRetry: LocalizedStringResource { .init("signin.retry", bundle: bundle) }
    static var signInCancelled: LocalizedStringResource { .init("signin.cancelled", bundle: bundle) }
    static var signInFailed: LocalizedStringResource { .init("signin.failed", bundle: bundle) }
    static var signInNotAllowed: LocalizedStringResource { .init("signin.not_allowed", bundle: bundle) }
    static var signInMisconfigured: LocalizedStringResource { .init("signin.misconfigured", bundle: bundle) }
    static var signInUnavailable: LocalizedStringResource { .init("signin.unavailable", bundle: bundle) }
    static var signInOffline: LocalizedStringResource { .init("signin.offline", bundle: bundle) }

    static var tabAnnouncements: LocalizedStringResource { .init("tab.announcements", bundle: bundle) }
    static var tabVacation: LocalizedStringResource { .init("tab.vacation", bundle: bundle) }
    static var tabWeek: LocalizedStringResource { .init("tab.week", bundle: bundle) }
    static var tabMore: LocalizedStringResource { .init("tab.more", bundle: bundle) }
    static var tabApprovals: LocalizedStringResource { .init("tab.approvals", bundle: bundle) }

    static var homeLoading: LocalizedStringResource { .init("home.loading", bundle: bundle) }
    static var homeRefresh: LocalizedStringResource { .init("home.refresh", bundle: bundle) }
    static var homeOffline: LocalizedStringResource { .init("home.offline", bundle: bundle) }
    static func role(_ role: Role) -> LocalizedStringResource {
        switch role {
        case .communicator: .init("role.communicator", bundle: bundle)
        case .manager: .init("role.manager", bundle: bundle)
        case .employee: .init("role.employee", bundle: bundle)
        }
    }

    static var placeholderTitle: LocalizedStringResource { .init("placeholder.title", bundle: bundle) }
    static var placeholderMessage: LocalizedStringResource { .init("placeholder.message", bundle: bundle) }

    static var moreAccount: LocalizedStringResource { .init("more.account", bundle: bundle) }
    static var signOut: LocalizedStringResource { .init("more.signout", bundle: bundle) }
    static var signOutTitle: LocalizedStringResource { .init("more.signout.title", bundle: bundle) }
    static var signOutMessage: LocalizedStringResource { .init("more.signout.message", bundle: bundle) }
    static var cancel: LocalizedStringResource { .init("common.cancel", bundle: bundle) }

    static var reauthTitle: LocalizedStringResource { .init("reauth.title", bundle: bundle) }
    static var reauthMessage: LocalizedStringResource { .init("reauth.message", bundle: bundle) }
}
