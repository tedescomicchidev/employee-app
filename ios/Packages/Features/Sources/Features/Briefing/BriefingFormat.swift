import Core
import Foundation

/// Times are Europe/Zurich business times: format them in that zone so the device zone never shifts them.
enum BriefingFormat {
    private static var style: Date.FormatStyle {
        Date.FormatStyle(calendar: .zurich, timeZone: Calendar.zurich.timeZone)
    }

    static func time(_ date: Date) -> String { date.formatted(style.hour().minute()) }

    static func timeRange(_ start: Date, _ end: Date) -> String { "\(time(start))–\(time(end))" }

    static func dayHeader(_ day: CalendarDay) -> String {
        day.date().formatted(style.weekday(.wide).day().month(.abbreviated))
    }

    static func weekRange(_ start: CalendarDay, _ end: CalendarDay) -> String {
        "\(VacationFormat.shortMonth(start)) – \(VacationFormat.shortMonth(end))"
    }

    static func hours(minutes: Int) -> String {
        let measure = Measurement(value: Double(minutes), unit: UnitDuration.minutes)
        return measure.formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0))))
    }

    /// One line for VoiceOver and the day row: time, title, and where it is, as `api/` returned it.
    static func eventLine(_ event: BriefingEvent) -> String {
        event.allDay ? String(localized: L10n.brfAllday) : timeRange(event.start, event.end)
    }
}
