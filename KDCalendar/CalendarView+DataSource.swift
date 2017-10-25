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
    
    func numberOfSections(in collectionView: UICollectionView) -> Int {
        
        guard let startDate = self.dataSource?.startDate(), let endDate = self.dataSource?.endDate() else {
            return 0
        }
        
        self.startDateCache = startDate
        self.endDateCache = endDate
        
        // check if the dates are in correct order
        
        guard self.gregorian.compare(startDate, to:endDate, toGranularity:.nanosecond) == .orderedAscending else { return 0 }
        
        var firstDayOfStartMonth = self.gregorian.dateComponents([.era, .year, .month], from: startDateCache)
        firstDayOfStartMonth.day = 1
        
        guard let dateFromDayOneComponents = self.gregorian.date(from: firstDayOfStartMonth) else { return 0 }
        
        self.startOfMonthCache = dateFromDayOneComponents
        
        let today = Date()
        
        if self.startOfMonthCache.compare(today) == .orderedAscending && self.endDateCache.compare(today) == .orderedDescending {
            
            let differenceFromTodayComponents = self.gregorian.dateComponents([.month, .day], from: self.startOfMonthCache, to: today)
            
            self.todayIndexPath = IndexPath(item: differenceFromTodayComponents.day!, section: differenceFromTodayComponents.month!)
            
        }
        
        let differenceComponents = self.gregorian.dateComponents([.month], from: startDateCache, to: endDateCache)
        

        
        return differenceComponents.month! + 1 // if we are for example on the same month and the difference is 0 we still need 1 to display it
        
        
    }
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        
        var monthOffsetComponents = DateComponents()
        monthOffsetComponents.month = section;
        
        guard let correctMonthForSectionDate = self.gregorian.date(byAdding: monthOffsetComponents, to: startOfMonthCache) else { return 0 }
        
        var firstWeekdayOfMonthIndex    = self.gregorian.component(.weekday, from: correctMonthForSectionDate)
        firstWeekdayOfMonthIndex        = firstWeekdayOfMonthIndex - 1 // firstWeekdayOfMonthIndex should be 0-Indexed
        firstWeekdayOfMonthIndex        = (firstWeekdayOfMonthIndex + 6) % 7 // push it modularly to take it back one day where the first day is Monday instead of Sunday
        
        guard let rangeOfDaysInMonth:Range<Int> = self.gregorian.range(of: .day, in: .month, for: correctMonthForSectionDate) else { return 0 }
        
        // the format of the range returned is (1..<32) so subtract the lower to get the absolute
        let numberOfDaysInMonth         = rangeOfDaysInMonth.upperBound - rangeOfDaysInMonth.lowerBound
        
        self.monthInfo[section]         = (firstDay: firstWeekdayOfMonthIndex, daysTotal: numberOfDaysInMonth)
        
        return NUMBER_OF_DAYS_IN_WEEK * MAXIMUM_NUMBER_OF_ROWS // 7 x 6 = 42
        
    }
    
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        
        let dayCell = collectionView.dequeueReusableCell(withReuseIdentifier: cellReuseIdentifier, for: indexPath) as! CalendarDayCell
        
        let ms = DateFormatter().shortMonthSymbols[(indexPath.section % 12)]
        if self.cellCallsPerMonth[ms] == nil {
            self.cellCallsPerMonth[ms] = 0
        }
        self.cellCallsPerMonth[ms]! += 1
        
        guard let (firstDayIndex, numberOfDaysTotal) = self.monthInfo[indexPath.section] else { return dayCell }
        
        let fromStartOfMonthIndexPath = IndexPath(item: indexPath.item - firstDayIndex, section: indexPath.section) // if the first is wednesday, add 2
        
        let lastDayIndex = firstDayIndex + numberOfDaysTotal
        
        if (firstDayIndex..<lastDayIndex).contains(indexPath.item) { // item within range from first to last day
            
            dayCell.textLabel.text = String(fromStartOfMonthIndexPath.item + 1)
            dayCell.isHidden = false
            
        }
        else {
            dayCell.textLabel.text = ""
            dayCell.isHidden = true
        }
        
        dayCell.isSelected = selectedIndexPaths.contains(indexPath)
        
        if indexPath.section == 0 && indexPath.item == 0 {
            self.scrollViewDidEndDecelerating(collectionView)
        }
        
        if let idx = todayIndexPath {
            dayCell.isToday = (idx.section == indexPath.section && idx.item + firstDayIndex == indexPath.item)
        }
        
        
        if let eventsForDay = self.eventsByIndexPath[fromStartOfMonthIndexPath] {
            
            dayCell.eventsCount = eventsForDay.count
            
        } else {
            dayCell.eventsCount = 0
        }
        
        return dayCell
    }
    
}
