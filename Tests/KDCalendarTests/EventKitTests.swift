import EventKit
import Testing
import UIKit

@testable import KDCalendar
@testable import KDCalendarEventKit

/// The EventKit bridge, driven by a fake store so no calendar access is needed.
///
/// Serialized because every test swaps `EventsManager.store`.
@Suite(.serialized)
@MainActor
struct EventKitTests {

    final class FakeStore: CalendarEventStore {
        var hasFullAccess = false
        var grantsAccess = true
        var requestFails = false
        var requests = 0
        var stored: [CalendarEvent] = []
        var saveFails = false
        var queried: [(Date, Date)] = []

        func requestFullAccess() async throws -> Bool {
            requests += 1
            if requestFails { throw EventsManagerError.authorization }
            hasFullAccess = grantsAccess
            return grantsAccess
        }

        func events(from start: Date, to end: Date) -> [CalendarEvent] {
            queried.append((start, end))
            return stored.filter { $0.startDate < end && $0.endDate >= start }
        }

        func save(_ event: CalendarEvent) throws {
            if saveFails { throw EventsManagerError.authorization }
            stored.append(event)
        }
    }

    final class FixedDataSource: CalendarViewDataSource {
        let start: Date
        let end: Date
        init(start: Date, end: Date) {
            self.start = start
            self.end = end
        }
        func startDate() -> Date { start }
        func endDate() -> Date { end }
    }

    let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    let store = FakeStore()
    let originalStore: any CalendarEventStore

    final class Retained {
        var objects: [AnyObject] = []
    }
    let retained = Retained()

    init() {
        originalStore = EventsManager.store
        EventsManager.store = store
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0) -> Date {
        utc.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func event(_ title: String, _ day: Date, hours: Int = 1) -> CalendarEvent {
        CalendarEvent(title: title, startDate: day, endDate: day.addingTimeInterval(TimeInterval(hours * 3600)))
    }

    private func makeCalendar(start: Date, end: Date) -> CalendarView {
        var style = CalendarView.Style()
        style.calendar = utc
        let view = CalendarView(frame: CGRect(x: 0, y: 0, width: 350, height: 420))
        view.style = style
        let dataSource = FixedDataSource(start: start, end: end)
        retained.objects.append(dataSource)
        view.dataSource = dataSource
        view.layoutIfNeeded()
        return view
    }

    private func restore() {
        EventsManager.store = originalStore
    }

    // MARK: EventsManager

    @Test func loadAsksForAccessOnceAndReturnsTheEvents() async throws {
        defer { restore() }
        store.stored = [event("a", date(2024, 1, 10)), event("b", date(2024, 3, 1))]
        let events = try await EventsManager.load(from: date(2024, 1, 1), to: date(2024, 2, 1))
        #expect(store.requests == 1)
        #expect(events.map(\.title) == ["a"])
        #expect(store.queried.count == 1)
        _ = try await EventsManager.load(from: date(2024, 1, 1), to: date(2024, 2, 1))
        #expect(store.requests == 1, "access is not requested again once granted")
        #expect(EventsManager.hasFullAccess == true)
    }

    @Test func loadThrowsWhenAccessIsDenied() async {
        defer { restore() }
        store.grantsAccess = false
        await #expect(throws: EventsManagerError.authorization) {
            try await EventsManager.load(from: date(2024, 1, 1), to: date(2024, 2, 1))
        }
        #expect(store.queried.isEmpty)
    }

