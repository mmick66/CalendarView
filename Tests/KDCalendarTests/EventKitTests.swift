import EventKit
import Testing
import UIKit

@testable import KDCalendar
@testable import KDCalendarEventKit

/// The EventKit bridge, driven by a fake store so no calendar access is needed.
@MainActor
struct EventKitTests: CalendarFixture {

    struct StoreError: Error, Equatable {}

    final class FakeStore: CalendarEventStore {
        var hasFullAccess = false
        var grantsAccess = true
        var requestFails = false
        var requests = 0
        var stored: [CalendarEvent] = []
        var saveFails = false
        var queried: [(Date, Date)] = []
        /// Whether queries wait for ``release(_:)`` before returning.
        var holdsQueries = false
        var heldQueries: [CheckedContinuation<Void, Never>] = []

        func requestFullAccess() async throws -> Bool {
            requests += 1
            if requestFails { throw StoreError() }
            hasFullAccess = grantsAccess
            return grantsAccess
        }

        func events(from start: Date, to end: Date) async -> [CalendarEvent] {
            queried.append((start, end))
            let found = stored.filter { $0.startDate < end && $0.endDate >= start }
            if holdsQueries {
                await withCheckedContinuation { heldQueries.append($0) }
            }
            return found
        }

        /// Lets the `index`th held query return.
        func release(_ index: Int) {
            heldQueries[index].resume()
        }

        /// Waits until `count` queries are held.
        func waitForHeldQueries(_ count: Int) async {
            while heldQueries.count < count { await Task.yield() }
        }

        func save(_ event: CalendarEvent) throws {
            if saveFails { throw StoreError() }
            stored.append(event)
        }
    }

    /// Not reset between tests, which run side by side and only need their calendars to have a window.
    static let window = makeWindow()
    var manager: EventsManager { EventsManager(store: store) }
    let retained = Retained()
    let store = FakeStore()

    private func event(_ title: String, _ day: Date, hours: Int = 1) -> CalendarEvent {
        CalendarEvent(title: title, startDate: day, endDate: day.addingTimeInterval(TimeInterval(hours * 3600)))
    }

    /// A shared-fixture calendar whose events go through the fake store.
    private func makeCalendarWithStore(start: Date, end: Date) -> CalendarView {
        let view = makeCalendar(start: start, end: end)
        view.eventsManager = manager
        return view
    }

    // MARK: EventsManager

    @Test func loadAsksForAccessOnceAndReturnsTheEvents() async throws {
        store.stored = [event("a", date(2024, 1, 10)), event("b", date(2024, 3, 1))]
        let events = try await manager.load(from: date(2024, 1, 1), to: date(2024, 2, 1))
        #expect(store.requests == 1)
        #expect(events.map(\.title) == ["a"])
        #expect(store.queried.count == 1)
        _ = try await manager.load(from: date(2024, 1, 1), to: date(2024, 2, 1))
        #expect(store.requests == 1, "access is not requested again once granted")
        #expect(store.hasFullAccess == true)
    }

