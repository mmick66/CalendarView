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
        
        let getComponents = { (date: Date) -> DateComponents in
            self.calendar.dateComponents([.era, .year, .month, .day], from: date)
        }
        
        let startDateComponents = getComponents(self.startDateCache)
        let endDateComponents = getComponents(self.endDateCache)
        
        var firstDayOfStartMonthComponents = startDateComponents
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
        
        // how many months should the whole calendar display?
        let numberOfMonths = self.calendar.dateComponents([.month], from: startOfMonthCache, to: endOfMonthCache).month!
        
        // subtract one to include the day
        self.startIndexPath = IndexPath(item: startDateComponents.day! - 1, section: 0)
        self.endIndexPath = IndexPath(item: endDateComponents.day! - 1, section: numberOfMonths)
        
        // if we are for example on the same month and the difference is 0 we still need 1 to display it
        return numberOfMonths + 1
    }
    
    public func getMonthInfo(for date: Date) -> (firstDay: Int, daysTotal: Int)? {
        
        var firstWeekdayOfMonthIndex    = self.calendar.component(.weekday, from: date)
        firstWeekdayOfMonthIndex       -= CalendarView.Style.firstWeekday == .monday ? 1 : 0 
        firstWeekdayOfMonthIndex        = (firstWeekdayOfMonthIndex + 6) % 7 // push it modularly to map it in the range 0 to 6
        
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
        
        dayCell.clearStyles()
        
        guard let (firstDayIndex, numberOfDaysTotal) = self.monthInfoForSection[indexPath.section] else { return dayCell }
        
        let lastDayIndex = firstDayIndex + numberOfDaysTotal
        
        let cellOutOfRange = { (indexPath: IndexPath) -> Bool in
            if self.startIndexPath.section == indexPath.section { // is 0
                return self.startIndexPath.item + firstDayIndex > indexPath.item
            }
            if self.endIndexPath.section == indexPath.section {
                return self.endIndexPath.item + firstDayIndex < indexPath.item
            }
            return false
        }
    
        // the index of this cell is within the range of first and the last day of the month
        if (firstDayIndex..<lastDayIndex).contains(indexPath.item) {
            // ex. if the first is wednesday (index of 3), subtract 2 to show it as 1
            dayCell.textLabel.text = String((indexPath.item - firstDayIndex) + 1)
            dayCell.isHidden = false
            
            dayCell.isOutOfRange = cellOutOfRange(indexPath)
            
        } else {
            dayCell.textLabel.text = ""
            dayCell.isHidden = true
        }
        
        // hack: send once at the beginning
        if indexPath.section == 0 && indexPath.item == 0 {
            self.scrollViewDidEndDecelerating(collectionView)
        }
        
        guard !dayCell.isOutOfRange else { return dayCell }
        
        // if is in range continue with additional styling
        
        if let idx = self.todayIndexPath {
            dayCell.isToday = (idx.section == indexPath.section && idx.item + firstDayIndex == indexPath.item)
        }
        
        dayCell.isSelected = selectedIndexPaths.contains(indexPath)
        
        if self.marksWeekends {
            let we = indexPath.item % 7
            let weekDayOption = CalendarView.Style.firstWeekday == .sunday ? 0 : 5
            dayCell.isWeekend = we == weekDayOption || we == 6
        }
        
        dayCell.eventsCount = self.eventsByIndexPath[indexPath]?.count ?? 0
        
        return dayCell
    }
}


