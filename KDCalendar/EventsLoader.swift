//
//  EventsLoader.swift
//  CalendarView
//
//  Created by Michael Michailidis on 26/10/2017.
//  Copyright © 2017 Karmadust. All rights reserved.
//

import Foundation
import EventKit

class EventsLoader {
    
    private static let store = EKEventStore()
    
    static func load(from fromDate: Date, to toDate: Date, complete onComplete: @escaping (Bool, [CalendarEvent]) -> Void) {
        
        let q = DispatchQueue.main
        guard EKEventStore.authorizationStatus(for: .event) == .authorized else {
            
            return EventsLoader.store.requestAccess(to: EKEntityType.event, completion: {(granted, error) -> Void in
                guard granted else {
                    return q.async { onComplete(false, []) }
                }
                EventsLoader.fetch(from: fromDate, to: toDate) { events in
                    q.async { onComplete(true, events) }
                }
            })
        }
        
        EventsLoader.fetch(from: fromDate, to: toDate) { events in
            q.async { onComplete(true, events) }
        }
        
    }
    
    private static func fetch(from fromDate: Date, to toDate: Date, complete onComplete: @escaping ([CalendarEvent]) -> Void) {
        
        let predicate = store.predicateForEvents(withStart: fromDate, end: toDate, calendars: nil)
        
        let secondsFromGMTDifference = TimeInterval(TimeZone.current.secondsFromGMT())
        
        let events = store.events(matching: predicate).map {
            return CalendarEvent(
                title:      $0.title,
                startDate:  $0.startDate.addingTimeInterval(secondsFromGMTDifference),
                endDate:    $0.endDate.addingTimeInterval(secondsFromGMTDifference)
            )
        }
        
        onComplete(events)
        
    }
}