    @Test func loadThrowsWhenAccessIsDenied() async {
        store.grantsAccess = false
        await #expect(throws: EventsManagerError.authorization) {
            try await manager.load(from: date(2024, 1, 1), to: date(2024, 2, 1))
        }
        #expect(store.queried.isEmpty)
    }

    @Test func loadPassesOnTheErrorOfAFailedRequest() async {
        store.requestFails = true
        await #expect(throws: StoreError()) {
            try await manager.load(from: date(2024, 1, 1), to: date(2024, 2, 1))
        }
    }

    @Test func saveRequiresAccessAndPassesOnStoreFailures() throws {
        let sample = event("dinner", date(2024, 1, 10, hour: 19))
        #expect(throws: EventsManagerError.authorization) {
            try manager.save(sample)
        }
        #expect(store.requests == 0, "saving does not ask for access")
        #expect(store.stored.isEmpty)
        store.hasFullAccess = true
        try manager.save(sample)
        #expect(store.stored.map(\.title) == ["dinner"])
        store.saveFails = true
        #expect(throws: StoreError()) {
            try manager.save(sample)
        }
        #expect(store.stored.count == 1)
    }

    // MARK: Chunking

    @Test func anIntervalThatFitsIsOneChunk() {
        let year = DateInterval(start: date(2024, 1, 1), end: date(2025, 1, 1))
        #expect(year.chunked(maxDuration: .eventKitQueryLimit) == [year])

        let exact = DateInterval(start: date(2024, 1, 1), duration: .eventKitQueryLimit)
        #expect(exact.chunked(maxDuration: .eventKitQueryLimit) == [exact])

        let instant = DateInterval(start: date(2024, 1, 1), duration: 0)
        #expect(instant.chunked(maxDuration: .eventKitQueryLimit) == [instant])
    }

    @Test func aLongIntervalIsSplitIntoContiguousChunks() {
        let interval = DateInterval(start: date(2024, 1, 1), duration: 25)
        #expect(
            interval.chunked(maxDuration: 10) == [
                DateInterval(start: interval.start, duration: 10),
                DateInterval(start: interval.start.addingTimeInterval(10), duration: 10),
                DateInterval(start: interval.start.addingTimeInterval(20), duration: 5),
            ]
        )
    }

    @Test func eventKitChunksAreUnderFourYears() {
        let interval = DateInterval(start: date(2020, 1, 1), end: date(2031, 1, 1))
        let chunks = interval.chunked(maxDuration: .eventKitQueryLimit)
        #expect(chunks.count == 3)
        #expect(chunks.first?.start == interval.start)
        #expect(chunks.last?.end == interval.end)
        for (previous, next) in zip(chunks, chunks.dropFirst()) {
            #expect(previous.end == next.start, "no gap or overlap between chunks")
        }
        for chunk in chunks {
            #expect(chunk.duration > 0)
            // EventKit's limit is four calendar years; the shortest such span is 1460 days.
            #expect(chunk.duration < 1460 * 24 * 60 * 60)
        }
    }

    // MARK: CalendarView integration

    @Test func loadEventsPassesARangeLongerThanFourYearsWhole() async throws {
        store.hasFullAccess = true
        store.stored = [
            event("early", date(2020, 6, 1)),
            event("late", date(2029, 6, 1)),
        ]
        let view = makeCalendarWithStore(start: date(2020, 1, 1), end: date(2030, 12, 31))
        try await view.loadEvents()
        #expect(store.queried.count == 1, "the store, not the manager, splits the range for EventKit")
        #expect(store.queried.first?.0 == date(2020, 1, 1))
        #expect(store.queried.first?.1 == date(2031, 1, 1))
        #expect(view.events.map(\.title) == ["early", "late"])
    }

    @Test func loadEventsCoversTheWholeRangeIncludingTheLastDay() async throws {
        store.hasFullAccess = true
        store.stored = [
            event("first", date(2024, 1, 15, hour: 9)),
            event("last day", date(2024, 3, 10, hour: 18)),
            event("after", date(2024, 3, 11)),
        ]
        let view = makeCalendarWithStore(start: date(2024, 1, 15), end: date(2024, 3, 10))
        try await view.loadEvents()
        #expect(view.events.map(\.title) == ["first", "last day"])
        #expect(store.queried.first?.0 == date(2024, 1, 15))
        #expect(store.queried.first?.1 == date(2024, 3, 11), "the query runs to the end of the last day")
        #expect(view.snapshot.eventIndex.count(at: view.indexPathForDate(date(2024, 3, 10))!) == 1)
    }

    @Test func completionFormReportsSuccessAndDenialOnTheMainActor() async {
        store.stored = [event("a", date(2024, 1, 10))]
        let view = makeCalendarWithStore(start: date(2024, 1, 1), end: date(2024, 1, 31))

        let success: Error? = await withCheckedContinuation { continuation in
            view.loadEvents { error in
                #expect(Thread.isMainThread)
                continuation.resume(returning: error)
            }
        }
        #expect(success == nil)
        #expect(view.events.count == 1)

        store.hasFullAccess = false
        store.grantsAccess = false
        let failure: Error? = await withCheckedContinuation { continuation in
            view.loadEvents { continuation.resume(returning: $0) }
        }
        #expect(failure as? EventsManagerError == .authorization)
        #expect(view.events.count == 1, "a failed load keeps the previous events")
    }

    @Test func theLatestLoadWinsWhenAnEarlierQueryFinishesLast() async throws {
        store.hasFullAccess = true
        store.holdsQueries = true
        store.stored = [event("january", date(2024, 1, 10)), event("march", date(2024, 3, 10))]
        let view = makeCalendarWithStore(start: date(2024, 1, 1), end: date(2024, 1, 31))

        let first = Task { try await view.loadEvents() }
        await store.waitForHeldQueries(1)
        dataSource(of: view).start = date(2024, 3, 1)
        dataSource(of: view).end = date(2024, 3, 31)
        view.reloadData()
        let second = Task { try await view.loadEvents() }
        await store.waitForHeldQueries(2)

        store.release(1)
        try await second.value
        #expect(view.events.map(\.title) == ["march"])

        store.release(0)
        await #expect(throws: CancellationError.self) { try await first.value }
        #expect(view.events.map(\.title) == ["march"], "the superseded load leaves the events alone")
    }

    @Test func completionFormReportsASupersededLoadAsCancelled() async {
        store.hasFullAccess = true
        store.holdsQueries = true
        store.stored = [event("a", date(2024, 1, 10))]
        let view = makeCalendarWithStore(start: date(2024, 1, 1), end: date(2024, 1, 31))

        let first = Task {
            await withCheckedContinuation { continuation in
                view.loadEvents { continuation.resume(returning: $0) }
            }
        }
        await store.waitForHeldQueries(1)
        let second = Task {
            await withCheckedContinuation { continuation in
                view.loadEvents { continuation.resume(returning: $0) }
            }
        }
        await store.waitForHeldQueries(2)
        store.release(0)
        store.release(1)
        #expect(await first.value is CancellationError)
        #expect(await second.value == nil)
        #expect(view.events.map(\.title) == ["a"])
    }

    @Test func addEventSavesForTheGivenDurationAndShowsADot() {
        store.hasFullAccess = true
        let view = makeCalendarWithStore(start: date(2024, 1, 1), end: date(2024, 1, 31))
        #expect(view.addEvent("Lunch", date: date(2024, 1, 10, hour: 12), duration: 2) == true)
        #expect(store.stored.first?.startDate == date(2024, 1, 10, hour: 12))
        #expect(store.stored.first?.endDate == date(2024, 1, 10, hour: 14))
        #expect(view.events.map(\.title) == ["Lunch"])
        #expect(view.snapshot.eventIndex.count(at: IndexPath(item: 9, section: 0)) == 1)

        store.hasFullAccess = false
        #expect(view.addEvent("Nope", date: date(2024, 1, 11)) == false)
        #expect(view.events.count == 1)
    }

    @Test func saveEventSaysWhyTheEventWasNotShown() throws {
        let view = makeCalendarWithStore(start: date(2024, 1, 1), end: date(2024, 1, 31))
        let sample = event("Lunch", date(2024, 1, 10, hour: 12))
        #expect(throws: EventsManagerError.authorization) {
            try view.saveEvent(sample)
        }
        store.hasFullAccess = true
        store.saveFails = true
        #expect(throws: StoreError()) {
            try view.saveEvent(sample)
        }
        #expect(view.events.isEmpty)
        store.saveFails = false
        try view.saveEvent(sample)
        #expect(view.events.map(\.title) == ["Lunch"])
    }

    @Test func aViewUsesTheSharedManagerUntilGivenAnother() {
        let view = CalendarView(frame: .zero)
        #expect(view.eventsManager.store === EventsManager.shared.store)
        view.eventsManager = manager
        #expect(view.eventsManager.store === store)
    }

    @Test func theDeprecatedStoreParametersStillUseTheGivenStore() async throws {
        try await (self as any DeprecatedForms).exerciseDeprecatedForms()
    }

    /// Records the thread each EventKit query runs on, and finds nothing.
    final class ThreadRecordingStore: EKEventStore, @unchecked Sendable {
        nonisolated(unsafe) var queriedOnMainThread: [Bool] = []

        override func events(matching predicate: NSPredicate) -> [EKEvent] {
            queriedOnMainThread.append(Thread.isMainThread)
            return []
        }
    }

    /// Called from the main actor, as ``EventsManager`` calls it.
    ///
    /// Once `NonisolatedNonsendingByDefault` is on, only `@concurrent` keeps the query off it.
    @Test func theSystemStoreQueriesOffTheMainThread() async {
        let systemStore = ThreadRecordingStore()
        let events = await systemStore.events(from: date(2020, 1, 1), to: date(2031, 1, 1))
        #expect(events.isEmpty)
        #expect(
            systemStore.queriedOnMainThread == [false, false, false],
            "one query per chunk, none on the main thread"
        )
    }

    @Test func theSystemStoreFindsNothingInABackwardsInterval() async {
        let systemStore = ThreadRecordingStore()
        let events = await systemStore.events(from: date(2025, 1, 1), to: date(2024, 1, 1))
        #expect(events.isEmpty)
        #expect(systemStore.queriedOnMainThread.isEmpty, "no query is made")
    }
}

