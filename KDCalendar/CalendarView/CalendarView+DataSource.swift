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
    
    
    public func numberOfSections(in collectionView: UICollectionView) -> Int {
        
        guard let dateSource = self.dataSource else { return 0 }
        
        self.startDateCache = dateSource.startDate()
        self.endDateCache   = dateSource.endDate()
        
        guard self.startDateCache <= self.endDateCache else { fatalError("Start date cannot be later than end date.") }
        
        var firstDayOfStartMonthComponents = self.calendar.dateComponents([.era, .year, .month], from: self.startDateCache)
        firstDayOfStartMonthComponents.day = 1
        
        let firstDayOfStartMonthDate = self.calendar.date(from: firstDayOfStartMonthComponents)!
        
        self.startOfMonthCache = firstDayOfStartMonthDate
        
        var lastDayOfEndMonthComponents = self.calendar.dateComponents([.era, .year, .month], from: self.endDateCache)
        let range = self.calendar.range(of: .day, in: .month, for: self.endDateCache)!
        lastDayOfEndMonthComponents.day = range.count
        
        self.endOfMonthCache = self.calendar.date(from: lastDayOfEndMonthComponents)!
        
        let today = Date()
        
        if (self.startOfMonthCache ... self.endOfMonthCache).contains(today) {
            
            let distanceFromTodayComponents = self.calendar.dateComponents([.month, .day], from: self.startOfMonthCache, to: today)
            
            self.todayIndexPath = IndexPath(item: distanceFromTodayComponents.day!, section: distanceFromTodayComponents.month!)
        }
        
        // if we are for example on the same month and the difference is 0 we still need 1 to display it
        return self.calendar.dateComponents([.month], from: startOfMonthCache, to: endOfMonthCache).month! + 1
    }
    
    public func getMonthInfo(for date: Date) -> (firstDay: Int, daysTotal: Int)? {
        
        var firstWeekdayOfMonthIndex    = self.calendar.component(.weekday, from: date)
        firstWeekdayOfMonthIndex       -= CalendarView.Style.firstWeekday == .monday ? 1 : 0 
        firstWeekdayOfMonthIndex        = (firstWeekdayOfMonthIndex + 6) % 7 // push it modularly to take it back one day where the first day is Monday instead of Sunday
        
        guard let rangeOfDaysInMonth = self.calendar.range(of: .day, in: .month, for: date) else { return nil }
        
        return (firstDay: firstWeekdayOfMonthIndex, daysTotal: rangeOfDaysInMonth.count)
    }
    
    public func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        
        var monthOffsetComponents = DateComponents()
        monthOffsetComponents.month = section;
        
        guard
            let correctMonthForSectionDate = self.calendar.date(byAdding: monthOffsetComponents, to: startOfMonthCache),
            let info = self.getMonthInfo(for: correctMonthForSectionDate) else { return 0 }
        
        self.monthInfoForSection[section] = info
        
        return 42 // rows:7 x cols:6
        
    }
    
    public func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        
        let dayCell = collectionView.dequeueReusableCell(withReuseIdentifier: cellReuseIdentifier, for: indexPath) as! CalendarDayCell
        
        guard let (firstDayIndex, numberOfDaysTotal) = self.monthInfoForSection[indexPath.section] else { return dayCell }
        
        let fromStartOfMonthIndexPath = IndexPath(item: indexPath.item - firstDayIndex, section: indexPath.section) // if the first is wednesday, add 2
        
        let lastDayIndex = firstDayIndex + numberOfDaysTotal
        
        if (firstDayIndex..<lastDayIndex).contains(indexPath.item) { // item within range from first to last day
            dayCell.textLabel.text = String(fromStartOfMonthIndexPath.item + 1)
            dayCell.isHidden = false
            
        } else {
            dayCell.textLabel.text = ""
            dayCell.isHidden = true
        }
        
        if indexPath.section == 0 && indexPath.item == 0 {
            self.scrollViewDidEndDecelerating(collectionView)
        }
        
        if let idx = todayIndexPath {
            dayCell.isToday = (idx.section == indexPath.section && idx.item + firstDayIndex == indexPath.item)
        }
        
        dayCell.isSelected = selectedIndexPaths.contains(indexPath)
        
        if self.marksWeekends {
            let we = indexPath.item % 7
            dayCell.isWeekend = we == 5 || we == 6
        }
        
        if let eventsForDay = self.eventsByIndexPath[indexPath] {
            dayCell.eventsCount = eventsForDay.count
        } else {
            dayCell.eventsCount = 0
        }
        
        return dayCell
    }
}
