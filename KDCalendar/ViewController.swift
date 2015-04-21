//
//  ViewController.swift
//  KDCalendar
//
//  Created by Michael Michailidis on 01/04/2015.
//  Copyright (c) 2015 Karmadust. All rights reserved.
//

import UIKit

class ViewController: UIViewController, KDCalendarViewDataSource, KDCalendarViewDelegate {

    
    @IBOutlet weak var calendarView: KDCalendarView!
    
    
    override func viewDidLoad() {
        
        super.viewDidLoad()
        
        calendarView.dataSource = self
        calendarView.delegate = self
        
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
    
    override func viewDidLayoutSubviews() {
        
        super.viewDidLayoutSubviews()
        
        let width = self.view.frame.size.width - 16.0 * 2
        let height = width + 20.0
        self.calendarView.frame = CGRect(x: 16.0, y: 32.0, width: width, height: height)
        
        
    }
    
    
    // MARK : KDCalendarDelegate
   
    func calendar(calendar: KDCalendarView, didSelectDate date : NSDate) {
        println("\(date)")
    }
    
    func calendar(calendar: KDCalendarView, didScrollToMonth date : NSDate) {
        println("\(date)")
    }

}

