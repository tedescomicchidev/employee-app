import SwiftUI

/// Month grid with 44 pt day cells, an optional selected range and holiday dots.
public struct DSCalendarMonth: View {
    private let month: Date
    private let selection: ClosedRange<Date>?
    private let holidays: [Date]
    private let dimsWeekends: Bool
    private let calendar: Calendar
    private let onSelect: (Date) -> Void

    public init(
        month: Date,
        selection: ClosedRange<Date>? = nil,
        holidays: [Date] = [],
        dimsWeekends: Bool = false,
        calendar: Calendar = .current,
        onSelect: @escaping (Date) -> Void = { _ in }
    ) {
        self.month = month
        self.selection = selection
        self.holidays = holidays
        self.dimsWeekends = dimsWeekends
        self.calendar = calendar
        self.onSelect = onSelect
    }

    /// Formats in the calendar's own time zone, so a fixed business calendar never shifts a day.
    private var format: Date.FormatStyle {
        Date.FormatStyle(calendar: calendar, timeZone: calendar.timeZone)
    }

    private var columns: [GridItem] { Array(repeating: GridItem(.flexible(), spacing: 0), count: 7) }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    /// `nil` entries pad the first week.
    private var days: [Date?] {
        guard let interval = calendar.dateInterval(of: .month, for: month),
              let count = calendar.range(of: .day, in: .month, for: month)?.count
        else { return [] }
        let weekday = calendar.component(.weekday, from: interval.start)
        let lead = (weekday - calendar.firstWeekday + 7) % 7
        let dates: [Date?] = (0..<count).compactMap {
            calendar.date(byAdding: .day, value: $0, to: interval.start)
        }
        return Array(repeating: nil, count: lead) + dates
    }

    public var body: some View {
        VStack(spacing: DSSpacing.xs) {
            Text(month, format: format.month(.wide).year())
                .font(DSFont.cardTitle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
            LazyVGrid(columns: columns, spacing: 0) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol).font(DSFont.caption).foregroundStyle(DSColor.ink2)
                        .accessibilityHidden(true)
                }
                ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                    if let day { cell(for: day) } else { Color.clear.frame(height: DSSize.touch) }
                }
            }
        }
    }

    private func isSelected(_ day: Date) -> Bool {
        guard let selection else { return false }
        return calendar.startOfDay(for: day) >= calendar.startOfDay(for: selection.lowerBound)
            && calendar.startOfDay(for: day) <= calendar.startOfDay(for: selection.upperBound)
    }

    private func isHoliday(_ day: Date) -> Bool {
        holidays.contains { calendar.isDate($0, inSameDayAs: day) }
    }

    private func cell(for day: Date) -> some View {
        let selected = isSelected(day)
        return Button { onSelect(day) } label: {
            VStack(spacing: 2) {
                Text(day, format: format.day()).font(DSFont.body).monospacedDigit()
                Circle().fill(isHoliday(day) ? DSColor.orange : .clear).frame(width: 5, height: 5)
            }
            .foregroundStyle(selected ? Color.white : (dimsWeekends && calendar.isDateInWeekend(day) ? DSColor.ink2 : DSColor.ink))
            .frame(maxWidth: .infinity, minHeight: DSSize.touch)
            .background(selected ? DSColor.tint : .clear, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(day, format: format.weekday(.wide).day().month(.wide)))
        .accessibilityValue(isHoliday(day) ? Text(DSStrings.holiday) : Text(verbatim: ""))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

public struct DSEventRow: View {
    private let time: Text
    private let title: Text
    private let subtitle: Text?
    private let tag: Text?

    public init(time: Text, title: Text, subtitle: Text? = nil, tag: Text? = nil) {
        self.time = time
        self.title = title
        self.subtitle = subtitle
        self.tag = tag
    }

    public var body: some View {
        HStack(alignment: .top, spacing: DSSpacing.s) {
            time.font(DSFont.secondary).foregroundStyle(DSColor.ink2).monospacedDigit()
                .frame(minWidth: 52, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                title.font(DSFont.body)
                if let subtitle { subtitle.font(DSFont.secondary).foregroundStyle(DSColor.ink2) }
            }
            Spacer(minLength: 0)
            if let tag { DSStatusChip(.info, label: tag) }
        }
        .padding(.horizontal, DSSpacing.m)
        .padding(.vertical, DSSpacing.xs)
        .frame(minHeight: DSSize.rowDense)
        .accessibilityElement(children: .combine)
    }
}

#Preview("Calendar and events") {
    let start = Date(timeIntervalSince1970: 1_798_070_400) // 2026-12-24
    return ScrollView {
        VStack(spacing: DSSpacing.m) {
            DSCalendarMonth(month: start, selection: start...start.addingTimeInterval(4 * 86_400),
                            holidays: [start.addingTimeInterval(86_400)])
                .padding(DSSpacing.m)
                .background(DSColor.card, in: RoundedRectangle(cornerRadius: DSRadius.card))
            DSGroupedSection {
                DSEventRow(time: Text("09:00"), title: Text("Team-Standup"), subtitle: Text("Raum 4"), tag: Text("Teams"))
            }
        }
        .padding(DSSpacing.gutter)
    }
    .background(DSColor.bg)
}