/// Calls the 2.1 forms that take a `store` argument.
///
/// Reached through a protocol so that the tests compile without deprecation warnings.
@MainActor
private protocol DeprecatedForms {
    func exerciseDeprecatedForms() async throws
}

extension EventKitTests: DeprecatedForms {
    @available(*, deprecated)
    func exerciseDeprecatedForms() async throws {
        let view = CalendarView(frame: CGRect(x: 0, y: 0, width: 350, height: 420))
        let day = utc.date(from: DateComponents(year: 2024, month: 1, day: 10, hour: 12))!
        let sample = CalendarEvent(title: "Lunch", startDate: day, endDate: day.addingTimeInterval(3600))

        #expect(EventsManager.add(event: sample, store: store) == false)
        #expect(view.addEvent("Nope", date: day, store: store) == false)
        #expect(throws: EventsManagerError.authorization) { try EventsManager.save(sample, store: store) }
        #expect(throws: EventsManagerError.authorization) { try view.saveEvent(sample, store: store) }

        _ = try await EventsManager.load(from: day, to: day, store: store)
        #expect(store.requests == 1, "load asks the given store for access")
        #expect(EventsManager.add(event: sample, store: store) == true)
        #expect(view.addEvent("Dinner", date: day, duration: 2, store: store) == true)
        try view.saveEvent(sample, store: store)
        #expect(store.stored.map(\.title) == ["Lunch", "Dinner", "Lunch"])

        try await view.loadEvents(store: store)
        #expect(store.queried.count == 2)
        let error: Error? = await withCheckedContinuation { continuation in
            view.loadEvents(store: store) { continuation.resume(returning: $0) }
        }
        #expect(error == nil)
        #expect(store.queried.count == 3)
        #expect(view.eventsManager.store === EventsManager.shared.store, "the view keeps its own manager")
    }
}
