//
//  KDCalendarView.swift
//  KDCalendar
//
//  Created by Michael Michailidis on 02/04/2015.
//  Copyright (c) 2015 Karmadust. All rights reserved.
//

import UIKit

let reuseIdentifier = "KDCalendarDayCell"

let NUMBER_OF_DAYS_IN_WEEK = 7
let MAXIMUM_NUMBER_OF_ROWS = 6

let HEADER_DEFAULT_SIZE = 40.0

let FIRST_DAY_INDEX = 0
let NUMBER_OF_DAYS_INDEX = 1

@objc protocol KDCalendarViewDataSource {
    
    func startDate() -> NSDate?
    func endDate() -> NSDate?
    
}

@objc protocol KDCalendarViewDelegate {
    
    optional func calendar(calendar : KDCalendarView, canSelectDate : NSDate)
    func calendar(calendar : KDCalendarView, didScrollToMonth : NSDate)
    func calendar(calendar : KDCalendarView, didSelectDate : NSDate)
}

class KDCalendarView: UIView, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    
    
    
    var dataSource : KDCalendarViewDataSource?
    var delegate : KDCalendarViewDelegate?
    
    var startDateCache : NSDate = NSDate()
    var endDateCache : NSDate = NSDate()
    var startOfMonthCache : NSDate = NSDate()
    
    var cellSize = CGSizeZero
    
    lazy var collectionView : UICollectionView = {
     
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = UICollectionViewScrollDirection.Horizontal
        layout.minimumInteritemSpacing = 0
        layout.minimumLineSpacing = 0
        
        
        let cv = UICollectionView(frame: CGRectZero, collectionViewLayout: layout)
        cv.dataSource = self
        cv.delegate = self
        cv.pagingEnabled = true
        cv.backgroundColor = UIColor.clearColor()
        return cv
        
    }()
    
    
    var monthInfo : [Int:[Int]] = [Int:[Int]]()
    
    override init() {
        // just give a default size if the class is called without a frame
        super.init(frame : CGRectMake(0.0, 0.0, 200.0, 200.0))
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.initialSetup()
    }

    required init(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
    
    override func awakeFromNib() {
        self.initialSetup()
    }
    
    
    
    // MARK: Setup 
    
    func initialSetup() {
        
        
        self.collectionView.frame = self.bounds
        
        cellSize.width = self.bounds.size.width / CGFloat(NUMBER_OF_DAYS_IN_WEEK)
        cellSize.height = self.bounds.size.height / CGFloat(MAXIMUM_NUMBER_OF_ROWS)
        
        self.collectionView.registerClass(KDCalendarDayCell.self, forCellWithReuseIdentifier: reuseIdentifier)
        
        self.addSubview(self.collectionView)
    }
    
    // MARK: UICollectionViewDataSource
    
    func numberOfSectionsInCollectionView(collectionView: UICollectionView) -> Int {
        
        
        if let dateSource = self.dataSource {
            
            if let startDate = dateSource.startDate() {
                
                startDateCache = startDate
                
                if let endDate = dateSource.endDate() {
                    
                    endDateCache = endDate
                    
                    // check if the dates are in correct order
                    if NSCalendar.currentCalendar().compareDate(startDate, toDate: endDate, toUnitGranularity: NSCalendarUnit.CalendarUnitNanosecond) != NSComparisonResult.OrderedAscending {
                        
                        return 0
                        
                    }
                    
                    let dayOneComponents = NSCalendar.currentCalendar().components(NSCalendarUnit.CalendarUnitDay, fromDate: startDateCache)
                    dayOneComponents.day = 1
                    
                    if let dateFromDayOneComponents = NSCalendar.currentCalendar().dateFromComponents(dayOneComponents) {
                        
                        startOfMonthCache = dateFromDayOneComponents
                    }
                    else {
                        
                        return 0
                        
                    }
                    
                    
                    let differenceComponents = NSCalendar.currentCalendar().components(NSCalendarUnit.CalendarUnitMonth, fromDate: startDateCache, toDate: endDateCache, options: NSCalendarOptions.allZeros)
                    
                    return differenceComponents.month + 1 // if we are for example on the same month and the difference is 0 we still need 1 to display it
                    
                }
            }
            
        }
        
        
        return 0
    }
    
    
    func collectionView(collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        
        let monthOffsetComponents = NSDateComponents()
        
        // offset by the number of months
        monthOffsetComponents.month = section;
        
        if let correctMonthForSectionDate = NSCalendar.currentCalendar().dateByAddingComponents(monthOffsetComponents, toDate: startDateCache, options: NSCalendarOptions.allZeros) {
         
            let numberOfDaysInMonth = NSCalendar.currentCalendar().rangeOfUnit(NSCalendarUnit.CalendarUnitDay, inUnit: NSCalendarUnit.CalendarUnitMonth, forDate: correctMonthForSectionDate).length
            
            let firstWeekdayOfMonthIndex = NSCalendar.currentCalendar().component(NSCalendarUnit.CalendarUnitDay, fromDate: correctMonthForSectionDate) - 1 // firstWeekdayOfMonthIndex should be 0-Indexed
            
            
            monthInfo[section] = [firstWeekdayOfMonthIndex,numberOfDaysInMonth]
            
            return NUMBER_OF_DAYS_IN_WEEK * MAXIMUM_NUMBER_OF_ROWS
        }
        
        return 0
        
    }
    
    func collectionView(collectionView: UICollectionView, cellForItemAtIndexPath indexPath: NSIndexPath) -> UICollectionViewCell {
        
        let dayCell = collectionView.dequeueReusableCellWithReuseIdentifier(reuseIdentifier, forIndexPath: indexPath) as KDCalendarDayCell
     
        let currentMonthInfo : [Int] = monthInfo[indexPath.section]!
        
        if indexPath.item >= currentMonthInfo[FIRST_DAY_INDEX] && indexPath.item < currentMonthInfo[FIRST_DAY_INDEX] + currentMonthInfo[NUMBER_OF_DAYS_INDEX] {
            
            dayCell.textLabel.text = String(indexPath.item - currentMonthInfo[FIRST_DAY_INDEX])
            
            dayCell.backgroundColor = UIColor.grayColor()
            
        }
        else {
            
            dayCell.textLabel.text = ""
            
        }
        
        
        return dayCell
    }
    
    // MARK: UICollectionViewDelegateFlowLayout
    
    func collectionView(collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAtIndexPath indexPath: NSIndexPath) -> CGSize {
        return cellSize
    }

}
