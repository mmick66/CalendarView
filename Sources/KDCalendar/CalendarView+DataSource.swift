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
        self.startIndexPath = IndexPath(item: months[0].firstDay + calendar.component(.day, from: startDay) - 1, section: 0)
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

    /// The day a cell shows, or `nil` for the empty cells before and after the month.
    func date(at indexPath: IndexPath) -> Date? {
        guard months.indices.contains(indexPath.section) else { return nil }
        let month = months[indexPath.section]
        let offset = indexPath.item - month.firstDay
        guard offset >= 0, offset < month.daysTotal else { return nil }
        return calendar.date(byAdding: .day, value: offset, to: month.firstDate)
    }

    func isOutOfRange(_ indexPath: IndexPath) -> Bool {
        indexPath < startIndexPath || indexPath > endIndexPath
    }
}

extension CalendarView {

    /// The month grid for the data source's current range, rebuilt when the range moves to
    /// other days. Zero months when there is no data source or the range is invalid.
    var currentMonths: MonthGrid? {
        guard let dataSource = self.dataSource else {
            months = nil
            return nil
        }
        let start = dataSource.startDate()
        let end = dataSource.endDate()
        if let months = months,
            calendar.isDate(months.startDay, inSameDayAs: start),
            calendar.isDate(months.endDay, inSameDayAs: end),
            months.calendar == calendar
        {
            return months
        }
        months = MonthGrid(start: start, end: end, calendar: calendar, firstWeekday: style.effectiveFirstWeekday)
        if months == nil {
            CalendarView.logger.error(
                "The data source's start date (\(start)) is after its end date (\(end)); showing no months.")
        }
        rebuildEventIndex()
        return months
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

    var todayIndexPath: IndexPath? {
        currentMonths?.indexPath(for: Date())
    }

    func rebuildEventIndex() {
        eventsByIndexPath.removeAll()
        guard let months = months else { return }
        for event in events {
            var day = calendar.startOfDay(for: event.startDate)
            let last = max(event.startDate, event.endDate)
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
        return currentMonths?.numberOfSections ?? 0
    }

    public func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return MonthGrid.cellsPerMonth  // rows:7 x cols:6
    }

    public func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let dayCell = collectionView.dequeueReusableCell(withReuseIdentifier: cellReuseIdentifier, for: indexPath) as! CalendarDayCell

        dayCell.style = style
        dayCell.transform = _isRtl
            ? CGAffineTransform(scaleX: -1.0, y: 1.0)
            : CGAffineTransform.identity

        guard let months = currentMonths, months.months.indices.contains(indexPath.section) else { return dayCell }
        let month = months.months[indexPath.section]

        let firstDayIndex = month.firstDay
        let lastDayIndex = firstDayIndex + month.daysTotal
        let isInRange = (firstDayIndex..<lastDayIndex).contains(indexPath.item)

        if isInRange {
            dayCell.day = indexPath.item - firstDayIndex + 1
            dayCell.isOutOfRange = months.isOutOfRange(indexPath)
            dayCell.isToday = indexPath == todayIndexPath
            if marksWeekends, let date = months.date(at: indexPath) {
                dayCell.isWeekend = calendar.isDateInWeekend(date)
            }
            dayCell.eventsCount = eventsByIndexPath[indexPath]?.count ?? 0
            dayCell.date = months.date(at: indexPath)
            if let date = dayCell.date {
                dayCell.accessibilityLabel = accessibilityLabel(
                    for: date, isToday: dayCell.isToday, eventsCount: dayCell.eventsCount)
            }
        } else if style.showAdjacentDays {
            if indexPath.item < firstDayIndex {
                if indexPath.section > 0 {
                    dayCell.day = months.months[indexPath.section - 1].daysTotal - firstDayIndex + indexPath.item + 1
                } else {
                    dayCell.isHidden = true
                }
            } else {
                dayCell.day = indexPath.item - lastDayIndex + 1
            }
            dayCell.isAdjacent = true
            dayCell.eventsCount = 0
        } else {
            dayCell.isHidden = true
        }

        return dayCell
    }
}
