import Foundation

/// The months a calendar shows, as a 7 × 6 grid per month. Pure date arithmetic, built once
/// per data source range and calendar.
struct MonthGrid {

    /// Cells per month: seven columns, six rows.
    static let cellsPerMonth = 42

    struct Month {
        /// The first day of the month at the start of the day.
        let firstDate: Date
        /// The grid index of the first day, 0 for the first column.
        let firstDay: Int
        /// The number of days in the month.
        let daysTotal: Int
    }

    let calendar: Calendar
    /// The first selectable day, at the start of the day.
    let startDay: Date
    /// The last selectable day, at the start of the day.
    let endDay: Date
    let months: [Month]
    /// The cell of `startDay`.
    let startIndexPath: IndexPath
    /// The cell of `endDay`.
    let endIndexPath: IndexPath

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
            let firstDay = (weekday - firstWeekday + 7) % 7
            months.append(Month(firstDate: firstDate, firstDay: firstDay, daysTotal: days.count))
        }

        self.calendar = calendar
        self.startDay = startDay
        self.endDay = endDay
        self.months = months
        self.startIndexPath = IndexPath(
            item: months[0].firstDay + calendar.component(.day, from: startDay) - 1, section: 0)
        self.endIndexPath = IndexPath(
            item: months[monthCount].firstDay + calendar.component(.day, from: endDay) - 1, section: monthCount)
    }

    var numberOfSections: Int { months.count }

    func firstDay(ofSection section: Int) -> Date? {
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
        return IndexPath(item: months[section].firstDay + dayOfMonth - 1, section: section)
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
        let offset = indexPath.item - month.firstDay
        guard let date = calendar.date(byAdding: .day, value: offset, to: month.firstDate) else { return .empty }
        if offset < 0 {
            return .leading(dayOfMonth: calendar.component(.day, from: date))
        }
        if offset >= month.daysTotal {
            return .trailing(dayOfMonth: offset - month.daysTotal + 1)
        }
        return .day(date, dayOfMonth: offset + 1)
    }

    /// The day a cell shows, or `nil` for the empty cells before and after the month.
    func date(at indexPath: IndexPath) -> Date? {
        guard case .day(let date, _) = content(at: indexPath) else { return nil }
        return date
    }

    func isOutOfRange(_ indexPath: IndexPath) -> Bool {
        indexPath < startIndexPath || indexPath > endIndexPath
    }
}
