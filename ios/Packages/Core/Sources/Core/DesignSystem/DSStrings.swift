import Foundation

/// Strings owned by the DesignSystem itself (accessibility and fixed labels).
/// Feature copy is passed in by callers as `LocalizedStringResource`.
enum DSStrings {
    private static var bundle: LocalizedStringResource.BundleDescription {
        .atURL(Bundle.module.bundleURL)
    }

    static var loading: LocalizedStringResource { .init("ds.loading", bundle: bundle) }
    static var details: LocalizedStringResource { .init("ds.details", bundle: bundle) }
    static var correlationId: LocalizedStringResource { .init("ds.correlation_id", bundle: bundle) }
    static var holiday: LocalizedStringResource { .init("ds.holiday", bundle: bundle) }
    static var code: LocalizedStringResource { .init("ds.code", bundle: bundle) }
}
