//
//  KDCalendarView.swift
//  KDCalendar
//
//  Created by Michael Michailidis on 02/04/2015.
//  Copyright (c) 2015 Karmadust. All rights reserved.
//

import UIKit

let cellReuseIdentifier = "KDCalendarDayCell"

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
    
    let formatter = NSDateFormatter()
    
    var startDateCache : NSDate = NSDate()
    var endDateCache : NSDate = NSDate()
    var startOfMonthCache : NSDate = NSDate()
    
    lazy var headerView : KDCalendarHeaderView = {
       
        let hv = KDCalendarHeaderView(frame:CGRectZero)
        
        return hv
        
    }()
    
    lazy var collectionView : UICollectionView = {
     
        let layout = KDCalendarFlowLayout()
        layout.scrollDirection = UICollectionViewScrollDirection.Horizontal
        layout.minimumInteritemSpacing = 0
        layout.minimumLineSpacing = 0
        
        let cv = UICollectionView(frame: CGRectZero, collectionViewLayout: layout)
        cv.dataSource = self
        cv.delegate = self
        cv.pagingEnabled = true
        cv.backgroundColor = UIColor.clearColor()
        cv.showsHorizontalScrollIndicator = false
        cv.showsVerticalScrollIndicator = false
        
        return cv
        
    }()
    
    override var frame: CGRect {
        didSet {
            
            var elementFrame = CGRect(x:0.0, y:0.0, width: self.frame.size.width, height:80.0)
            
            self.headerView.frame = elementFrame
            
            elementFrame.origin.y += elementFrame.size.height
            elementFrame.size.height = self.frame.size.height - elementFrame.size.height
            
            self.collectionView.frame = CGRect(x:0.0, y:80.0, width: self.frame.size.width, height:self.frame.size.height - 80.0)
            
            let layout = self.collectionView.collectionViewLayout as! KDCalendarFlowLayout
            
            self.collectionView.collectionViewLayout = layout
            
        }
    }
    
    

    override init(frame: CGRect) {
        super.init(frame : CGRectMake(0.0, 0.0, 200.0, 200.0))
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
        
        
        self.clipsToBounds = true
        
        // Register Class
        self.collectionView.registerClass(KDCalendarDayCell.self, forCellWithReuseIdentifier: cellReuseIdentifier)
        
        
        self.addSubview(self.headerView)
        self.addSubview(self.collectionView)
    }
    
    
    
    // MARK: UICollectionViewDataSource
    
    func numberOfSectionsInCollectionView(collectionView: UICollectionView) -> Int {
        
        // Set the collection view to the correct layout
        let layout = self.collectionView.collectionViewLayout as! UICollectionViewFlowLayout
        layout.itemSize = CGSizeMake(self.collectionView.frame.size.width / CGFloat(NUMBER_OF_DAYS_IN_WEEK), (self.collectionView.frame.size.height - layout.headerReferenceSize.height) / CGFloat(MAXIMUM_NUMBER_OF_ROWS))
        self.collectionView.collectionViewLayout = layout
        
        
        if let dateSource = self.dataSource {
            
            if let startDate = dateSource.startDate() {
                
                startDateCache = startDate
                
                if let endDate = dateSource.endDate() {
                    
                    endDateCache = endDate
                    
                    // check if the dates are in correct order
                    if NSCalendar.currentCalendar().compareDate(startDate, toDate: endDate, toUnitGranularity: NSCalendarUnit.CalendarUnitNanosecond) != NSComparisonResult.OrderedAscending {
                        return 0
                    }
                    
                    // discart day and minutes so that they round off to the first of the month
                    let dayOneComponents = NSCalendar.currentCalendar().components(NSCalendarUnit.CalendarUnitMonth | NSCalendarUnit.CalendarUnitYear | NSCalendarUnit.CalendarUnitEra, fromDate: startDateCache)
                
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
    
    var monthInfo : [Int:[Int]] = [Int:[Int]]()
    
    func collectionView(collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        
        let monthOffsetComponents = NSDateComponents()
        
        // offset by the number of months
        monthOffsetComponents.month = section;
        
        if let correctMonthForSectionDate = NSCalendar.currentCalendar().dateByAddingComponents(monthOffsetComponents, toDate: startOfMonthCache, options: NSCalendarOptions.allZeros) {
            
            let numberOfDaysInMonth = NSCalendar.currentCalendar().rangeOfUnit(NSCalendarUnit.CalendarUnitDay, inUnit: NSCalendarUnit.CalendarUnitMonth, forDate: correctMonthForSectionDate).length
            
            var firstWeekdayOfMonthIndex = NSCalendar.currentCalendar().component(NSCalendarUnit.CalendarUnitWeekday, fromDate: correctMonthForSectionDate)
            firstWeekdayOfMonthIndex = firstWeekdayOfMonthIndex - 1 // firstWeekdayOfMonthIndex should be 0-Indexed
            firstWeekdayOfMonthIndex = (firstWeekdayOfMonthIndex + 6) % 7 // push it modularly so that we take it back one day so that the first day is Monday instead of Sunday which is the default
     
            
            monthInfo[section] = [firstWeekdayOfMonthIndex,numberOfDaysInMonth]
            
            
            
            
            return NUMBER_OF_DAYS_IN_WEEK * MAXIMUM_NUMBER_OF_ROWS // 7 x 6 = 42
        }
        
        return 0
        
    }
    
    func collectionView(collectionView: UICollectionView, cellForItemAtIndexPath indexPath: NSIndexPath) -> UICollectionViewCell {
        
        let dayCell = collectionView.dequeueReusableCellWithReuseIdentifier(cellReuseIdentifier, forIndexPath: indexPath) as! KDCalendarDayCell
     
        let currentMonthInfo : [Int] = monthInfo[indexPath.section]!
        
        if indexPath.item >= currentMonthInfo[FIRST_DAY_INDEX] && indexPath.item < currentMonthInfo[FIRST_DAY_INDEX] + currentMonthInfo[NUMBER_OF_DAYS_INDEX] {
            
            dayCell.textLabel.text = String(indexPath.item - currentMonthInfo[FIRST_DAY_INDEX] + 1)
            
            dayCell.setColor( UIColor(white: 0.0, alpha: 0.1) )
            
        }
        else {
            
            dayCell.textLabel.text = ""
            
            dayCell.setColor( UIColor.clearColor() )
            
        }
        
        if indexPath.section == 0 && indexPath.item == 0 {
            self.scrollViewDidEndDecelerating(collectionView)
        }
        

        
        return dayCell
    }
    
    // MARK: UIScrollViewDelegate
    
    
    
    func scrollViewDidEndDecelerating(scrollView: UIScrollView) {
        
        
        let cvbounds = self.collectionView.bounds
        
        let page : Int = Int(floor(self.collectionView.contentOffset.x / cvbounds.size.width))
        
        self.collectionView.collectionViewLayout.layoutAttributesForElementsInRect(cvbounds)
        
        if let monthName = formatter.monthSymbols[page] as? String {
            self.headerView.monthLabel.text = monthName
        }
        
        if let delegate = self.delegate {
            
           // inform the delegate
            
        }
        
    }
    
    // MARK: UICollectionViewDelegateFlowLayout
    
    

}
