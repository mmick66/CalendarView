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
    
    public func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        
        guard let date = self.dateFromIndexPath(indexPath) else { return }
        
        if let index = selectedIndexPaths.firstIndex(of: indexPath) {
            
            delegate?.calendar(self, didDeselectDate: date)
            if enableDeslection {
                selectedIndexPaths.remove(at: index)
                selectedDates.remove(at: index)
            }
            
        } else {
            
            if !multipleSelectionEnable {
                selectedIndexPaths.removeAll()
                selectedDates.removeAll()
            }
            
            selectedIndexPaths.append(indexPath)
            selectedDates.append(date)
            
            let eventsForDaySelected = eventsByIndexPath[indexPath] ?? []
            delegate?.calendar(self, didSelectDate: date, withEvents: eventsForDaySelected)
        }
        
        self.reloadData()
    }
    
    public func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        
        guard let dateBeingSelected = self.dateFromIndexPath(indexPath) else { return false }
        
        if let delegate = self.delegate {
            return delegate.calendar(self, canSelectDate: dateBeingSelected)
        }
   
        return true // default
    }
    
    // MARK: UIScrollViewDelegate
    
    public func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        self.updateAndNotifyScrolling()
        
    }
    
    public func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        self.updateAndNotifyScrolling()
    }
    
    func updateAndNotifyScrolling() {
        
        guard let date = self.dateFromScrollViewPosition() else { return }
        
        self.displayDateOnHeader(date)
        self.delegate?.calendar(self, didScrollToMonth: date)
        
    }

    @discardableResult
    func dateFromScrollViewPosition() -> Date? {
        var page: Int = 0
        
        switch self.direction {
        case .horizontal:
            let offsetX = ceilf(Float(self.collectionView.contentOffset.x))
            let width = self.collectionView.bounds.size.width
            page = Int(floor(offsetX / Float(width)))
        case .vertical:
            let offsetY = ceilf(Float(self.collectionView.contentOffset.y))
            let width = self.collectionView.bounds.size.width
            page = Int(floor(offsetY / Float(width)))
        @unknown default:
            fatalError()
        }
        
        page = page > 0 ? page : 0
        
        var monthsOffsetComponents = DateComponents()
        monthsOffsetComponents.month = page
        
        return self.calendar.date(byAdding: monthsOffsetComponents, to: self.firstDayCache);
    }
    
    func displayDateOnHeader(_ date: Date) {
        let month = self.calendar.component(.month, from: date) // get month
        
        let formatter = DateFormatter()
        formatter.locale = style.locale
        formatter.timeZone = style.calendar.timeZone
        
        let monthName = formatter.monthSymbols[(month-1) % 12].capitalized // 0 indexed array
        
        let year = self.calendar.component(.year, from: date)

        self.headerView.monthLabel.text = dataSource?.headerString(date) ?? monthName + " " + String(year)
        
        self.displayDate = date
    }
}
