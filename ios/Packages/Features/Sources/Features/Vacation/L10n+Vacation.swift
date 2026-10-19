import Core
import Foundation

/// Typed keys for the vacation strings (FR-VAC-001/002/006).
extension L10n {
    static var vacRequestButton: LocalizedStringResource { .init("vac.request.button", bundle: bundle) }
    static var vacOverviewHint: LocalizedStringResource { .init("vac.overview.hint", bundle: bundle) }
    static var vacOverviewComposition: LocalizedStringResource { .init("vac.overview.composition", bundle: bundle) }
    static var vacApproved: LocalizedStringResource { .init("vac.approved", bundle: bundle) }
    static var vacPending: LocalizedStringResource { .init("vac.pending", bundle: bundle) }
    static var vacNext: LocalizedStringResource { .init("vac.next", bundle: bundle) }
    static var vacEmptyTitle: LocalizedStringResource { .init("vac.overview.empty.title", bundle: bundle) }
    static var vacEmptyMessage: LocalizedStringResource { .init("vac.overview.empty.message", bundle: bundle) }
    static var vacHolidaysRow: LocalizedStringResource { .init("vac.overview.holidays", bundle: bundle) }
    static var vacOfflineRequest: LocalizedStringResource { .init("vac.offline.request", bundle: bundle) }
    static var vacErrorTitle: LocalizedStringResource { .init("vac.error.title", bundle: bundle) }
    static var vacErrorMessage: LocalizedStringResource { .init("vac.error.message", bundle: bundle) }
    static var vacRetry: LocalizedStringResource { .init("vac.retry", bundle: bundle) }
    static var vacNotProvisionedTitle: LocalizedStringResource { .init("vac.notprovisioned.title", bundle: bundle) }
    static var vacNotProvisionedMessage: LocalizedStringResource { .init("vac.notprovisioned.message", bundle: bundle) }
    static var vacRefresh: LocalizedStringResource { .init("vac.refresh", bundle: bundle) }

    static func vacRemaining(_ year: Int) -> LocalizedStringResource {
        .init("vac.overview.remaining", defaultValue: "Remaining \(String(year))", bundle: bundle)
    }
    static func vacEntitlement(_ year: Int) -> LocalizedStringResource {
        .init("vac.entitlement", defaultValue: "Entitlement \(String(year))", bundle: bundle)
    }
    static func vacCarried(_ year: Int) -> LocalizedStringResource {
        .init("vac.carried", defaultValue: "Carried over from \(String(year))", bundle: bundle)
    }
    static func vacNextApprover(_ name: String) -> LocalizedStringResource {
        .init("vac.next.approver", defaultValue: "with \(name)", bundle: bundle)
    }
    static func vacOfflineAsOf(_ asOf: String) -> LocalizedStringResource {
        .init("vac.offline.asof", defaultValue: "Offline. Last updated \(asOf)", bundle: bundle)
    }
    static func vacStatus(_ status: VacationStatus) -> LocalizedStringResource {
        switch status {
        case .pending: .init("vac.status.pending", bundle: bundle)
        case .approved: .init("vac.status.approved", bundle: bundle)
        case .rejected: .init("vac.status.rejected", bundle: bundle)
        case .cancelled: .init("vac.status.cancelled", bundle: bundle)
        }
    }

    /// The unit word next to a hero number ("13 Tage"). A plural variation must contain the number,
    /// so singular and plural are separate keys.
    static func vacDaysUnit(_ count: Int) -> LocalizedStringResource {
        count == 1 ? .init("vac.days.unit.one", bundle: bundle) : .init("vac.days.unit.other", bundle: bundle)
    }
    static func vacDays(_ count: Int) -> LocalizedStringResource {
        .init("vac.days", defaultValue: "\(count) days", bundle: bundle)
    }
    static func vacWorkdays(_ count: Int) -> LocalizedStringResource {
        .init("vac.workdays", defaultValue: "\(count) working days", bundle: bundle)
    }

    // Holidays (FR-VAC-006)
    static var vacHolidaysNote: LocalizedStringResource { .init("vac.holidays.note", bundle: bundle) }
    static var vacHolidaysEmptyTitle: LocalizedStringResource { .init("vac.holidays.empty.title", bundle: bundle) }
    static var vacHolidaysEmptyMessage: LocalizedStringResource { .init("vac.holidays.empty.message", bundle: bundle) }
    static var vacCantonTitle: LocalizedStringResource { .init("vac.canton.title", bundle: bundle) }
    static var vacCantonMessage: LocalizedStringResource { .init("vac.canton.message", bundle: bundle) }
    static func vacHolidaysTitle(_ year: Int) -> LocalizedStringResource {
        .init("vac.holidays.title", defaultValue: "Holidays \(String(year))", bundle: bundle)
    }
    static func vacHolidaysCanton(_ canton: String) -> LocalizedStringResource {
        .init("vac.holidays.canton", defaultValue: "Canton \(canton)", bundle: bundle)
    }

