/*
 * CalendarView+Delegate.swift
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

extension CalendarView: UICollectionViewDelegateFlowLayout {
    
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        
        guard
            let dateBeingSelectedByUser = self.dateBeingSelectedByUser,
            let (firstDayIndex, _) = self.monthInfo[indexPath.section] else { return }
        
        let fromStartOfMonthIndexPath = IndexPath(item: indexPath.item - firstDayIndex, section: indexPath.section)
        
        var eventsArray = [CalendarEvent]()
        
        if let eventsForDay = eventsByIndexPath[fromStartOfMonthIndexPath] {
            eventsArray = eventsForDay;
        }
        
        delegate?.calendar(self, didSelectDate: dateBeingSelectedByUser, withEvents: eventsArray)
        
        // Update model
        selectedIndexPaths.append(indexPath)
        selectedDates.append(dateBeingSelectedByUser)
    }
    
    func collectionView(_ collectionView: UICollectionView, didDeselectItemAt indexPath: IndexPath) {
        
        guard let dateBeingSelectedByUser = dateBeingSelectedByUser else {
            return
        }
        
        guard let index = selectedIndexPaths.index(of: indexPath) else {
            return
        }
        
        delegate?.calendar(self, didDeselectDate: dateBeingSelectedByUser)
        
        selectedIndexPaths.remove(at: index)
        selectedDates.remove(at: index)
        
        
        if self.calendarView.allowsMultipleSelection {
            self.dateBeingSelectedByUser = selectedDates.last
        } else {
            self.dateBeingSelectedByUser = nil
            
        }
    }
    
    func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        
        guard let (firstDayInMonth, _) = self.monthInfo[indexPath.section] else { return false }
        
        var offsetComponents    = DateComponents()
        offsetComponents.month  = indexPath.section
        offsetComponents.day    = indexPath.item - firstDayInMonth
        
        guard let dateUserSelected = self.gregorian.date(byAdding: offsetComponents, to: startOfMonthCache) else { return false }
        
        dateBeingSelectedByUser = dateUserSelected
        
        if let delegate = self.delegate {
            return delegate.calendar(self, canSelectDate: dateUserSelected)
        }
   
        return true // default
    }
    
    
    // MARK: UIScrollViewDelegate
    
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        
        if  let date = self.dateFromScrollViewPosition(),
            let delegate = self.delegate {
            
            delegate.calendar(self, didScrollToMonth: date)
            self.displayDate = date
        }
        
    }
    
    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
  
        guard let date = self.dateFromScrollViewPosition() else { return }
        
        self.displayDateOnHeader(date)
        self.delegate?.calendar(self, didScrollToMonth: date)
        
        print(self.cellCallsPerMonth)
        self.cellCallsPerMonth.removeAll()
    }

    @discardableResult
    func dateFromScrollViewPosition() -> Date? {
        
        var page: Int = 0
        
        switch self.direction {
        case .horizontal:   page = Int(floor(self.calendarView.contentOffset.x / self.calendarView.bounds.size.width))
        case .vertical:     page = Int(floor(self.calendarView.contentOffset.y / self.calendarView.bounds.size.height))
        }
        
        page = page > 0 ? page : 0
        
        var monthsOffsetComponents = DateComponents()
        monthsOffsetComponents.month = page
        
        return self.gregorian.date(byAdding: monthsOffsetComponents, to: self.startOfMonthCache);
        
    }
    
    func displayDateOnHeader(_ date: Date) {
        
        let month = self.gregorian.component(.month, from: date) // get month
        
        let monthName = DateFormatter().monthSymbols[(month-1) % 12] // 0 indexed array
        
        let year = self.gregorian.component(.year, from: date)
        
        
        self.headerView.monthLabel.text = monthName + " " + String(year)
        
        self.displayDate = date
    }
}
