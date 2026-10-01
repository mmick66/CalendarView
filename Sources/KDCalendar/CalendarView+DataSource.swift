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

extension CalendarView: UICollectionViewDataSource {

    /// One section per month of the data source's range.
    public func numberOfSections(in collectionView: UICollectionView) -> Int {
        return refreshMonths()?.numberOfSections ?? 0
    }

    /// Seven columns by six rows of days in every month.
    public func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return MonthGrid.cellsPerMonth  // rows:7 x cols:6
    }

    /// A ``CalendarDayCell`` configured for the day at `indexPath`, its events and its style.
    public func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath)
        -> UICollectionViewCell
    {
        let dayCell =
            collectionView.dequeueReusableCell(withReuseIdentifier: cellReuseIdentifier, for: indexPath)
            as! CalendarDayCell

        var configuration = DayCellConfiguration(style: style)
        switch currentMonths?.content(at: indexPath) {
        case .day(let date, let dayOfMonth):
            let isToday = indexPath == todayIndexPath
            let eventsCount = eventIndex.count(at: indexPath)
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

    func accessibilityLabel(for date: Date, isToday: Bool, eventsCount: Int) -> String {
        var parts = [formatters.accessibility.string(from: date)]
        if isToday {
            parts.append(
                String(localized: "Today", bundle: .kdCalendar, comment: "VoiceOver suffix for the current day"))
        }
        if eventsCount > 0 {
            parts.append(
                String(
                    localized: "\(eventsCount) events", bundle: .kdCalendar,
                    comment: "VoiceOver suffix with the number of events on a day"))
        }
        return parts.joined(separator: ", ")
    }
}
