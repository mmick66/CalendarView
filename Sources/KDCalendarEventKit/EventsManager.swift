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
/// stand in for it through ``EventsManager/init(store:)``.
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
    /// Splits the interval into consecutive intervals no longer than `maxDuration`, each starting
    /// where the previous one ends.
    ///
    /// An interval that fits comes back whole.
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
///
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

    /// Whether the authorization status for events is full access.
    public var hasFullAccess: Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    /// Asks for full access to events with `requestFullAccessToEvents()`.
    public func requestFullAccess() async throws -> Bool {
        try await requestFullAccessToEvents()
    }

    /// Queries the interval in chunks shorter than four years, since EventKit shortens a longer
    /// interval to its first four years.
    ///
    /// An event that overlaps two chunks is returned once, and an interval that ends before it
    /// starts finds nothing.
    ///
    /// The query is synchronous and can be slow, so the method is `@concurrent`: it runs off
    /// the caller's actor, which for ``EventsManager`` is the main actor. Without the
    /// attribute it would stay off the main actor today but run on it once
    /// `NonisolatedNonsendingByDefault` (SE-0461) is on, blocking scrolling for the length of
    /// the query. Compilers before Swift 6.2 lack the attribute and run a `nonisolated async`
    /// method off the caller's actor anyway.
    #if compiler(>=6.2)
    @concurrent
    #endif
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

    /// Saves the event to the default calendar for new events.
    public func save(_ calendarEvent: CalendarEvent) throws {
        let event = EKEvent(eventStore: self)
        event.title = calendarEvent.title
        event.startDate = calendarEvent.startDate
        event.endDate = calendarEvent.endDate
        event.calendar = defaultCalendarForNewEvents
        try save(event, span: .thisEvent)
    }
}

/// The bridge between an event store and `CalendarEvent` values.
///
/// Every call is made on the main actor, though `EKEventStore` runs its queries off it. Full
/// calendar access is requested the first time it is needed; the app must declare
/// `NSCalendarsFullAccessUsageDescription`. Use ``shared`` for the system event store, or
/// make a manager around a ``CalendarEventStore`` of your own to test without calendar
/// access.
@MainActor
public struct EventsManager {

    /// The manager of the system event store.
    ///
    /// One store is shared because an `EKEventStore` is expensive to create.
    public static let shared = EventsManager(store: systemStore)

    private static let systemStore = EKEventStore()

    /// The store the manager reads and writes.
    public let store: any CalendarEventStore

    /// Creates a manager that reads and writes `store`.
    public init(store: any CalendarEventStore) {
        self.store = store
    }

    /// Whether the app currently holds full access to the user's calendars.
    public var hasFullAccess: Bool {
        store.hasFullAccess
    }

    /// Requests full access if needed and returns the events between the two dates.
    /// - Throws: ``EventsManagerError/authorization`` when access is denied, or the error
    ///   the store threw while asking for it.
    public func load(from fromDate: Date, to toDate: Date) async throws -> [CalendarEvent] {
        if !store.hasFullAccess {
            guard try await store.requestFullAccess() else { throw EventsManagerError.authorization }
        }
        return await store.events(from: fromDate, to: toDate)
    }

    /// Saves an event to the user's default calendar.
    ///
    /// Does not ask for access.
    ///
    /// - Throws: ``EventsManagerError/authorization`` when access has not been granted, or
    ///   the error the store threw when it refused the event.
    public func save(_ calendarEvent: CalendarEvent) throws {
        guard store.hasFullAccess else { throw EventsManagerError.authorization }
        try store.save(calendarEvent)
    }
}

// MARK: - Deprecated static forms

extension EventsManager {

    /// The system event store.
    @available(*, deprecated, message: "Use EventsManager.shared.store")
    public static var store: EKEventStore {
        systemStore
    }

    /// Whether the app currently holds full access to the user's calendars.
    @available(*, deprecated, message: "Use EventsManager.shared.hasFullAccess")
    public static var hasFullAccess: Bool {
        shared.hasFullAccess
    }

    /// Requests full access if needed and returns the events between the two dates.
    @available(*, deprecated, message: "Use EventsManager.shared.load(from:to:), or EventsManager(store:)")
    public static func load(
        from fromDate: Date,
        to toDate: Date,
        store: any CalendarEventStore = EventsManager.shared.store
    ) async throws -> [CalendarEvent] {
        try await EventsManager(store: store).load(from: fromDate, to: toDate)
    }

    /// Saves an event to the user's default calendar.
    ///
    /// Does not ask for access.
    @available(*, deprecated, message: "Use EventsManager.shared.save(_:), or EventsManager(store:)")
    public static func save(
        _ calendarEvent: CalendarEvent,
        store: any CalendarEventStore = EventsManager.shared.store
    ) throws {
        try EventsManager(store: store).save(calendarEvent)
    }

    /// Saves an event to the user's default calendar.
    ///
    /// Returns `false` when access has not been granted or the store refuses the event.
    @available(*, deprecated, message: "Use EventsManager.shared.save(_:), which throws the reason")
    public static func add(
        event calendarEvent: CalendarEvent,
        store: any CalendarEventStore = EventsManager.shared.store
    ) -> Bool {
        (try? EventsManager(store: store).save(calendarEvent)) != nil
    }
}

// MARK: - CalendarView integration

@MainActor private var eventsManagerKey: UInt8 = 0
@MainActor private var eventsLoadKey: UInt8 = 0

