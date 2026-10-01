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
/// be passed as the `store` argument of any call that takes one.
@MainActor
public protocol CalendarEventStore: AnyObject {
    /// Whether the app holds full access to the user's calendars.
    var hasFullAccess: Bool { get }
    /// Asks the user for full access. Returns whether it was granted.
    func requestFullAccess() async throws -> Bool
    /// The events that overlap the interval, as `CalendarEvent` values. `EKEventStore` runs
    /// the query off the main actor.
    func events(from start: Date, to end: Date) async -> [CalendarEvent]
    /// Saves a new event to the default calendar.
    func save(_ event: CalendarEvent) throws
}

extension TimeInterval {
    /// The longest interval sent to EventKit in one query: four years less a day, inside the
    /// four-year span `predicateForEvents(withStart:end:calendars:)` accepts.
    static let eventKitQueryLimit: TimeInterval = (4 * 365 - 1) * 24 * 60 * 60
}

extension DateInterval {
    /// Splits the interval into consecutive intervals no longer than `maxDuration`, each
    /// starting where the previous one ends. An interval that fits comes back whole.
    func chunked(maxDuration: TimeInterval) -> [DateInterval] {
        precondition(maxDuration > 0, "maxDuration must be positive")
        var chunks: [DateInterval] = []
        var chunkStart = start
        while end.timeIntervalSince(chunkStart) > maxDuration {
            let chunk = DateInterval(start: chunkStart, duration: maxDuration)
            chunks.append(chunk)
            chunkStart = chunk.end
        }
        chunks.append(DateInterval(start: chunkStart, end: end))
        return chunks
    }
}

/// An event as EventKit returns it, so that one found by two chunked queries counts once.
/// Occurrences of a recurring event share an identifier, so the start date tells them apart.
private struct Occurrence: Hashable {
    let identifier: String?
    let startDate: Date?

    init(_ event: EKEvent) {
        self.identifier = event.eventIdentifier
        self.startDate = event.startDate
    }
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
    /// returned once, and an interval that ends before it starts finds nothing. The query is
    /// synchronous and can be slow, so it runs off the main actor.
    public nonisolated func events(from start: Date, to end: Date) async -> [CalendarEvent] {
        guard start <= end else { return [] }
        var seen = Set<Occurrence>()
        var result: [CalendarEvent] = []
        for chunk in DateInterval(start: start, end: end).chunked(maxDuration: .eventKitQueryLimit) {
            let predicate = predicateForEvents(withStart: chunk.start, end: chunk.end, calendars: nil)
            for event in events(matching: predicate) {
                guard seen.insert(Occurrence(event)).inserted else { continue }
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
/// Every call is made on the main actor, though `EKEventStore` runs its queries off it. Full
/// calendar access is requested the first time it is needed; the app must declare
/// `NSCalendarsFullAccessUsageDescription`. Calls use the shared ``store`` unless given
/// another.
@MainActor
public enum EventsManager {

    /// The system event store calls use by default. One store is shared because an
    /// `EKEventStore` is expensive to create; pass a ``CalendarEventStore`` of your own as
    /// the `store` argument to test without calendar access.
    public static let store = EKEventStore()

    /// Whether the app currently holds full access to the user's calendars.
    public static var hasFullAccess: Bool {
        store.hasFullAccess
    }

    /// Requests full access if needed and returns the events between the two dates.
    /// - Throws: ``EventsManagerError/authorization`` when access is denied, or the error
    ///   the store threw while asking for it.
    public static func load(
        from fromDate: Date,
        to toDate: Date,
        store: any CalendarEventStore = EventsManager.store
    ) async throws -> [CalendarEvent] {
        if !store.hasFullAccess {
            guard try await store.requestFullAccess() else { throw EventsManagerError.authorization }
        }
        return await store.events(from: fromDate, to: toDate)
    }

    /// Saves an event to the user's default calendar. Does not ask for access.
    /// - Throws: ``EventsManagerError/authorization`` when access has not been granted, or
    ///   the error the store threw when it refused the event.
    public static func save(
        _ calendarEvent: CalendarEvent,
        store: any CalendarEventStore = EventsManager.store
    ) throws {
        guard store.hasFullAccess else { throw EventsManagerError.authorization }
        try store.save(calendarEvent)
    }

    /// Saves an event to the user's default calendar. Returns `false` when access has not
    /// been granted or the store refuses the event; ``save(_:store:)`` says which.
    public static func add(
        event calendarEvent: CalendarEvent,
        store: any CalendarEventStore = EventsManager.store
    ) -> Bool {
        (try? save(calendarEvent, store: store)) != nil
    }
}

// MARK: - CalendarView integration

extension CalendarView {

    /// Loads the events from the system calendar that fall inside the data source's range and
    /// assigns them to `events`. Asks for full calendar access if it
    /// has not been granted yet; the app must declare `NSCalendarsFullAccessUsageDescription`.
    /// - Parameter store: The store to read; ``EventsManager/store`` by default.
    /// - Throws: ``EventsManagerError/authorization`` when access is denied, or the error
    ///   the store threw while asking for it.
    public func loadEvents(store: any CalendarEventStore = EventsManager.store) async throws {
        let range = self.dateRange
        guard let end = calendar.date(byAdding: .day, value: 1, to: range.upperBound) else { return }
        self.events = try await EventsManager.load(from: range.lowerBound, to: end, store: store)
    }

    /// Completion-handler form of ``loadEvents(store:)``. The handler runs on the main actor
    /// with `nil` on success or the error ``loadEvents(store:)`` threw.
    public func loadEvents(
        store: any CalendarEventStore = EventsManager.store,
        onComplete: (@MainActor (Error?) -> Void)? = nil
    ) {
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.loadEvents(store: store)
                onComplete?(nil)
            } catch {
                onComplete?(error)
            }
        }
    }

    /// Saves an event to the user's default calendar and shows it in the view. Does not ask
    /// for access.
    /// - Parameters:
    ///   - event: The event to save.
    ///   - store: The store to save to; ``EventsManager/store`` by default.
    /// - Throws: ``EventsManagerError/authorization`` when access has not been granted, or
    ///   the error the store threw when it refused the event.
    public func saveEvent(_ event: CalendarEvent, store: any CalendarEventStore = EventsManager.store) throws {
        try EventsManager.save(event, store: store)
        self.events.append(event)
    }

    /// Saves a new event of `hours` hours to the user's default calendar and shows it in
    /// the view. Returns `false` when access has not been granted or the store refuses the
    /// event; ``saveEvent(_:store:)`` says which.
    @discardableResult public func addEvent(
        _ title: String,
        date startDate: Date,
        duration hours: Int = 1,
        store: any CalendarEventStore = EventsManager.store
    ) -> Bool {
        guard let endDate = self.calendar.date(byAdding: .hour, value: hours, to: startDate) else {
            return false
        }
        let event = CalendarEvent(title: title, startDate: startDate, endDate: endDate)
        return (try? saveEvent(event, store: store)) != nil
    }
}
