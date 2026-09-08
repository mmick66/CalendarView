/*
 * EventsManager.swift
 * Created by Michael Michailidis on 26/10/2017.
 * http://blog.karmadust.com/
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 *
 */

import EventKit
import Foundation
import KDCalendar

/// Errors reported by the EventKit integration.
public enum EventsManagerError: Error {
    /// The user has not granted full access to their calendars.
    case authorization
}

open class EventsManager {

    private static let store = EKEventStore()

    static func load(from fromDate: Date, to toDate: Date, complete onComplete: @escaping ([CalendarEvent]?) -> Void) {

        let q = DispatchQueue.main

        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {

            return EventsManager.store.requestFullAccessToEvents { granted, _ in
                guard granted else {
                    return q.async { onComplete(nil) }
                }
                EventsManager.fetch(from: fromDate, to: toDate) { events in
                    q.async { onComplete(events) }
                }
            }
        }

        EventsManager.fetch(from: fromDate, to: toDate) { events in
            q.async { onComplete(events) }
        }
    }

    static func add(event calendarEvent: CalendarEvent) -> Bool {

        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
            return false
        }

        let secondsFromGMTDifference = TimeInterval(TimeZone.current.secondsFromGMT()) * -1

        let event = EKEvent(eventStore: store)
        event.title = calendarEvent.title
        event.startDate = calendarEvent.startDate.addingTimeInterval(secondsFromGMTDifference)
        event.endDate = calendarEvent.endDate.addingTimeInterval(secondsFromGMTDifference)
        event.calendar = store.defaultCalendarForNewEvents
        do {
            try store.save(event, span: .thisEvent)
            return true
        } catch {
            return false
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

// MARK: - CalendarView integration

extension CalendarView {

    /// Loads the events from the system calendar that fall inside the data source's range and
    /// assigns them to `events`. Asks for full calendar access if it has not been granted yet;
    /// the app must declare `NSCalendarsFullAccessUsageDescription`.
    public func loadEvents(onComplete: ((Error?) -> Void)? = nil) {

        let range = self.dateRange

        EventsManager.load(from: range.lowerBound, to: range.upperBound) { [weak self] events in

            guard let self = self else { return }

            if let events = events {
                self.events = events
                onComplete?(nil)
            } else {
                onComplete?(EventsManagerError.authorization)
            }
        }
    }

    /// Saves a new event to the user's default calendar and shows it in the view.
    /// Returns `false` when access has not been granted or the store refuses the event.
    @discardableResult public func addEvent(_ title: String, date startDate: Date, duration hours: NSInteger = 1) -> Bool {

        var components = DateComponents()
        components.hour = hours

        guard let endDate = self.calendar.date(byAdding: components, to: startDate) else {
            return false
        }

        let event = CalendarEvent(title: title, startDate: startDate, endDate: endDate)

        guard EventsManager.add(event: event) else {
            return false
        }

        self.events.append(event)

        self.reloadData()

        return true
    }
}
