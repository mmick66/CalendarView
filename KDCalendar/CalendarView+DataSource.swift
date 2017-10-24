//
//  CalendarView+DataSource.swift
//  CalendarView
//
//  Created by Michael Michailidis on 24/10/2017.
//  Copyright © 2017 Karmadust. All rights reserved.
//

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
        
        // offset by the number of months
        monthOffsetComponents.month = section;
        
        guard
            let correctMonthForSectionDate = self.gregorian.date(byAdding: monthOffsetComponents, to: startOfMonthCache),
            let rangeOfDaysInMonth:Range<Int> = self.gregorian.range(of: .day, in: .month, for: correctMonthForSectionDate) else { return 0 }
        
        let numberOfDaysInMonth = rangeOfDaysInMonth.upperBound
        
        var firstWeekdayOfMonthIndex = self.gregorian.component(.weekday, from: correctMonthForSectionDate)
        firstWeekdayOfMonthIndex = firstWeekdayOfMonthIndex - 1 // firstWeekdayOfMonthIndex should be 0-Indexed
        firstWeekdayOfMonthIndex = (firstWeekdayOfMonthIndex + 6) % 7 // push it modularly so that we take it back one day so that the first day is Monday instead of Sunday which is the default
        
        monthInfo[section] = [firstWeekdayOfMonthIndex, numberOfDaysInMonth]
        
        return NUMBER_OF_DAYS_IN_WEEK * MAXIMUM_NUMBER_OF_ROWS // 7 x 6 = 42
        
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        
        let dayCell = collectionView.dequeueReusableCell(withReuseIdentifier: cellReuseIdentifier, for: indexPath) as! CalendarDayCell
        
        return dayCell
    }
    
}
