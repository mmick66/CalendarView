/*
 * CalendarView+DataSource.swift
 * Created by Michael Michailidis on 24/10/2017.
 * http://blog.karmadust.com/
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 *
 */

import UIKit

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
        /// Nothing: a cell before the first displayed month or outside the grid.
        case empty
    }

    /// What the cell at `indexPath` shows. The cells around a month hold the neighbouring
    /// months' days, except before the first month, which has no previous month to borrow from.
    func content(at indexPath: IndexPath) -> Content {
        guard months.indices.contains(indexPath.section) else { return .empty }
        let month = months[indexPath.section]
        let offset = indexPath.item - month.firstDay
        if offset < 0 {
            guard indexPath.section > 0 else { return .empty }
            return .leading(dayOfMonth: months[indexPath.section - 1].daysTotal + offset + 1)
        }
        if offset >= month.daysTotal {
            return .trailing(dayOfMonth: offset - month.daysTotal + 1)
        }
        guard let date = calendar.date(byAdding: .day, value: offset, to: month.firstDate) else { return .empty }
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

extension CalendarView {

    /// Asks the data source for its range and rebuilds the month grid when the range moved to
    /// other days or the calendar changed, and the formatters when the calendar changed. The
    /// current month alone without a data source; zero months when the range is invalid. Called
    /// once per reload, not once per cell.
    @discardableResult
    func refreshMonths() -> MonthGrid? {
        let start = dataSource?.startDate() ?? Date()
        let end = dataSource?.endDate() ?? start
        // The grid keeps a fixed copy: an autoupdating calendar always equals itself, so
        // comparing it would miss the time zone changes the grid has to follow.
        let calendar = self.calendar.fixed
        if formatters.calendar != calendar {
            rebuildFormatters()
        }
        if let months = months,
            calendar.isDate(months.startDay, inSameDayAs: start),
            calendar.isDate(months.endDay, inSameDayAs: end),
            months.calendar == calendar
        {
            todayIndexPath = months.indexPath(for: Date())
            return months
        }
        let previousCalendar = months?.calendar
        months = MonthGrid(start: start, end: end, calendar: calendar, firstWeekday: style.effectiveFirstWeekday)
        if let previousCalendar {
            moveSelection(from: previousCalendar)
        }
        if months == nil {
            CalendarView.logger.error(
                "The data source's start date (\(start)) is after its end date (\(end)); showing no months.")
        }
        todayIndexPath = months?.indexPath(for: Date())
        rebuildEventIndex()
        return months
    }

    /// The month grid, built on first use. Reloads refresh it from the data source.
    var currentMonths: MonthGrid? {
        months ?? refreshMonths()
    }

    func invalidateMonths() {
        months = nil
    }

    var startDay: Date {
        currentMonths?.startDay ?? calendar.startOfDay(for: Date())
    }

    var endDay: Date {
        currentMonths?.endDay ?? calendar.startOfDay(for: Date())
    }

    /// Buckets every event into the days it covers, clamped to the displayed months so an
    /// open-ended event costs one loop over the grid, not over the centuries.
    func rebuildEventIndex() {
        eventsByIndexPath.removeAll()
        guard let months = months, let first = months.months.first, let lastMonth = months.months.last,
            let gridEnd = calendar.date(byAdding: .day, value: lastMonth.daysTotal, to: lastMonth.firstDate)
        else { return }
        let gridStart = first.firstDate
        for event in events {
            let eventEnd = max(event.startDate, event.endDate)
            guard event.startDate < gridEnd, eventEnd >= gridStart else { continue }
            var day = calendar.startOfDay(for: max(event.startDate, gridStart))
            let last = min(eventEnd, gridEnd)
            repeat {
                if let indexPath = months.indexPath(for: day) {
                    eventsByIndexPath[indexPath, default: []].append(event)
                }
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
            } while day < last
        }
    }

    /// The cell showing the day that contains `date`, or `nil` outside the displayed months.
    public func indexPathForDate(_ date: Date) -> IndexPath? {
        currentMonths?.indexPath(for: date)
    }

    /// The day a cell shows, at the start of the day, or `nil` for an empty cell.
    public func dateFromIndexPath(_ indexPath: IndexPath) -> Date? {
        currentMonths?.date(at: indexPath)
    }

    /// The grid offset of the first day and the number of days for the month in `section`.
    public func getCachedSectionInfo(_ section: Int) -> (firstDay: Int, daysTotal: Int)? {
        guard let months = currentMonths, months.months.indices.contains(section) else { return nil }
        let month = months.months[section]
        return (firstDay: month.firstDay, daysTotal: month.daysTotal)
    }

    func isOutOfRange(_ indexPath: IndexPath) -> Bool {
        currentMonths?.isOutOfRange(indexPath) ?? true
    }
}

extension CalendarView: UICollectionViewDataSource {

    public func numberOfSections(in collectionView: UICollectionView) -> Int {
        return refreshMonths()?.numberOfSections ?? 0
    }

    public func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return MonthGrid.cellsPerMonth  // rows:7 x cols:6
    }

    public func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath)
        -> UICollectionViewCell
    {
        let dayCell =
            collectionView.dequeueReusableCell(withReuseIdentifier: cellReuseIdentifier, for: indexPath)
            as! CalendarDayCell

        dayCell.transform =
            _isRtl
            ? CGAffineTransform(scaleX: -1.0, y: 1.0)
            : CGAffineTransform.identity

        var configuration = DayCellConfiguration(style: style)
        switch currentMonths?.content(at: indexPath) {
        case .day(let date, let dayOfMonth):
            let isToday = indexPath == todayIndexPath
            let eventsCount = eventsByIndexPath[indexPath]?.count ?? 0
            configuration.style = delegate?.calendar(self, styleForDate: date) ?? style
            configuration.day = dayOfMonth
            configuration.date = date
            configuration.isOutOfRange = isOutOfRange(indexPath)
            configuration.isToday = isToday
            configuration.isWeekend = marksWeekends && calendar.isDateInWeekend(date)
            configuration.eventsCount = eventsCount
            configuration.accessibilityLabel = accessibilityLabel(for: date, isToday: isToday, eventsCount: eventsCount)
        case .leading(let dayOfMonth) where style.showAdjacentDays,
            .trailing(let dayOfMonth) where style.showAdjacentDays:
            configuration.day = dayOfMonth
            configuration.isAdjacent = true
        case .leading, .trailing, .empty:
            configuration.isHidden = true
        case nil:
            break
        }
        dayCell.configuration = configuration

        return dayCell
    }
}

extension Calendar {

    /// This calendar with the settings it has now. An autoupdating calendar, such as
    /// `Calendar.autoupdatingCurrent`, would follow later changes to the user's settings.
    var fixed: Calendar {
        guard self == .autoupdatingCurrent else { return self }
        var calendar = Calendar(identifier: identifier)
        calendar.locale = locale
        calendar.timeZone = timeZone
        calendar.firstWeekday = firstWeekday
        calendar.minimumDaysInFirstWeek = minimumDaysInFirstWeek
        return calendar
    }
}
