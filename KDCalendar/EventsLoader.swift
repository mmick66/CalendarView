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
    
    static func load(from fromDate: Date, to toDate: Date, complete onComplete: @escaping (Bool, [EKEvent]) -> Void) {
        
        if EKEventStore.authorizationStatus(for: .event) != .authorized {
            
            EventsLoader.store.requestAccess(to: EKEntityType.event, completion: {(granted, error) -> Void in
                guard granted else {
                    DispatchQueue.main.async { onComplete(false, []) }
                    return
                }
                EventsLoader.fetchEvents(from: fromDate, to: toDate) { eventsFetched in DispatchQueue.main.async { onComplete(true, eventsFetched) } }
            })
        }
        else {
            EventsLoader.fetchEvents(from: fromDate, to: toDate) { eventsFetched in DispatchQueue.main.async { onComplete(true, eventsFetched) } }
        }
        
    }
    
    private static func fetchEvents(from fromDate: Date, to toDate: Date, complete onComplete: @escaping ([EKEvent]) -> Void) {
        
        let predicate = store.predicateForEvents(withStart: fromDate, end: toDate, calendars: nil)
        
        let eventsBetweenDates = store.events(matching: predicate)
        onComplete(eventsBetweenDates)
        
    }
}
