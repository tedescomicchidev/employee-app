import Core
import Foundation
import SwiftUI

/// Dates are Europe/Zurich business dates; format them in that calendar so no device time zone shifts a day.
enum VacationFormat {
    private static var style: Date.FormatStyle {
        Date.FormatStyle(calendar: .zurich, timeZone: Calendar.zurich.timeZone)
    }

    static func weekdayDay(_ day: CalendarDay) -> String {
        day.date().formatted(style.weekday(.abbreviated).day())
    }

    static func short(_ day: CalendarDay) -> String {
        day.date().formatted(style.weekday(.abbreviated).day().month(.abbreviated))
    }

    static func long(_ day: CalendarDay) -> String {
        day.date().formatted(style.weekday(.abbreviated).day().month(.abbreviated).year())
    }

    static func plain(_ day: CalendarDay) -> String {
        day.date().formatted(style.day().month(.abbreviated).year())
    }

    /// "2. Jun." for "decided on" lines.
    static func shortMonth(_ day: CalendarDay) -> String {
        day.date().formatted(style.day().month(.abbreviated))
    }

    /// "Mo 9. – Do 12. Nov." within a month, with both months otherwise; one day when start == end.
    static func range(_ start: CalendarDay, _ end: CalendarDay, long useLong: Bool = false) -> String {
        if start == end { return useLong ? long(start) : short(start) }
        if useLong { return "\(long(start)) – \(long(end))" }
        if start.year == end.year, start.month == end.month {
            return "\(weekdayDay(start)) – \(short(end))"
        }
        return "\(short(start)) – \(short(end))"
    }

    static func days(_ count: Int) -> String { String(localized: L10n.vacDays(count)) }

    /// "−11" with a true minus sign, as in the mockup's composition list.
    static func minus(_ count: Int) -> String { "\u{2212}\(count)" }

    static func asOf(_ date: Date) -> String { date.formatted(date: .abbreviated, time: .shortened) }
}

extension View {
    @ViewBuilder func vacInlineTitle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
}