    @Test func loadTreatsARequestFailureAsDenied() async {
        defer { restore() }
        store.requestFails = true
        await #expect(throws: EventsManagerError.authorization) {
            try await EventsManager.load(from: date(2024, 1, 1), to: date(2024, 2, 1))
        }
    }

    @Test func addRequiresAccessAndReportsStoreFailures() {
        defer { restore() }
        let sample = event("dinner", date(2024, 1, 10, hour: 19))
        #expect(EventsManager.add(event: sample) == false)
        #expect(store.stored.isEmpty)
        store.hasFullAccess = true
        #expect(EventsManager.add(event: sample) == true)
        #expect(store.stored.map(\.title) == ["dinner"])
        store.saveFails = true
        #expect(EventsManager.add(event: sample) == false)
        #expect(store.stored.count == 1)
    }

    @Test func aShortIntervalIsQueriedInOneChunk() {
        defer { restore() }
        let chunks = EventsManager.queryIntervals(from: date(2024, 1, 1), to: date(2025, 1, 1))
        #expect(chunks.count == 1)
        #expect(chunks.first?.start == date(2024, 1, 1))
        #expect(chunks.first?.end == date(2025, 1, 1))

        let exact = date(2024, 1, 1).addingTimeInterval(EventsManager.maximumQueryLength)
        #expect(EventsManager.queryIntervals(from: date(2024, 1, 1), to: exact).count == 1)

        let backwards = EventsManager.queryIntervals(from: date(2025, 1, 1), to: date(2024, 1, 1))
        #expect(backwards.count == 1)
        #expect(backwards.first?.start == date(2025, 1, 1))
    }

    @Test func aLongIntervalIsSplitIntoContiguousChunksUnderFourYears() {
        defer { restore() }
        let start = date(2020, 1, 1)
        let end = date(2031, 1, 1)
        let chunks = EventsManager.queryIntervals(from: start, to: end)
        #expect(chunks.count == 3)
        #expect(chunks.first?.start == start)
        #expect(chunks.last?.end == end)
        for (previous, next) in zip(chunks, chunks.dropFirst()) {
            #expect(previous.end == next.start, "no gap or overlap between chunks")
        }
        for chunk in chunks {
            #expect(chunk.end > chunk.start)
            // EventKit's limit is four calendar years; the shortest such span is 1460 days.
            #expect(chunk.end.timeIntervalSince(chunk.start) < 1460 * 24 * 60 * 60)
        }
    }

    // MARK: CalendarView integration

    @Test func loadEventsPassesARangeLongerThanFourYearsWhole() async throws {
        defer { restore() }
        store.hasFullAccess = true
        store.stored = [
            event("early", date(2020, 6, 1)),
            event("late", date(2029, 6, 1)),
        ]
        let view = makeCalendar(start: date(2020, 1, 1), end: date(2030, 12, 31))
        try await view.loadEvents()
        #expect(store.queried.count == 1, "the store, not the manager, splits the range for EventKit")
        #expect(store.queried.first?.0 == date(2020, 1, 1))
        #expect(store.queried.first?.1 == date(2031, 1, 1))
        #expect(view.events.map(\.title) == ["early", "late"])
    }

    @Test func loadEventsCoversTheWholeRangeIncludingTheLastDay() async throws {
        defer { restore() }
        store.hasFullAccess = true
        store.stored = [
            event("first", date(2024, 1, 15, hour: 9)),
            event("last day", date(2024, 3, 10, hour: 18)),
            event("after", date(2024, 3, 11)),
        ]
        let view = makeCalendar(start: date(2024, 1, 15), end: date(2024, 3, 10))
        try await view.loadEvents()
        #expect(view.events.map(\.title) == ["first", "last day"])
        #expect(store.queried.first?.0 == date(2024, 1, 15))
        #expect(store.queried.first?.1 == date(2024, 3, 11), "the query runs to the end of the last day")
        #expect(view.eventsByIndexPath[view.indexPathForDate(date(2024, 3, 10))!]?.count == 1)
    }

    @Test func completionFormReportsSuccessAndDenialOnTheMainActor() async {
        defer { restore() }
        store.stored = [event("a", date(2024, 1, 10))]
        let view = makeCalendar(start: date(2024, 1, 1), end: date(2024, 1, 31))

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

    @Test func addEventSavesForTheGivenDurationAndShowsADot() {
        defer { restore() }
        store.hasFullAccess = true
        let view = makeCalendar(start: date(2024, 1, 1), end: date(2024, 1, 31))
        #expect(view.addEvent("Lunch", date: date(2024, 1, 10, hour: 12), duration: 2) == true)
        #expect(store.stored.first?.startDate == date(2024, 1, 10, hour: 12))
        #expect(store.stored.first?.endDate == date(2024, 1, 10, hour: 14))
        #expect(view.events.map(\.title) == ["Lunch"])
        #expect(view.eventsByIndexPath[IndexPath(item: 9, section: 0)]?.count == 1)

        store.hasFullAccess = false
        #expect(view.addEvent("Nope", date: date(2024, 1, 11)) == false)
        #expect(view.events.count == 1)
    }

    @Test func theDefaultStoreIsTheSystemEventStore() {
        defer { restore() }
        #expect(originalStore is EKEventStore)
    }
}