extension CalendarView {

    /// The manager that ``loadEvents()``, ``saveEvent(_:)`` and ``addEvent(_:date:duration:)`` use;
    /// ``EventsManager/shared`` by default.
    ///
    /// Assign a manager around another ``CalendarEventStore`` to test without calendar access.
    public var eventsManager: EventsManager {
        get { objc_getAssociatedObject(self, &eventsManagerKey) as? EventsManager ?? .shared }
        set { objc_setAssociatedObject(self, &eventsManagerKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    /// Loads the events from the system calendar that fall inside the data source's range and
    /// assigns them to `events`.
    ///
    /// Asks for full calendar access if it has not been granted yet; the app must declare
    /// `NSCalendarsFullAccessUsageDescription`.
    ///
    /// A load supersedes any load still running, so the last call wins however long each query
    /// takes: a superseded load leaves `events` alone and throws `CancellationError`.
    ///
    /// - Throws: ``EventsManagerError/authorization`` when access is denied, the error the
    ///   store threw while asking for it, or `CancellationError` when a later load started
    ///   before this one finished.
    public func loadEvents() async throws {
        try await loadEvents(using: eventsManager)
    }

    /// Completion-handler form of ``loadEvents()``.
    ///
    /// The handler runs on the main actor with `nil` on success or the error ``loadEvents()``
    /// threw, which is `CancellationError` when a later load superseded this one.
    public func loadEvents(onComplete: (@MainActor (_ error: Error?) -> Void)? = nil) {
        loadEvents(using: eventsManager, onComplete: onComplete)
    }

    /// Saves an event to the user's default calendar and shows it in the view.
    ///
    /// Does not ask for access.
    ///
    /// - Throws: ``EventsManagerError/authorization`` when access has not been granted, or
    ///   the error the store threw when it refused the event.
    public func saveEvent(_ event: CalendarEvent) throws {
        try saveEvent(event, using: eventsManager)
    }

    /// Saves a new event of `hours` hours to the user's default calendar and shows it in the view.
    ///
    /// Returns `false` when access has not been granted or the store refuses the event;
    /// ``saveEvent(_:)`` says which.
    @discardableResult public func addEvent(_ title: String, date startDate: Date, duration hours: Int = 1) -> Bool {
        addEvent(title, date: startDate, duration: hours, using: eventsManager)
    }

    /// Counts the loads started on this view, so that a load can tell whether a later one has
    /// superseded it.
    private var eventsLoad: Int {
        get { objc_getAssociatedObject(self, &eventsLoadKey) as? Int ?? 0 }
        set { objc_setAssociatedObject(self, &eventsLoadKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    private func loadEvents(using manager: EventsManager) async throws {
        eventsLoad += 1
        let load = eventsLoad
        let range = self.dateRange
        guard let end = calendar.date(byAdding: .day, value: 1, to: range.upperBound) else { return }
        let events = try await manager.load(from: range.lowerBound, to: end)
        // Queries can finish out of order; only the latest load may assign its events.
        guard load == eventsLoad else { throw CancellationError() }
        self.events = events
    }

    private func loadEvents(using manager: EventsManager, onComplete: (@MainActor (_ error: Error?) -> Void)?) {
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.loadEvents(using: manager)
                onComplete?(nil)
            } catch {
                onComplete?(error)
            }
        }
    }

    private func saveEvent(_ event: CalendarEvent, using manager: EventsManager) throws {
        try manager.save(event)
        self.events.append(event)
    }

    private func addEvent(
        _ title: String,
        date startDate: Date,
        duration hours: Int,
        using manager: EventsManager
    ) -> Bool {
        guard let endDate = self.calendar.date(byAdding: .hour, value: hours, to: startDate) else {
            return false
        }
        let event = CalendarEvent(title: title, startDate: startDate, endDate: endDate)
        return (try? saveEvent(event, using: manager)) != nil
    }
}

// MARK: - Deprecated store parameters

extension CalendarView {

    /// Loads the events from `store` that fall inside the data source's range.
    @available(*, deprecated, message: "Set eventsManager to EventsManager(store:) and call loadEvents()")
    public func loadEvents(store: any CalendarEventStore) async throws {
        try await loadEvents(using: EventsManager(store: store))
    }

    /// Completion-handler form of ``loadEvents(store:)``.
    @available(*, deprecated, message: "Set eventsManager to EventsManager(store:) and call loadEvents(onComplete:)")
    public func loadEvents(store: any CalendarEventStore, onComplete: (@MainActor (_ error: Error?) -> Void)? = nil) {
        loadEvents(using: EventsManager(store: store), onComplete: onComplete)
    }

    /// Saves an event to `store` and shows it in the view.
    @available(*, deprecated, message: "Set eventsManager to EventsManager(store:) and call saveEvent(_:)")
    public func saveEvent(_ event: CalendarEvent, store: any CalendarEventStore) throws {
        try saveEvent(event, using: EventsManager(store: store))
    }

    /// Saves a new event of `hours` hours to `store` and shows it in the view.
    @available(*, deprecated, message: "Set eventsManager to EventsManager(store:) and call addEvent(_:date:duration:)")
    @discardableResult public func addEvent(
        _ title: String,
        date startDate: Date,
        duration hours: Int = 1,
        store: any CalendarEventStore
    ) -> Bool {
        addEvent(title, date: startDate, duration: hours, using: EventsManager(store: store))
    }
}