    // Request (date range)
    static var vacRequestTitle: LocalizedStringResource { .init("vac.request.title", bundle: bundle) }
    static var vacRequestPeriod: LocalizedStringResource { .init("vac.request.period", bundle: bundle) }
    static var vacRequestNone: LocalizedStringResource { .init("vac.request.none", bundle: bundle) }
    static var vacRequestNote: LocalizedStringResource { .init("vac.request.note", bundle: bundle) }
    static var vacRequestEnter: LocalizedStringResource { .init("vac.request.enter", bundle: bundle) }
    static var vacRequestCalendar: LocalizedStringResource { .init("vac.request.calendar", bundle: bundle) }
    static var vacRequestStart: LocalizedStringResource { .init("vac.request.start", bundle: bundle) }
    static var vacRequestEnd: LocalizedStringResource { .init("vac.request.end", bundle: bundle) }
    static var vacRequestContinue: LocalizedStringResource { .init("vac.request.continue", bundle: bundle) }
    static var vacRequestChecking: LocalizedStringResource { .init("vac.request.checking", bundle: bundle) }
    static var vacLegendHoliday: LocalizedStringResource { .init("vac.request.legend.holiday", bundle: bundle) }
    static var vacHolidaysLoading: LocalizedStringResource { .init("vac.request.holidays.loading", bundle: bundle) }
    static var vacHolidaysFailed: LocalizedStringResource { .init("vac.request.holidays.failed", bundle: bundle) }
    static var vacRequestOffline: LocalizedStringResource { .init("vac.request.offline", bundle: bundle) }
    static var vacRequestFailed: LocalizedStringResource { .init("vac.request.failed", bundle: bundle) }
    static var vacNoApprover: LocalizedStringResource { .init("vac.request.noapprover", bundle: bundle) }

    /// One plain sentence per reason code; every number and date comes from the API's response.
    static func vacRule(_ violation: VacationViolation) -> String {
        func day(_ d: CalendarDay) -> String { d.date().formatted(.dateTime.day().month(.abbreviated).year()) }
        switch violation.rule {
        case .invalidRange: return String(localized: .init("vac.rule.invalid_range", bundle: bundle))
        case .pastDate: return String(localized: .init("vac.rule.past_date", bundle: bundle))
        case .zeroDays: return String(localized: .init("vac.rule.zero_days", bundle: bundle))
        case .blackout:
            guard let range = violation.range else {
                return String(localized: .init("vac.rule.blackout.generic", bundle: bundle))
            }
            let from = day(range.start), to = day(range.end)
            return String(localized: .init("vac.rule.blackout", defaultValue: "Blocked \(from) \(to)", bundle: bundle))
        case .overlap:
            guard let first = violation.conflicts.first else {
                return String(localized: .init("vac.rule.overlap.generic", bundle: bundle))
            }
            let span = "\(day(first.start)) – \(day(first.end))"
            return String(localized: .init("vac.rule.overlap", defaultValue: "Overlaps \(span)", bundle: bundle))
        case .insufficientBalance:
            guard let requested = violation.requested, let remaining = violation.remaining else {
                return String(localized: .init("vac.rule.insufficient.generic", bundle: bundle))
            }
            return String(localized: .init(
                "vac.rule.insufficient", defaultValue: "Not enough: \(requested) of \(remaining)", bundle: bundle))
        case nil: return String(localized: .init("vac.rule.generic", bundle: bundle))
        }
    }

    // Review
    static var vacReviewTitle: LocalizedStringResource { .init("vac.review.title", bundle: bundle) }
    static var vacReviewSectionRequest: LocalizedStringResource { .init("vac.review.section.request", bundle: bundle) }
    static var vacReviewCounted: LocalizedStringResource { .init("vac.review.counted", bundle: bundle) }
    static var vacReviewExcluded: LocalizedStringResource { .init("vac.review.excluded", bundle: bundle) }
    static var vacReviewExcludedNone: LocalizedStringResource { .init("vac.review.excluded.none", bundle: bundle) }
    static var vacReviewWeekend: LocalizedStringResource { .init("vac.review.excluded.weekend", bundle: bundle) }
    static var vacReviewHoliday: LocalizedStringResource { .init("vac.review.excluded.holiday", bundle: bundle) }
    static var vacReviewAfter: LocalizedStringResource { .init("vac.review.after", bundle: bundle) }
    static var vacReviewApprover: LocalizedStringResource { .init("vac.review.approver", bundle: bundle) }
    static var vacReviewAvailable: LocalizedStringResource { .init("vac.review.available", bundle: bundle) }
    static var vacReviewMissing: LocalizedStringResource { .init("vac.review.missing", bundle: bundle) }
    static var vacReviewChange: LocalizedStringResource { .init("vac.review.change", bundle: bundle) }
    static var vacReviewOffline: LocalizedStringResource { .init("vac.review.offline", bundle: bundle) }
    static var vacReviewFailed: LocalizedStringResource { .init("vac.review.failed", bundle: bundle) }
    static var vacReviewExpired: LocalizedStringResource { .init("vac.review.expired", bundle: bundle) }
    static func vacReviewSectionBalance(_ year: Int) -> LocalizedStringResource {
        .init("vac.review.section.balance", defaultValue: "Your balance \(String(year))", bundle: bundle)
    }
    static func vacReviewBefore(_ days: Int) -> LocalizedStringResource {
        .init("vac.review.before", defaultValue: "before: \(days)", bundle: bundle)
    }
    static func vacReviewHint(_ approver: String) -> LocalizedStringResource {
        .init("vac.review.hint", defaultValue: "Sent to \(approver)", bundle: bundle)
    }

    // Success
    static var vacSuccessTitle: LocalizedStringResource { .init("vac.success.title", bundle: bundle) }
    static var vacDone: LocalizedStringResource { .init("vac.done", bundle: bundle) }
    static func vacSuccessDetail(_ approver: String) -> LocalizedStringResource {
        .init("vac.success.detail", defaultValue: "Pending with \(approver)", bundle: bundle)
    }
}
