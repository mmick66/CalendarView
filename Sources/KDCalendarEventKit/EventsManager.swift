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
public enum EventsManagerError: Error, Sendable {
    /// The user has not granted full access to their calendars.
    case authorization
}

/// The bridge between the system event store and ``KDCalendar/CalendarEvent`` values.
///
/// Every call runs on the main actor. Full calendar access is requested the first time
/// it is needed; the app must declare `NSCalendarsFullAccessUsageDescription`.
@MainActor
public enum EventsManager {

    private static let store = EKEventStore()

    /// Whether the app currently holds full access to the user's calendars.
    public static var hasFullAccess: Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    /// Requests full access if needed and returns the events between the two dates.
    /// - Throws: ``EventsManagerError/authorization`` when access is denied.
    public static func load(from fromDate: Date, to toDate: Date) async throws -> [CalendarEvent] {
        if !hasFullAccess {
            let granted = (try? await store.requestFullAccessToEvents()) ?? false
            guard granted else { throw EventsManagerError.authorization }
        }
        return fetch(from: fromDate, to: toDate)
    }

    /// Saves an event to the user's default calendar. Returns `false` when access has not
    /// been granted or the store refuses the event.
    public static func add(event calendarEvent: CalendarEvent) -> Bool {

        guard hasFullAccess else {
            return false
        }

        let event = EKEvent(eventStore: store)
        event.title = calendarEvent.title
        event.startDate = calendarEvent.startDate
        event.endDate = calendarEvent.endDate
        event.calendar = store.defaultCalendarForNewEvents
        do {
            try store.save(event, span: .thisEvent)
            return true
        } catch {
            return false
        }
    }

    private static func fetch(from fromDate: Date, to toDate: Date) -> [CalendarEvent] {

        let predicate = store.predicateForEvents(withStart: fromDate, end: toDate, calendars: nil)

        return store.events(matching: predicate).map {
            CalendarEvent(title: $0.title, startDate: $0.startDate, endDate: $0.endDate)
        }
    }
}

// MARK: - CalendarView integration

extension CalendarView {

    /// Loads the events from the system calendar that fall inside the data source's range and
    /// assigns them to ``KDCalendar/CalendarView/events``. Asks for full calendar access if it
    /// has not been granted yet; the app must declare `NSCalendarsFullAccessUsageDescription`.
    /// - Throws: ``EventsManagerError/authorization`` when access is denied.
    public func loadEvents() async throws {
        let range = self.dateRange
        self.events = try await EventsManager.load(from: range.lowerBound, to: range.upperBound)
    }

    /// Completion-handler form of ``loadEvents()``. The handler runs on the main actor with
    /// `nil` on success or ``EventsManagerError/authorization`` when access is denied.
    public func loadEvents(onComplete: (@MainActor (Error?) -> Void)? = nil) {
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.loadEvents()
                onComplete?(nil)
            } catch {
                onComplete?(error)
            }
        }
    }

    /// Saves a new event to the user's default calendar and shows it in the view.
    /// Returns `false` when access has not been granted or the store refuses the event.
    @discardableResult public func addEvent(_ title: String, date startDate: Date, duration hours: Int = 1) -> Bool {

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

        return true
    }
}
