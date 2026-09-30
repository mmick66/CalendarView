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

/// The part of an event store the bridge needs. `EKEventStore` conforms; a test double can
/// stand in through ``EventsManager/store``.
@MainActor
public protocol CalendarEventStore: AnyObject {
    /// Whether the app holds full access to the user's calendars.
    var hasFullAccess: Bool { get }
    /// Asks the user for full access. Returns whether it was granted.
    func requestFullAccess() async throws -> Bool
    /// The events that overlap the interval, as `CalendarEvent` values.
    func events(from start: Date, to end: Date) -> [CalendarEvent]
    /// Saves a new event to the default calendar.
    func save(_ event: CalendarEvent) throws
}

extension EKEventStore: CalendarEventStore {

    public var hasFullAccess: Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    public func requestFullAccess() async throws -> Bool {
        try await requestFullAccessToEvents()
    }

    /// Queries the interval in chunks shorter than four years, since EventKit shortens a
    /// longer interval to its first four years. An event that overlaps two chunks is
    /// returned once.
    public func events(from start: Date, to end: Date) -> [CalendarEvent] {
        struct Occurrence: Hashable {
            let identifier: String?
            let startDate: Date?
        }
        var seen = Set<Occurrence>()
        var result: [CalendarEvent] = []
        for chunk in EventsManager.queryIntervals(from: start, to: end) {
            let predicate = predicateForEvents(withStart: chunk.start, end: chunk.end, calendars: nil)
            for event in events(matching: predicate) {
                // Occurrences of a recurring event share an identifier but not a start date.
                let occurrence = Occurrence(identifier: event.eventIdentifier, startDate: event.startDate)
                guard seen.insert(occurrence).inserted else { continue }
                result.append(CalendarEvent(title: event.title, startDate: event.startDate, endDate: event.endDate))
            }
        }
        return result
    }

    public func save(_ calendarEvent: CalendarEvent) throws {
        let event = EKEvent(eventStore: self)
        event.title = calendarEvent.title
        event.startDate = calendarEvent.startDate
        event.endDate = calendarEvent.endDate
        event.calendar = defaultCalendarForNewEvents
        try save(event, span: .thisEvent)
    }
}

/// The bridge between the system event store and `CalendarEvent` values.
///
/// Every call runs on the main actor. Full calendar access is requested the first time
/// it is needed; the app must declare `NSCalendarsFullAccessUsageDescription`.
@MainActor
public enum EventsManager {

    /// The store every call goes through. `EKEventStore` by default; replace it with a
    /// ``CalendarEventStore`` of your own to test without calendar access.
    public static var store: any CalendarEventStore = EKEventStore()

    /// Whether the app currently holds full access to the user's calendars.
    public static var hasFullAccess: Bool {
        store.hasFullAccess
    }

    /// The longest interval sent to EventKit in one query: four years less a day, inside the
    /// four-year span `predicateForEvents(withStart:end:calendars:)` accepts.
    nonisolated static let maximumQueryLength: TimeInterval = (4 * 365 - 1) * 24 * 60 * 60

    /// Splits the interval into consecutive chunks no longer than ``maximumQueryLength``.
    /// An interval that fits, or that ends before it starts, comes back as one chunk.
    nonisolated static func queryIntervals(from start: Date, to end: Date) -> [(start: Date, end: Date)] {
        var intervals: [(start: Date, end: Date)] = []
        var chunkStart = start
        while end.timeIntervalSince(chunkStart) > maximumQueryLength {
            let chunkEnd = chunkStart.addingTimeInterval(maximumQueryLength)
            intervals.append((chunkStart, chunkEnd))
            chunkStart = chunkEnd
        }
        intervals.append((chunkStart, end))
        return intervals
    }

    /// Requests full access if needed and returns the events between the two dates.
    /// - Throws: ``EventsManagerError/authorization`` when access is denied.
    public static func load(from fromDate: Date, to toDate: Date) async throws -> [CalendarEvent] {
        if !hasFullAccess {
            let granted = (try? await store.requestFullAccess()) ?? false
            guard granted else { throw EventsManagerError.authorization }
        }
        return store.events(from: fromDate, to: toDate)
    }

    /// Saves an event to the user's default calendar. Returns `false` when access has not
    /// been granted or the store refuses the event.
    public static func add(event calendarEvent: CalendarEvent) -> Bool {
        guard hasFullAccess else {
            return false
        }
        do {
            try store.save(calendarEvent)
            return true
        } catch {
            return false
        }
    }
}

// MARK: - CalendarView integration

extension CalendarView {

    /// Loads the events from the system calendar that fall inside the data source's range and
    /// assigns them to `events`. Asks for full calendar access if it
    /// has not been granted yet; the app must declare `NSCalendarsFullAccessUsageDescription`.
    /// - Throws: ``EventsManagerError/authorization`` when access is denied.
    public func loadEvents() async throws {
        let range = self.dateRange
        guard let end = calendar.date(byAdding: .day, value: 1, to: range.upperBound) else { return }
        self.events = try await EventsManager.load(from: range.lowerBound, to: end)
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
