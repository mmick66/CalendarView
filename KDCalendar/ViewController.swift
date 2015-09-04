//
//  ViewController.swift
//  KDCalendar
//
//  Created by Michael Michailidis on 01/04/2015.
//  Copyright (c) 2015 Karmadust. All rights reserved.
//

import UIKit
import EventKit

class ViewController: UIViewController, KDCalendarViewDataSource, KDCalendarViewDelegate {

    
    @IBOutlet weak var calendarView: KDCalendarView!
    
    
    override func viewDidLoad() {
        
        super.viewDidLoad()
        
        calendarView.dataSource = self
        calendarView.delegate = self
        
        // change the code to get a vertical calender.
        calendarView.direction = .Horizontal
        
    }
    
    override func viewDidAppear(animated: Bool) {
        super.viewDidAppear(animated)
        
        self.loadEventsInCalendar()
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
        // println("Did Select: \(date)")
    }
    
    func calendar(calendar: KDCalendarView, didScrollToMonth date : NSDate) {
        // println("Did Scroll to: \(date)")
    }

    // MARK : Events
    
    func loadEventsInCalendar() {
        
        if let  startDate = self.startDate(),
                endDate = self.endDate() {
            
            let store = EKEventStore()
            
            let fetchEvents = { () -> Void in
                
                let predicate = store.predicateForEventsWithStartDate(startDate, endDate:endDate, calendars: nil)
                
                // if can return nil for no events between these dates
                if let eventsBetweenDates = store.eventsMatchingPredicate(predicate) as? [EKEvent] {
                    
                    self.calendarView.events = eventsBetweenDates
                    
                }
                
            }
            
            let q = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0)
            
            if EKEventStore.authorizationStatusForEntityType(EKEntityTypeEvent) != EKAuthorizationStatus.Authorized {
                
                store.requestAccessToEntityType(EKEntityTypeEvent, completion: {(granted : Bool, error : NSError!) -> Void in
                    if granted {
                        fetchEvents()
                    }
                })
                
            }
            else {
                fetchEvents()
            }
            
        }
        
    }
    
}




