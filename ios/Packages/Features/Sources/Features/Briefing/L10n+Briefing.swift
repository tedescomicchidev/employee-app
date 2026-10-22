import Core
import Foundation

/// Typed keys for the weekly briefing strings (FR-BRF-001..005, DE/FR/IT/EN).
extension L10n {
    static var brfOptinTitle: LocalizedStringResource { .init("brf.optin.title", bundle: bundle) }
    static var brfOptinMessage: LocalizedStringResource { .init("brf.optin.message", bundle: bundle) }
    static var brfOptinAccessHeader: LocalizedStringResource { .init("brf.optin.access.header", bundle: bundle) }
    static var brfOptinAccessCalendar: LocalizedStringResource { .init("brf.optin.access.calendar", bundle: bundle) }
    static var brfOptinAccessVia: LocalizedStringResource { .init("brf.optin.access.via", bundle: bundle) }
    static var brfOptinAccessStored: LocalizedStringResource { .init("brf.optin.access.stored", bundle: bundle) }
    static var brfOptinFootnote: LocalizedStringResource { .init("brf.optin.footnote", bundle: bundle) }
    static var brfOptinTurnon: LocalizedStringResource { .init("brf.optin.turnon", bundle: bundle) }
    static var brfOptinNotnow: LocalizedStringResource { .init("brf.optin.notnow", bundle: bundle) }
    static var brfOptinWorking: LocalizedStringResource { .init("brf.optin.working", bundle: bundle) }
    static var brfOptinFailed: LocalizedStringResource { .init("brf.optin.failed", bundle: bundle) }
    static var brfOptinOffline: LocalizedStringResource { .init("brf.optin.offline", bundle: bundle) }
    static var brfReminderTitle: LocalizedStringResource { .init("brf.reminder.title", bundle: bundle) }
    static var brfReminderMessage: LocalizedStringResource { .init("brf.reminder.message", bundle: bundle) }
    static var brfReminderAllow: LocalizedStringResource { .init("brf.reminder.allow", bundle: bundle) }
    static var brfReminderSkip: LocalizedStringResource { .init("brf.reminder.skip", bundle: bundle) }
    static var brfNotificationTitle: LocalizedStringResource { .init("brf.notification.title", bundle: bundle) }
    static var brfReadingTitle: LocalizedStringResource { .init("brf.reading.title", bundle: bundle) }
    static var brfReadingMessage: LocalizedStringResource { .init("brf.reading.message", bundle: bundle) }
    static var brfReadingSlow: LocalizedStringResource { .init("brf.reading.slow", bundle: bundle) }
    static var brfReadingStop: LocalizedStringResource { .init("brf.reading.stop", bundle: bundle) }
    static var brfWeekEmptyTitle: LocalizedStringResource { .init("brf.week.empty.title", bundle: bundle) }
    static var brfWeekEmptyMessage: LocalizedStringResource { .init("brf.week.empty.message", bundle: bundle) }
    static var brfWeekPartialTitle: LocalizedStringResource { .init("brf.week.partial.title", bundle: bundle) }
    static var brfWeekRefresh: LocalizedStringResource { .init("brf.week.refresh", bundle: bundle) }
    static var brfWeekReminderOn: LocalizedStringResource { .init("brf.week.reminder.on", bundle: bundle) }
    static var brfDayNoevents: LocalizedStringResource { .init("brf.day.noevents", bundle: bundle) }
    static var brfDayMissing: LocalizedStringResource { .init("brf.day.missing", bundle: bundle) }
    static var brfDayTitle: LocalizedStringResource { .init("brf.day.title", bundle: bundle) }
    static var brfAllday: LocalizedStringResource { .init("brf.allday", bundle: bundle) }
    static var brfOnline: LocalizedStringResource { .init("brf.online", bundle: bundle) }
    static var brfConflict: LocalizedStringResource { .init("brf.conflict", bundle: bundle) }
    static var brfConflictChip: LocalizedStringResource { .init("brf.conflict.chip", bundle: bundle) }
    static var brfDayConflictsHeader: LocalizedStringResource { .init("brf.day.conflicts.header", bundle: bundle) }
    static var brfDayFreeHeader: LocalizedStringResource { .init("brf.day.free.header", bundle: bundle) }
    static var brfProblemUnavailableTitle: LocalizedStringResource { .init("brf.problem.unavailable.title", bundle: bundle) }
    static var brfProblemUnavailableMessage: LocalizedStringResource { .init("brf.problem.unavailable.message", bundle: bundle) }
    static var brfProblemNolicenceTitle: LocalizedStringResource { .init("brf.problem.nolicence.title", bundle: bundle) }
    static var brfProblemNolicenceMessage: LocalizedStringResource { .init("brf.problem.nolicence.message", bundle: bundle) }
    static var brfProblemConsentTitle: LocalizedStringResource { .init("brf.problem.consent.title", bundle: bundle) }
    static var brfProblemConsentMessage: LocalizedStringResource { .init("brf.problem.consent.message", bundle: bundle) }
    static var brfProblemOfflineTitle: LocalizedStringResource { .init("brf.problem.offline.title", bundle: bundle) }
    static var brfProblemOfflineMessage: LocalizedStringResource { .init("brf.problem.offline.message", bundle: bundle) }
    static var brfProblemTimeoutTitle: LocalizedStringResource { .init("brf.problem.timeout.title", bundle: bundle) }
    static var brfProblemTimeoutMessage: LocalizedStringResource { .init("brf.problem.timeout.message", bundle: bundle) }
    static var brfProblemSignedoutTitle: LocalizedStringResource { .init("brf.problem.signedout.title", bundle: bundle) }
    static var brfProblemSignedoutMessage: LocalizedStringResource { .init("brf.problem.signedout.message", bundle: bundle) }
    static var brfProblemStoppedTitle: LocalizedStringResource { .init("brf.problem.stopped.title", bundle: bundle) }
    static var brfProblemStoppedMessage: LocalizedStringResource { .init("brf.problem.stopped.message", bundle: bundle) }
    static var brfProblemNotprovisionedTitle: LocalizedStringResource { .init("brf.problem.notprovisioned.title", bundle: bundle) }
    static var brfProblemNotprovisionedMessage: LocalizedStringResource { .init("brf.problem.notprovisioned.message", bundle: bundle) }
    static var brfProblemFailedTitle: LocalizedStringResource { .init("brf.problem.failed.title", bundle: bundle) }
    static var brfProblemFailedMessage: LocalizedStringResource { .init("brf.problem.failed.message", bundle: bundle) }
    static var brfRetry: LocalizedStringResource { .init("brf.retry", bundle: bundle) }
    static var brfSettingsHeader: LocalizedStringResource { .init("brf.settings.header", bundle: bundle) }
    static var brfSettingsToggle: LocalizedStringResource { .init("brf.settings.toggle", bundle: bundle) }
    static var brfSettingsToggleHint: LocalizedStringResource { .init("brf.settings.toggle.hint", bundle: bundle) }
    static var brfSettingsReminder: LocalizedStringResource { .init("brf.settings.reminder", bundle: bundle) }
    static var brfSettingsReminderOn: LocalizedStringResource { .init("brf.settings.reminder.on", bundle: bundle) }
    static var brfSettingsReminderOff: LocalizedStringResource { .init("brf.settings.reminder.off", bundle: bundle) }
    static var brfSettingsReminderDenied: LocalizedStringResource { .init("brf.settings.reminder.denied", bundle: bundle) }
    static var brfSettingsOpensettings: LocalizedStringResource { .init("brf.settings.opensettings", bundle: bundle) }
    static var brfSettingsOffline: LocalizedStringResource { .init("brf.settings.offline", bundle: bundle) }
    static var brfSettingsFailed: LocalizedStringResource { .init("brf.settings.failed", bundle: bundle) }
    static var brfAlertOnTitle: LocalizedStringResource { .init("brf.alert.on.title", bundle: bundle) }
    static var brfAlertOnMessage: LocalizedStringResource { .init("brf.alert.on.message", bundle: bundle) }
    static var brfAlertOffTitle: LocalizedStringResource { .init("brf.alert.off.title", bundle: bundle) }
    static var brfAlertOffMessage: LocalizedStringResource { .init("brf.alert.off.message", bundle: bundle) }
    static var brfAlertOnConfirm: LocalizedStringResource { .init("brf.alert.on.confirm", bundle: bundle) }
    static var brfAlertOffConfirm: LocalizedStringResource { .init("brf.alert.off.confirm", bundle: bundle) }
    static var brfAgentEmpty: LocalizedStringResource { .init("brf.agent.empty", bundle: bundle) }
    static var brfAgentSuggestWeek: LocalizedStringResource { .init("brf.agent.suggest.week", bundle: bundle) }
    static var brfAgentSuggestConflicts: LocalizedStringResource { .init("brf.agent.suggest.conflicts", bundle: bundle) }
    static var brfAgentSuggestTurnon: LocalizedStringResource { .init("brf.agent.suggest.turnon", bundle: bundle) }
    static var brfAgentOpenweek: LocalizedStringResource { .init("brf.agent.openweek", bundle: bundle) }
    static var brfCardFieldAccess: LocalizedStringResource { .init("brf.card.field.access", bundle: bundle) }
    static var brfCardFieldVia: LocalizedStringResource { .init("brf.card.field.via", bundle: bundle) }
    static var brfCardFieldStored: LocalizedStringResource { .init("brf.card.field.stored", bundle: bundle) }
    static var brfCardOnTitle: LocalizedStringResource { .init("brf.card.on.title", bundle: bundle) }
    static var brfCardOffTitle: LocalizedStringResource { .init("brf.card.off.title", bundle: bundle) }
    static var brfCardOnConfirm: LocalizedStringResource { .init("brf.card.on.confirm", bundle: bundle) }
    static var brfCardOffConfirm: LocalizedStringResource { .init("brf.card.off.confirm", bundle: bundle) }
    static var brfCardFootnote: LocalizedStringResource { .init("brf.card.footnote", bundle: bundle) }
    static var brfCardDoneOn: LocalizedStringResource { .init("brf.card.done.on", bundle: bundle) }
    static var brfCardDoneOff: LocalizedStringResource { .init("brf.card.done.off", bundle: bundle) }
    static var brfCardValueCalendar: LocalizedStringResource { .init("brf.card.value.calendar", bundle: bundle) }
    static var brfCardValueWorkiq: LocalizedStringResource { .init("brf.card.value.workiq", bundle: bundle) }
    static var brfCardValueNothing: LocalizedStringResource { .init("brf.card.value.nothing", bundle: bundle) }

