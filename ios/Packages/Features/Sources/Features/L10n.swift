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

    // Announcements (FR-ANN-001)
    static var annEntry: LocalizedStringResource { .init("ann.entry", bundle: bundle) }
    static var annComposeTitle: LocalizedStringResource { .init("ann.compose.title", bundle: bundle) }
    static var annComposeFieldTitle: LocalizedStringResource { .init("ann.compose.field.title", bundle: bundle) }
    static var annComposeFieldBody: LocalizedStringResource { .init("ann.compose.field.body", bundle: bundle) }
    static var annComposeLanguage: LocalizedStringResource { .init("ann.compose.language", bundle: bundle) }
    static var annComposeAudience: LocalizedStringResource { .init("ann.compose.audience", bundle: bundle) }
    static var annAudienceAll: LocalizedStringResource { .init("ann.audience.all", bundle: bundle) }
    static var annComposeReview: LocalizedStringResource { .init("ann.compose.review", bundle: bundle) }
    static var annComposeChecking: LocalizedStringResource { .init("ann.compose.checking", bundle: bundle) }
    static var annErrorTitle: LocalizedStringResource { .init("ann.error.title", bundle: bundle) }
    static var annErrorBody: LocalizedStringResource { .init("ann.error.body", bundle: bundle) }
    static var annErrorOther: LocalizedStringResource { .init("ann.error.other", bundle: bundle) }
    static var annReviewTitle: LocalizedStringResource { .init("ann.review.title", bundle: bundle) }
    static var annReviewPublish: LocalizedStringResource { .init("ann.review.publish", bundle: bundle) }
    static var annReviewEdit: LocalizedStringResource { .init("ann.review.edit", bundle: bundle) }
    static var annReviewHint: LocalizedStringResource { .init("ann.review.hint", bundle: bundle) }
    static var annSuccessDone: LocalizedStringResource { .init("ann.success.done", bundle: bundle) }
    static var annOfflineMessage: LocalizedStringResource { .init("ann.offline.message", bundle: bundle) }
    static var annRetry: LocalizedStringResource { .init("ann.retry", bundle: bundle) }
    static var annForbiddenTitle: LocalizedStringResource { .init("ann.forbidden.title", bundle: bundle) }
    static var annForbiddenMessage: LocalizedStringResource { .init("ann.forbidden.message", bundle: bundle) }
    static var annFailedTitle: LocalizedStringResource { .init("ann.failed.title", bundle: bundle) }
    static var annFailedMessage: LocalizedStringResource { .init("ann.failed.message", bundle: bundle) }
    static var annExpired: LocalizedStringResource { .init("ann.expired", bundle: bundle) }

    static var annDetails: LocalizedStringResource { .init("ann.details", bundle: bundle) }

    static func annCounter(_ used: Int, _ limit: Int) -> LocalizedStringResource {
        .init("ann.compose.counter", defaultValue: "\(used) of \(limit)", bundle: bundle)
    }
    static func annRecipients(_ count: Int) -> LocalizedStringResource {
        .init("ann.review.recipients", defaultValue: "\(count) recipients", bundle: bundle)
    }
    static func annSuccessTitle(_ count: Int) -> LocalizedStringResource {
        .init("ann.success.title", defaultValue: "Published to \(count) people", bundle: bundle)
    }
    static func annLanguageA11y(_ language: ContentLanguage) -> LocalizedStringResource {
        .init("ann.language.a11y", defaultValue: "Language of the content, \(String(localized: annLanguage(language)))", bundle: bundle)
    }
    static func annLanguage(_ language: ContentLanguage) -> LocalizedStringResource {
        switch language {
        case .de: .init("ann.lang.de", bundle: bundle)
        case .fr: .init("ann.lang.fr", bundle: bundle)
        case .it: .init("ann.lang.it", bundle: bundle)
        case .en: .init("ann.lang.en", bundle: bundle)
        }
    }
}
