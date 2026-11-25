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
    /// The notification the store posts, with itself as the object, each time its events change,
    /// or `nil` when it posts none.
    ///
    /// A calendar view whose `reloadsEventsWhenStoreChanges` is `true` observes it to keep its
    /// events current. The store may post it on any thread. The default implementation returns
    /// `nil`; `EKEventStore` returns `EKEventStoreChanged`.
    var changeNotification: Notification.Name? { get }
}

extension CalendarEventStore {
    /// No notification: the store does not report its changes.
    public var changeNotification: Notification.Name? { nil }
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

    /// `EKEventStoreChanged`, which EventKit posts when the calendar database changes.
    ///
    /// EventKit posts it for the changes made in other apps, and may post it for the events this
    /// app saves as well.
    public var changeNotification: Notification.Name? {
        .EKEventStoreChanged
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

@MainActor private var eventsLoaderKey: UInt8 = 0

extension CalendarView {

    /// The manager that ``loadEvents()``, ``saveEvent(_:)`` and ``addEvent(_:date:duration:)`` use;
    /// ``EventsManager/shared`` by default.
    ///
    /// Assign a manager around another ``CalendarEventStore`` to test without calendar access.
    public var eventsManager: EventsManager {
        get { eventsLoader.manager ?? .shared }
        set { eventsLoader.manager = newValue }
    }

    /// Whether the view loads its events again when the store they came from reports a change;
    /// `false` by default.
    ///
    /// Set it to `true` to keep the events current while the user edits their calendar in another
    /// app. From its latest successful ``loadEvents()`` on, the view observes the
    /// ``CalendarEventStore/changeNotification`` of the store that load read, and answers a change
    /// as ``loadEvents()`` would: with the events of the same store over the data source's range
    /// at that moment, which replace `events`.
    ///
    /// - The view waits a moment before it loads, and changes reported during the wait or while a
    ///   load runs are answered together, so a burst of changes starts one query, not one each.
    /// - A change reported while a load the app started is running waits for it to finish and
    ///   never supersedes it; a load the app starts supersedes one that answers a change.
    /// - The view does not ask for access on a change. Without full access `events` stay as they
    ///   are, and ``loadEvents()`` says why.
    /// - A store whose ``CalendarEventStore/changeNotification`` is `nil` reports nothing, and the
    ///   property has no effect.
    ///
    /// The view stops observing when the property is set to `false` and when the view goes away.
    public var reloadsEventsWhenStoreChanges: Bool {
        get { eventsLoader.reloadsWhenStoreChanges }
        set { eventsLoader.reloadsWhenStoreChanges = newValue }
    }

    /// Loads the events from the system calendar that fall inside the data source's range and
    /// assigns them to `events`.
    ///
    /// Asks for full calendar access if it has not been granted yet; the app must declare
    /// `NSCalendarsFullAccessUsageDescription`.
    ///
    /// A load supersedes any load still running, so the last call wins however long each query
    /// takes: a superseded load leaves `events` alone and throws `CancellationError`. Events
    /// saved with ``saveEvent(_:)`` while the load runs stay in `events`, whether or not its query
    /// found them.
    ///
    /// - Throws: ``EventsManagerError/authorization`` when access is denied, the error the
    ///   store threw while asking for it, or `CancellationError` when a later load started
    ///   before this one finished.
    public func loadEvents() async throws {
        try await loadEvents(using: eventsManager)
    }

    /// Completion-handler form of ``loadEvents()``.
    ///
    /// The handler runs once, on the main actor, with `nil` on success or the error
    /// ``loadEvents()`` threw, which is `CancellationError` when a later load superseded this one.
    /// The load starts after the call returns and does not keep the view alive until then: when the
    /// view is gone before it starts, the handler gets `CancellationError`.
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

    /// The view's manager and the state of its loads, made when first needed.
    ///
    /// The one object the bridge associates with the view, which releases it when it goes away.
    var eventsLoader: EventsLoader {
        if let loader = objc_getAssociatedObject(self, &eventsLoaderKey) as? EventsLoader { return loader }
        let loader = EventsLoader(host: self)
        objc_setAssociatedObject(self, &eventsLoaderKey, loader, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return loader
    }

    private func loadEvents(using manager: EventsManager) async throws {
        try await eventsLoader.load(using: manager)
    }

    private func loadEvents(using manager: EventsManager, onComplete: (@MainActor (_ error: Error?) -> Void)?) {
        Task { [weak self] in
            do {
                // The handler is owed a call even when there is no view left to load for.
                guard let self else { throw CancellationError() }
                try await loadEvents(using: manager)
                onComplete?(nil)
            } catch {
                onComplete?(error)
            }
        }
    }

    private func saveEvent(_ event: CalendarEvent, using manager: EventsManager) throws {
        try eventsLoader.save(event, using: manager)
    }

    private func addEvent(
        _ title: String,
        date startDate: Date,
        duration hours: Int,
        using manager: EventsManager
    ) -> Bool {
        guard let endDate = calendar.date(byAdding: .hour, value: hours, to: startDate) else {
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