    static func brfSummaryEvents(_ count: Int) -> LocalizedStringResource {
        .init("brf.summary.events", defaultValue: "\(count) events", bundle: bundle)
    }
    static func brfSummaryConflicts(_ count: Int) -> LocalizedStringResource {
        .init("brf.summary.conflicts", defaultValue: "\(count) overlaps", bundle: bundle)
    }
    static func brfSummaryFree(_ count: Int) -> LocalizedStringResource {
        .init("brf.summary.free", defaultValue: "\(count) free blocks", bundle: bundle)
    }
    static func brfAttendees(_ count: Int) -> LocalizedStringResource {
        .init("brf.attendees", defaultValue: "\(count) attendees", bundle: bundle)
    }
    static func brfAgentOmitted(_ count: Int) -> LocalizedStringResource {
        .init("brf.agent.omitted", defaultValue: "\(count) more events in the full week", bundle: bundle)
    }
    static func brfWeekPartialMessage(_ days: String) -> LocalizedStringResource {
        .init("brf.week.partial.message", defaultValue: "No answer for \(days).", bundle: bundle)
    }
    static func brfFreeBlock(_ range: String) -> LocalizedStringResource {
        .init("brf.free.block", defaultValue: "Free \(range)", bundle: bundle)
    }
    static func brfWeekHeader(_ range: String) -> LocalizedStringResource {
        .init("brf.week.header", defaultValue: "Week \(range)", bundle: bundle)
    }
}
