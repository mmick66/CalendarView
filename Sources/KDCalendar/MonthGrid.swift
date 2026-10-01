import Foundation

/// The months a calendar shows, as a 7 × 6 grid per month. Pure date arithmetic, built once
/// per data source range and calendar.
struct MonthGrid {

    /// Cells per month: seven columns, six rows.
    static let cellsPerMonth = 42

    struct Month {
        /// The first day of the month at the start of the day.
        let firstDate: Date
        /// The column of the first day, 0 to 6, which is also its item in the section. The cells
        /// before it hold the end of the previous month.
        let firstColumn: Int
        /// The number of days in the month.
        let dayCount: Int
    }

    let calendar: Calendar
    /// The first selectable day, at the start of the day.
    let startDay: Date
    /// The last selectable day, at the start of the day.
    let endDay: Date
    let months: [Month]

    /// Returns `nil` when the range is empty, when `end` precedes `start`, or when the
    /// calendar cannot resolve the months.
    init?(start: Date, end: Date, calendar: Calendar, firstWeekday: Int) {
        let startDay = calendar.startOfDay(for: start)
        let endDay = calendar.startOfDay(for: end)
        guard startDay <= endDay,
            let firstMonth = calendar.dateInterval(of: .month, for: startDay)?.start,
            let lastMonth = calendar.dateInterval(of: .month, for: endDay)?.start,
            let monthCount = calendar.dateComponents([.month], from: firstMonth, to: lastMonth).month
        else { return nil }

        var months: [Month] = []
        for section in 0...monthCount {
            guard let firstDate = calendar.date(byAdding: .month, value: section, to: firstMonth),
                let days = calendar.range(of: .day, in: .month, for: firstDate)
            else { return nil }
            let weekday = calendar.component(.weekday, from: firstDate)
            let firstColumn = (weekday - firstWeekday + 7) % 7
            months.append(Month(firstDate: firstDate, firstColumn: firstColumn, dayCount: days.count))
        }

        self.calendar = calendar
        self.startDay = startDay
        self.endDay = endDay
        self.months = months
    }

    var numberOfSections: Int { months.count }

    /// The first day of the month in `section`, at the start of the day.
    func firstDayOfMonth(inSection section: Int) -> Date? {
        months.indices.contains(section) ? months[section].firstDate : nil
    }

    /// The cell showing the day that contains `date`, or `nil` outside the displayed months.
    func indexPath(for date: Date) -> IndexPath? {
        let day = calendar.startOfDay(for: date)
        guard let monthStart = calendar.dateInterval(of: .month, for: day)?.start,
            let section = calendar.dateComponents([.month], from: months[0].firstDate, to: monthStart).month,
            months.indices.contains(section)
        else { return nil }
        let dayOfMonth = calendar.component(.day, from: day)
        return IndexPath(item: months[section].firstColumn + dayOfMonth - 1, section: section)
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

    /// What the cell at `indexPath` shows. The cells around a month hold the neighbouring
    /// months' days, before the first month and after the last month too.
    func content(at indexPath: IndexPath) -> Content {
        guard months.indices.contains(indexPath.section) else { return .empty }
        let month = months[indexPath.section]
        let offset = indexPath.item - month.firstColumn
        guard let date = calendar.date(byAdding: .day, value: offset, to: month.firstDate) else { return .empty }
        if offset < 0 {
            return .leading(dayOfMonth: calendar.component(.day, from: date))
        }
        if offset >= month.dayCount {
            return .trailing(dayOfMonth: offset - month.dayCount + 1)
        }
        return .day(date, dayOfMonth: offset + 1)
    }

    /// The day a cell shows, or `nil` for the empty cells before and after the month.
    func date(at indexPath: IndexPath) -> Date? {
        guard case .day(let date, _) = content(at: indexPath) else { return nil }
        return date
    }

    /// Whether the cell shows no day between `startDay` and `endDay`. Cells without a day of
    /// their month are out of range.
    func isOutOfRange(_ indexPath: IndexPath) -> Bool {
        guard let date = date(at: indexPath) else { return true }
        return !(startDay...endDay).contains(date)
    }
}
