//
//  ViewController.swift
//  KDCalendar
//
//  Created by Michael Michailidis on 01/04/2015.
//  Copyright (c) 2015 Karmadust. All rights reserved.
//

import UIKit

class ViewController: UIViewController, KDCalendarViewDataSource, KDCalendarViewDelegate {

    
    
    override func viewDidLoad() {
        
        super.viewDidLoad()
        
        
        
    }

    // MARK : KDCalendarDataSource
    
    func startDate() -> NSDate? {
        
        
        
        let dateComponents = NSDateComponents()
        dateComponents.month = -3
        
        let today = NSDate()
        
        let threeMonthsAgo = NSCalendar.currentCalendar().dateByAddingComponents(dateComponents, toDate: today, options: NSCalendarOptions.allZeros)
        
        return threeMonthsAgo
    }
    
    func endDate() -> NSDate? {
        
        let dateComponents = NSDateComponents()
      
        dateComponents.year = 2;
        dateComponents.month = 3;
        let today = NSDate()
        
        let threeMonthsAgo = NSCalendar.currentCalendar().dateByAddingComponents(dateComponents, toDate: today, options: NSCalendarOptions.allZeros)
        
        return threeMonthsAgo
  
    }
    
    
    // MARK : KDCalendarDelegate
   
    func calendar(calendar: KDCalendarView, didSelectDate: NSDate) {
        
    }
    
    func calendar(calendar: KDCalendarView, didScrollToMonth: NSDate) {
        
    }

}

