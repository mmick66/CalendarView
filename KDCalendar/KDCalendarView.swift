//
//  KDCalendarView.swift
//  KDCalendar
//
//  Created by Michael Michailidis on 02/04/2015.
//  Copyright (c) 2015 Karmadust. All rights reserved.
//

import UIKit

let reuseIdentifier = "KDMonthCell"


@objc protocol KDCalendarViewDataSource {
    
    func startDate() -> NSDate?
    func endDate() -> NSDate?
    
}

@objc protocol KDCalendarViewDelegate {
    
    optional func calendar(calendar : KDCalendarView, canSelectDate : NSDate)
    func calendar(calendar : KDCalendarView, didScrollToMonth : NSDate)
    func calendar(calendar : KDCalendarView, didSelectDate : NSDate)
}

class KDCalendarView: UIView, UICollectionViewDataSource, UICollectionViewDelegate {
    
    var dataSource : KDCalendarViewDataSource?
    var delegate : KDCalendarViewDelegate?
    
    var startDateCache : NSDate = NSDate()
    var endDateCache : NSDate = NSDate()
    var startOfMonthCache : NSDate = NSDate()
    
    lazy var collectionView : UICollectionView = {
     
        let layout = UICollectionViewFlowLayout()
        let cv = UICollectionView(frame: CGRectZero, collectionViewLayout: layout)
        cv.dataSource = self
        cv.delegate = self
        return cv
        
    }()

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
        
        self.collectionView.registerClass(UICollectionViewCell.self, forCellWithReuseIdentifier: reuseIdentifier)
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
        
        
        
        return 0
    }
    
    func collectionView(collectionView: UICollectionView, cellForItemAtIndexPath indexPath: NSIndexPath) -> UICollectionViewCell {
        
        let cell = collectionView.dequeueReusableCellWithReuseIdentifier(reuseIdentifier, forIndexPath: indexPath) as UICollectionViewCell
        
        // Configure the cell
        
        return cell
    }

}
