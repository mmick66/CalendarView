import Foundation

/// The months a calendar shows, as a 7 × 6 grid per month.
///
/// Pure date arithmetic, built once per data source range and calendar. Every date it hands out is
/// the start of a day in its calendar. That is not always midnight: where a daylight saving change
/// skips midnight, the day, and with it sometimes the month, starts an hour later.
struct MonthGrid {

    /// Cells per month: seven columns, six rows.
    static let cellsPerMonth = 42

    struct Month {
        /// The first day of the month at the start of the day.
        let firstDate: Date
        /// The column of the first day, 0 to 6, which is also its item in the section.
        ///
        /// The cells before it hold the end of the previous month.
        let firstColumn: Int
        /// The number of days in the month.
        let dayCount: Int
    }

    let calendar: Calendar
    /// The first selectable day, at the start of the day.
    let startDay: Date
    /// The last selectable day, at the start of the day.
    let endDay: Date
    /// The months from the one of `startDay` to the one of `endDay`, at least one.
    let months: [Month]
    /// The end of the last month: the first moment after the grid.
    let lastMonthEnd: Date
    /// The cells of `startDay` and `endDay`.
    private let selectableCells: ClosedRange<IndexPath>

    /// Returns `nil` when the range is empty, when `end` precedes `start`, or when the
    /// calendar cannot resolve the months.
    init?(start: Date, end: Date, calendar: Calendar, firstWeekday: Int) {
        let startDay = calendar.startOfDay(for: start)
        let endDay = calendar.startOfDay(for: end)
        guard startDay <= endDay else { return nil }

        // Each month starts where the one before it ends. Adding months to the first one would
        // carry its time of day along, 01:00 when a daylight saving change skipped its midnight,
        // and counting whole months from there to a month that starts at 00:00 comes up one short.
        var months: [Month] = []
        var monthEnd = startDay
        repeat {
            guard let month = calendar.dateInterval(of: .month, for: monthEnd), month.end > monthEnd,
                let days = calendar.range(of: .day, in: .month, for: month.start)
            else { return nil }
            let weekday = calendar.component(.weekday, from: month.start)
            let firstColumn = (weekday - firstWeekday + 7) % 7
            months.append(Month(firstDate: month.start, firstColumn: firstColumn, dayCount: days.count))
            monthEnd = month.end
        } while monthEnd <= endDay

        let lastSection = months.count - 1
        let firstCell = IndexPath(
            item: months[0].firstColumn + calendar.component(.day, from: startDay) - 1, section: 0)
        let lastCell = IndexPath(
            item: months[lastSection].firstColumn + calendar.component(.day, from: endDay) - 1, section: lastSection)
        guard firstCell <= lastCell else { return nil }

        self.calendar = calendar
        self.startDay = startDay
        self.endDay = endDay
        self.months = months
        self.lastMonthEnd = monthEnd
        self.selectableCells = firstCell...lastCell
    }

    var numberOfSections: Int { months.count }

    /// The first day of the month in `section`, at the start of the day.
    func firstDayOfMonth(inSection section: Int) -> Date? {
        months.indices.contains(section) ? months[section].firstDate : nil
    }

    /// The cell showing the day that contains `date`, or `nil` outside the displayed months.
    func indexPath(for date: Date) -> IndexPath? {
        guard date >= months[0].firstDate, date < lastMonthEnd else { return nil }
        // The month of `date` is the last one that starts at or before it; `earlier` always does.
        var earlier = 0
        var later = months.count
        while later - earlier > 1 {
            let middle = (earlier + later) / 2
            if months[middle].firstDate <= date {
                earlier = middle
            } else {
                later = middle
            }
        }
        let dayOfMonth = calendar.component(.day, from: date)
        return IndexPath(item: months[earlier].firstColumn + dayOfMonth - 1, section: earlier)
    }

    /// What a cell shows.
    enum Content: Equatable {
        /// A day of the month, at the start of the day, and its number in the month.
        case day(Date, dayOfMonth: Int)
        /// A day of the previous month, in the cells before the first day.
        case leading(dayOfMonth: Int)
        /// A day of the next month, in the cells after the last day.
        case trailing(dayOfMonth: Int)
        /// Nothing: a cell outside the grid, or a day the calendar cannot resolve.
        case empty
    }

    /// What the cell at `indexPath` shows.
    ///
    /// The cells around a month hold the neighbouring months' days, before the first month and
    /// after the last month too.
    func content(at indexPath: IndexPath) -> Content {
        guard months.indices.contains(indexPath.section) else { return .empty }
        let month = months[indexPath.section]
        let offset = indexPath.item - month.firstColumn
        if offset >= month.dayCount {
            return .trailing(dayOfMonth: offset - month.dayCount + 1)
        }
        guard let date = calendar.date(byAdding: .day, value: offset, to: month.firstDate) else { return .empty }
        if offset < 0 {
            return .leading(dayOfMonth: calendar.component(.day, from: date))
        }
        // Adding days keeps the time of the first day, which is not the start of every day: a
        // month can start at 01:00, after a skipped midnight, and its other days at 00:00.
        return .day(calendar.startOfDay(for: date), dayOfMonth: offset + 1)
    }

    /// The day a cell shows, or `nil` for the empty cells before and after the month.
    func date(at indexPath: IndexPath) -> Date? {
        guard case .day(let date, _) = content(at: indexPath) else { return nil }
        return date
    }

    /// Whether the cell shows no day between `startDay` and `endDay`.
    ///
    /// Cells without a day of their month are out of range. Asks the calendar nothing.
    func isOutOfRange(_ indexPath: IndexPath) -> Bool {
        guard months.indices.contains(indexPath.section) else { return true }
        let month = months[indexPath.section]
        let days = month.firstColumn..<month.firstColumn + month.dayCount
        return !days.contains(indexPath.item) || !selectableCells.contains(indexPath)
    }

    /// Whether `day`, the start of a day, lies between `startDay` and `endDay`.
    func isInRange(_ day: Date) -> Bool {
        startDay <= day && day <= endDay
    }

    /// The days between `startDay` and `endDay` from the day of `range.lowerBound` to the day of
    /// `range.upperBound`, in order.
    ///
    /// Only the days of the grid's own range are walked, so far-off ends cost nothing.
    func days(in range: ClosedRange<Date>) -> [Date] {
        let last = min(calendar.startOfDay(for: range.upperBound), endDay)
        var day = max(calendar.startOfDay(for: range.lowerBound), startDay)
        var days: [Date] = []
        while day <= last {
            days.append(day)
            // Where a DST change skips midnight, adding a day lands after it, so return to the start.
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = calendar.startOfDay(for: next)
        }
        return days
    }
}
