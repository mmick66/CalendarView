//
//  ViewController.swift
//  KDCalendar
//
//  Created by Michael Michailidis on 01/04/2015.
//  Copyright (c) 2015 Karmadust. All rights reserved.
//

import UIKit
import EventKit

class ViewController: UIViewController, CalendarViewDataSource, CalendarViewDelegate {

    
    @IBOutlet weak var calendarView: CalendarView!
    @IBOutlet weak var datePicker: UIDatePicker!
    
    
    override func viewDidLoad() {
        
        super.viewDidLoad()
        
        calendarView.dataSource = self
        calendarView.delegate = self
        
        // change the code to get a vertical calender.
        calendarView.direction = .horizontal
        
    }
    
    override func viewDidAppear(_ animated: Bool) {
        
        super.viewDidAppear(animated)
        
        self.loadEventsInCalendar()
        
        var tomorrowComponents = DateComponents()
        tomorrowComponents.day = 1
        
        let today = Date()
        
        
        if let tomorrow = (self.calendarView.calendar as NSCalendar).date(byAdding: tomorrowComponents, to: today, options: NSCalendar.Options()) {
            self.calendarView.selectDate(tomorrow)
            //self.calendarView.deselectDate(date)
            
        }
        
        self.calendarView.setDisplayDate(today, animated: false)
        self.datePicker.setDate(today, animated: false)
        
        
    }

    // MARK : KDCalendarDataSource
    
    func startDate() -> Date? {
        
        var dateComponents = DateComponents()
        dateComponents.month = -3
        
        let today = Date()
        
        let threeMonthsAgo = (self.calendarView.calendar as NSCalendar).date(byAdding: dateComponents, to: today, options: NSCalendar.Options())
        
        
        return threeMonthsAgo
    }
    
    func endDate() -> Date? {
        
        var dateComponents = DateComponents()
      
        dateComponents.year = 2;
        let today = Date()
        
        let twoYearsFromNow = (self.calendarView.calendar as NSCalendar).date(byAdding: dateComponents, to: today, options: NSCalendar.Options())
        
        return twoYearsFromNow
  
    }
    
    override func viewDidLayoutSubviews() {
        
        super.viewDidLayoutSubviews()
        
        
    }
    
    
    
    // MARK : KDCalendarDelegate
   
    func calendar(_ calendar: CalendarView, didSelectDate date : Date, withEvents events: [CalendarEvent]) {
        
        for event in events {
            print("You have an event starting at \(event.startDate) : \(event.title)")
        }
        print("Did Select: \(date) with Events: \(events.count)")
        
        
        
    }
    
    func calendar(_ calendar: CalendarView, didScrollToMonth date : Date) {
    
        self.datePicker.setDate(date, animated: true)
    }
    
    

    // MARK : Events
    
    @objc func loadEventsInCalendar() {
        
        if let  startDate = self.startDate(),
                let endDate = self.endDate() {
            
            let store = EKEventStore()
            
            let fetchEvents = { () -> Void in
                
                let predicate = store.predicateForEvents(withStart: startDate, end:endDate, calendars: nil)
                
                // if can return nil for no events between these dates
                if let eventsBetweenDates = store.events(matching: predicate) as [EKEvent]? {
                    
                    self.calendarView.events = eventsBetweenDates
                    
                }
                
            }
            
            // let q = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0)
            
            if EKEventStore.authorizationStatus(for: EKEntityType.event) != EKAuthorizationStatus.authorized {
                
                store.requestAccess(to: EKEntityType.event, completion: {(granted, error ) -> Void in
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
    
    
    // MARK : Events
    
    @IBAction func onValueChange(_ picker : UIDatePicker) {
        
        self.calendarView.setDisplayDate(picker.date, animated: true)
    
        
    }
    
    @IBAction func goToPreviousMonth(_ sender: Any) {
        
        
        self.calendarView.goToPreviousMonth()
    }
    @IBAction func goToNextMonth(_ sender: Any) {
        self.calendarView.goToNextMonth()
        
    }
    
   
    
    
    
}


extension Date {

    func applyOffSetOfMonth(calendar: Calendar, offset:Int) -> Date? {
        
        var dateComponents = DateComponents()
        
        dateComponents.month = offset;
        
        return(calendar as NSCalendar).date(byAdding: dateComponents, to: self, options: NSCalendar.Options())
        
    }

}



