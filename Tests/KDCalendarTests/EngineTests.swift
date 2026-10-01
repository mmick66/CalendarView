import Testing
import UIKit

@testable import KDCalendar

/// Edge cases of the date engine: DST, calendars, locales, long events and data source traffic.
@Suite(.serialized)
@MainActor
struct EngineTests: CalendarFixture {

    static let window = makeWindow()
    let retained = Retained()

    init() {
        Self.resetWindow()
    }

    private func calendar(_ zone: String, identifier: Calendar.Identifier = .gregorian, locale: String? = nil)
        -> Calendar
    {
        var calendar = Calendar(identifier: identifier)
        calendar.timeZone = TimeZone(identifier: zone)!
        if let locale { calendar.locale = Locale(identifier: locale) }
        return calendar
    }

    private func date(_ calendar: Calendar, _ year: Int, _ month: Int, _ day: Int, hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    // MARK: Daylight saving time

    @Test func everyDayOfADSTYearRoundTrips() {
        let athens = calendar("Europe/Athens")
        let view = makeCalendar(start: date(athens, 2024, 1, 1), end: date(athens, 2024, 12, 31), calendar: athens)
        var day = date(athens, 2024, 1, 1)
        let last = date(athens, 2024, 12, 31)
        var count = 0
        while day <= last {
            let indexPath = view.indexPathForDate(day)
            #expect(indexPath != nil, "\(day)")
            #expect(view.dateFromIndexPath(indexPath!) == day, "\(day)")
            #expect(view.dateFromIndexPath(indexPath!) == athens.startOfDay(for: day), "\(day)")
            // Any time of that day, including the DST switch hours, lands on the same cell.
            #expect(view.indexPathForDate(day.addingTimeInterval(3 * 3600)) == indexPath, "\(day) + 3h")
            let nextDay = athens.date(byAdding: .day, value: 1, to: day)!
            #expect(view.indexPathForDate(nextDay.addingTimeInterval(-60)) == indexPath, "\(day), last minute")
            day = nextDay
            count += 1
        }
        #expect(count == 366)
        #expect(view.numberOfSections(in: view.collectionView) == 12)
    }

    @Test func aDaySwitchingToDSTAtMidnightStillMatchesStartOfDay() {
        // Chile switches to summer time on 8 September 2024 at 00:00, so that day starts at 01:00.
        let santiago = calendar("America/Santiago")
        let view = makeCalendar(start: date(santiago, 2024, 9, 1), end: date(santiago, 2024, 9, 30), calendar: santiago)
        let switchDay = santiago.startOfDay(for: date(santiago, 2024, 9, 8, hour: 12))
        #expect(santiago.component(.hour, from: switchDay) == 1, "the day really starts at 01:00")
        let indexPath = view.indexPathForDate(switchDay)!
        #expect(view.dateFromIndexPath(indexPath) == switchDay)
        #expect(santiago.component(.day, from: view.dateFromIndexPath(indexPath)!) == 8)
        #expect(view.indexPathForDate(date(santiago, 2024, 9, 9)) == IndexPath(item: indexPath.item + 1, section: 0))
        view.selectDate(date(santiago, 2024, 9, 8, hour: 15))
        #expect(view.selectedDates == [switchDay])
        view.deselectDate(switchDay)
        #expect(view.selectedDates == [])
    }

    @Test func aRangeAcrossASkippedMidnightKeepsItsLastDay() {
        // Adding a day to 8 September 2024 in Santiago lands on 01:00, past the midnight of
        // later days, so a walk that does not return to the start of each day stops short.
        let santiago = calendar("America/Santiago")
        let view = makeCalendar(start: date(santiago, 2024, 9, 1), end: date(santiago, 2024, 9, 30), calendar: santiago)
        let days = (6...10).map { santiago.startOfDay(for: date(santiago, 2024, 9, $0, hour: 12)) }

        view.selectRange(date(santiago, 2024, 9, 6)...date(santiago, 2024, 9, 10))
        #expect(view.selectedDates == days)

        view.clearAllSelectedDates()
        view.selectionMode = .range
        view.selectDate(date(santiago, 2024, 9, 6))
        view.selectDate(date(santiago, 2024, 9, 10))
        #expect(view.selectedDates == days)
    }

    // MARK: Cell content

    @Test func cellContentCoversTheMonthAndItsNeighbours() throws {
        let utc = calendar("UTC")
        // January 2024 starts on a Monday, February on a Thursday (Monday-first: items 0 and 3).
        let grid = try #require(
            MonthGrid(start: date(utc, 2024, 1, 1), end: date(utc, 2024, 2, 29), calendar: utc, firstWeekday: 2))
        #expect(grid.content(at: IndexPath(item: 0, section: 0)) == .day(date(utc, 2024, 1, 1), dayOfMonth: 1))
        #expect(grid.content(at: IndexPath(item: 30, section: 0)) == .day(date(utc, 2024, 1, 31), dayOfMonth: 31))
        #expect(grid.content(at: IndexPath(item: 31, section: 0)) == .trailing(dayOfMonth: 1))
        #expect(grid.content(at: IndexPath(item: 41, section: 0)) == .trailing(dayOfMonth: 11))
        #expect(grid.content(at: IndexPath(item: 0, section: 1)) == .leading(dayOfMonth: 29))
        #expect(grid.content(at: IndexPath(item: 2, section: 1)) == .leading(dayOfMonth: 31))
        #expect(grid.content(at: IndexPath(item: 3, section: 1)) == .day(date(utc, 2024, 2, 1), dayOfMonth: 1))
        #expect(grid.content(at: IndexPath(item: 31, section: 1)) == .day(date(utc, 2024, 2, 29), dayOfMonth: 29))
        #expect(grid.content(at: IndexPath(item: 32, section: 1)) == .trailing(dayOfMonth: 1))
        #expect(grid.content(at: IndexPath(item: 0, section: 2)) == .empty, "outside the grid")
        #expect(grid.date(at: IndexPath(item: 31, section: 0)) == nil)
    }

    @Test func outOfRangeComparesTheCellsDayWithTheRange() throws {
        let utc = calendar("UTC")
        // 15 January to 10 February 2024, Monday first: 15 January is item 14, 10 February item 12.
        let grid = try #require(
            MonthGrid(start: date(utc, 2024, 1, 15), end: date(utc, 2024, 2, 10), calendar: utc, firstWeekday: 2))
        #expect(grid.months.map(\.firstColumn) == [0, 3])
        #expect(grid.months.map(\.dayCount) == [31, 29])
        #expect(grid.firstDayOfMonth(inSection: 1) == date(utc, 2024, 2, 1))
        #expect(grid.firstDayOfMonth(inSection: 2) == nil)
        #expect(grid.isOutOfRange(IndexPath(item: 13, section: 0)))
        #expect(!grid.isOutOfRange(IndexPath(item: 14, section: 0)))
        #expect(!grid.isOutOfRange(IndexPath(item: 12, section: 1)))
        #expect(grid.isOutOfRange(IndexPath(item: 13, section: 1)))
        #expect(grid.isOutOfRange(IndexPath(item: 0, section: 1)), "a cell without a day of its month")
    }

    @Test func theFirstMonthBorrowsItsLeadingDaysFromTheCalendar() throws {
        let utc = calendar("UTC")
        // February 2024 starts on a Thursday: the three cells before it are 29, 30, 31 January.
        let grid = try #require(
            MonthGrid(start: date(utc, 2024, 2, 1), end: date(utc, 2024, 2, 29), calendar: utc, firstWeekday: 2))
        #expect(grid.content(at: IndexPath(item: 0, section: 0)) == .leading(dayOfMonth: 29))
        #expect(grid.content(at: IndexPath(item: 2, section: 0)) == .leading(dayOfMonth: 31))
        #expect(grid.content(at: IndexPath(item: 3, section: 0)) == .day(date(utc, 2024, 2, 1), dayOfMonth: 1))
        #expect(grid.date(at: IndexPath(item: 0, section: 0)) == nil)
        // March 2024 starts on a Friday, after a 29-day February.
        let march = try #require(
            MonthGrid(start: date(utc, 2024, 3, 1), end: date(utc, 2024, 3, 31), calendar: utc, firstWeekday: 2))
        #expect(march.content(at: IndexPath(item: 0, section: 0)) == .leading(dayOfMonth: 26))
        #expect(march.content(at: IndexPath(item: 3, section: 0)) == .leading(dayOfMonth: 29))
    }

    // MARK: Events

    @Test func anEventWithAFarEndDateIsClampedToTheGrid() throws {
        let utc = calendar("UTC")
        let grid = try #require(
            MonthGrid(start: date(utc, 2024, 1, 1), end: date(utc, 2024, 1, 31), calendar: utc, firstWeekday: 2))
        let started = Date()
        let index = EventIndex(
            events: [
                CalendarEvent(title: "forever", startDate: date(utc, 2024, 1, 30), endDate: date(utc, 4000, 1, 1)),
                CalendarEvent(title: "ancient", startDate: date(utc, 1, 1, 1), endDate: date(utc, 2024, 1, 2)),
            ], grid: grid)
        #expect(Date().timeIntervalSince(started) < 1.0, "no per-day loop over the centuries")
        #expect(index[IndexPath(item: 29, section: 0)].map(\.title) == ["forever"])
        #expect(index[IndexPath(item: 30, section: 0)].map(\.title) == ["forever"])
        #expect(index[IndexPath(item: 0, section: 0)].map(\.title) == ["ancient"])
        #expect(index[IndexPath(item: 1, section: 0)].isEmpty)
    }

    @Test func eventsOutsideTheGridAreLeftOut() throws {
        let utc = calendar("UTC")
        let grid = try #require(
            MonthGrid(start: date(utc, 2024, 1, 1), end: date(utc, 2024, 1, 31), calendar: utc, firstWeekday: 2))
        let index = EventIndex(
            events: [
                CalendarEvent(title: "after", startDate: date(utc, 2030, 1, 1), endDate: date(utc, 2031, 1, 1)),
                CalendarEvent(title: "before", startDate: date(utc, 2023, 12, 1), endDate: date(utc, 2023, 12, 31)),
            ], grid: grid)
        #expect(index.isEmpty)
        #expect(EventIndex().isEmpty)
        #expect(EventIndex()[IndexPath(item: 0, section: 0)].isEmpty)
    }

    @Test func anEventIndexCountsEveryEventOnADayInOrder() throws {
        let utc = calendar("UTC")
        let grid = try #require(
            MonthGrid(start: date(utc, 2024, 1, 1), end: date(utc, 2024, 2, 29), calendar: utc, firstWeekday: 2))
        let index = EventIndex(
            events: [
                CalendarEvent(
                    title: "a", startDate: date(utc, 2024, 1, 31, hour: 9), endDate: date(utc, 2024, 2, 1, hour: 10)),
                CalendarEvent(
                    title: "b", startDate: date(utc, 2024, 1, 31, hour: 14), endDate: date(utc, 2024, 2, 2, hour: 10)),
                CalendarEvent(
                    title: "reversed", startDate: date(utc, 2024, 2, 1, hour: 9), endDate: date(utc, 2024, 1, 1)),
            ], grid: grid)
        let lastOfJanuary = try #require(grid.indexPath(for: date(utc, 2024, 1, 31)))
        let firstOfFebruary = try #require(grid.indexPath(for: date(utc, 2024, 2, 1)))
        #expect(index[lastOfJanuary].map(\.title) == ["a", "b"])
        #expect(index.count(at: lastOfJanuary) == 2)
        #expect(firstOfFebruary.section == 1, "an event crosses into the next month's section")
        #expect(index[firstOfFebruary].map(\.title) == ["a", "b", "reversed"], "an end before the start marks one day")
        #expect(index.count(at: try #require(grid.indexPath(for: date(utc, 2024, 2, 2)))) == 1)
        #expect(index.count(at: try #require(grid.indexPath(for: date(utc, 2024, 2, 3)))) == 0)
    }

    @Test func anEventEndingJustAfterASkippedMidnightKeepsItsLastDay() throws {
        // Adding a day to 8 September 2024 in Santiago lands on 01:00, so a walk that does not
        // return to the start of each day reaches the 10th after this event has ended at 00:30.
        let santiago = calendar("America/Santiago")
        let grid = try #require(
            MonthGrid(
                start: date(santiago, 2024, 9, 1), end: date(santiago, 2024, 9, 30), calendar: santiago,
                firstWeekday: 2))
        let index = EventIndex(
            events: [
                CalendarEvent(
                    title: "a", startDate: date(santiago, 2024, 9, 6, hour: 10),
                    endDate: date(santiago, 2024, 9, 10).addingTimeInterval(30 * 60))
            ], grid: grid)
        for day in 6...10 {
            let indexPath = try #require(grid.indexPath(for: date(santiago, 2024, 9, day, hour: 12)))
            #expect(index[indexPath].map(\.title) == ["a"], "day \(day)")
        }
        let after = try #require(grid.indexPath(for: date(santiago, 2024, 9, 11, hour: 12)))
        #expect(index[after].isEmpty)
    }

    @Test func eventsCompareByTitleAndDates() {
        let utc = calendar("UTC")
        let event = CalendarEvent(title: "a", startDate: date(utc, 2024, 1, 1), endDate: date(utc, 2024, 1, 2))
        let same = CalendarEvent(title: "a", startDate: date(utc, 2024, 1, 1), endDate: date(utc, 2024, 1, 2))
        #expect(event == same)
        #expect(event != CalendarEvent(title: "b", startDate: event.startDate, endDate: event.endDate))
        #expect(event != CalendarEvent(title: "a", startDate: event.startDate, endDate: date(utc, 2024, 1, 3)))
        #expect(Set([event, same]).count == 1)
    }

    // MARK: Snapshot

    private func snapshotInputs(
        _ start: Date, _ end: Date, firstWeekday: CalendarView.Style.FirstWeekdayOptions = .monday,
        events: [CalendarEvent] = []
    ) -> CalendarSnapshot.Inputs {
        var style = CalendarView.Style()
        style.calendar = calendar("UTC")
        style.firstWeekday = firstWeekday
        return CalendarSnapshot.Inputs(start: start, end: end, style: style, events: events)
    }

    @Test func aSnapshotBuildsTheGridTodayAndTheEventsFromItsInputs() throws {
        let utc = calendar("UTC")
        let event = CalendarEvent(title: "a", startDate: date(utc, 2024, 2, 1), endDate: date(utc, 2024, 2, 2))
        let snapshot = CalendarSnapshot(
            snapshotInputs(date(utc, 2024, 1, 15), date(utc, 2024, 2, 20), events: [event]),
            now: date(utc, 2024, 1, 31, hour: 12))
        let grid = try #require(snapshot.grid)
        #expect(snapshot.calendar.timeZone == utc.timeZone)
        #expect(grid.numberOfSections == 2)
        #expect(grid.months[0].firstColumn == 0, "January 2024 starts on the Monday column")
        #expect(snapshot.today == grid.indexPath(for: date(utc, 2024, 1, 31)))
        #expect(snapshot.eventIndex[try #require(grid.indexPath(for: date(utc, 2024, 2, 1)))] == [event])
    }

    @Test func snapshotInputsCountOnlyTheDays() {
        let utc = calendar("UTC")
        let morning = snapshotInputs(date(utc, 2024, 1, 15, hour: 9), date(utc, 2024, 2, 20, hour: 9))
        #expect(morning == snapshotInputs(date(utc, 2024, 1, 15, hour: 20), date(utc, 2024, 2, 20, hour: 23)))
        #expect(morning.startDay == date(utc, 2024, 1, 15))
        #expect(morning != snapshotInputs(date(utc, 2024, 1, 16), date(utc, 2024, 2, 20)))
        #expect(morning != snapshotInputs(date(utc, 2024, 1, 15), date(utc, 2024, 2, 20), firstWeekday: .sunday))
        let event = CalendarEvent(title: "a", startDate: date(utc, 2024, 2, 1), endDate: date(utc, 2024, 2, 2))
        #expect(morning != snapshotInputs(date(utc, 2024, 1, 15), date(utc, 2024, 2, 20), events: [event]))
    }

    @Test func aSnapshotReusingThePreviousOneStillFollowsTodayAndTheEvents() throws {
        let utc = calendar("UTC")
        let inputs = snapshotInputs(date(utc, 2024, 1, 15), date(utc, 2024, 2, 20))
        let first = CalendarSnapshot(inputs, now: date(utc, 2024, 1, 20))
        let nextDay = CalendarSnapshot(inputs, now: date(utc, 2024, 1, 21), reusing: first)
        let grid = try #require(nextDay.grid)
        #expect(nextDay.today == grid.indexPath(for: date(utc, 2024, 1, 21)), "today moves on a kept grid")
        #expect(nextDay.today != first.today)

        let event = CalendarEvent(title: "a", startDate: date(utc, 2024, 1, 21), endDate: date(utc, 2024, 1, 21))
        let withEvent = CalendarSnapshot(
            snapshotInputs(date(utc, 2024, 1, 15), date(utc, 2024, 2, 20), events: [event]),
            now: date(utc, 2024, 1, 21), reusing: nextDay)
        #expect(nextDay.eventIndex.isEmpty)
        #expect(withEvent.eventIndex[try #require(withEvent.today)] == [event], "new events rebuild the index")
    }

    @Test func aSnapshotOfAnInvalidRangeHasNoMonths() {
        let utc = calendar("UTC")
        let event = CalendarEvent(title: "a", startDate: date(utc, 2024, 2, 1), endDate: date(utc, 2024, 2, 2))
        let snapshot = CalendarSnapshot(
            snapshotInputs(date(utc, 2024, 3, 10), date(utc, 2024, 1, 15), events: [event]),
            now: date(utc, 2024, 2, 1))
        #expect(snapshot.grid == nil)
        #expect(snapshot.today == nil)
        #expect(snapshot.eventIndex.isEmpty)
    }

    // MARK: Data source traffic

    @Test func theDataSourceIsAskedOncePerReloadNotOncePerCell() {
        let utc = calendar("UTC")
        let view = makeCalendar(start: date(utc, 2024, 1, 1), end: date(utc, 2024, 3, 31), calendar: utc)
        let source = dataSource(of: view)
        source.calls = 0
        view.reloadData()
        view.layoutIfNeeded()
        #expect(source.calls <= 4, "was \(source.calls)")
        source.calls = 0
        view.setDisplayDate(date(utc, 2024, 2, 1))
        view.layoutIfNeeded()
        #expect(source.calls <= 6, "was \(source.calls)")
    }

    // MARK: Locales and calendars

    @Test func weekendsFollowTheStyleLocaleWhenTheCalendarHasNone() {
        // Saudi Arabia's weekend is Friday and Saturday.
        let utc = calendar("UTC")
        let view = makeCalendar(
            start: date(utc, 2024, 1, 1), end: date(utc, 2024, 1, 31), calendar: utc,
            locale: Locale(identifier: "ar_SA"))
        #expect(view.calendar.locale?.identifier == "ar_SA")
        #expect(view.calendar.isDateInWeekend(date(utc, 2024, 1, 5)) == true, "Friday")
        #expect(view.calendar.isDateInWeekend(date(utc, 2024, 1, 7)) == false, "Sunday")
        // January 2024 starts on a Monday: Friday the 5th is item 4, Sunday the 7th item 6.
        #expect(cell(view, IndexPath(item: 4, section: 0))?.configuration.isWeekend == true)
        #expect(cell(view, IndexPath(item: 6, section: 0))?.configuration.isWeekend == false)
        // A calendar that already has a locale keeps it.
        let explicit = makeCalendar(
            start: date(utc, 2024, 1, 1), end: date(utc, 2024, 1, 31), calendar: calendar("UTC", locale: "en_US"),
            locale: Locale(identifier: "ar_SA"))
        #expect(explicit.calendar.locale?.identifier == "en_US")
        #expect(cell(explicit, IndexPath(item: 4, section: 0))?.configuration.isWeekend == false)
    }

    @Test func hebrewLeapYearsHaveThirteenMonths() {
        // 5784 (2023-24) is a leap year with Adar I and Adar II.
        let hebrew = calendar("UTC", identifier: .hebrew)
        let gregorian = calendar("UTC")
        let view = makeCalendar(
            start: date(gregorian, 2023, 9, 16), end: date(gregorian, 2024, 10, 2), calendar: hebrew)
        #expect(view.numberOfSections(in: view.collectionView) == 13)
        var day = date(gregorian, 2023, 9, 16)
        let last = date(gregorian, 2024, 10, 2)
        while day <= last {
            #expect(view.dateFromIndexPath(view.indexPathForDate(day)!) == day, "\(day)")
            day = gregorian.date(byAdding: .day, value: 1, to: day)!
        }
    }

    // MARK: Today

    @Test func theTodayMarkerMovesWhenTheDayChanges() {
        let local = Calendar.current
        let now = Date()
        let view = makeCalendar(
            start: local.date(byAdding: .day, value: -10, to: now)!,
            end: local.date(byAdding: .day, value: 10, to: now)!,
            calendar: local)
        view.setDisplayDate(now)
        view.layoutIfNeeded()
        let today = view.indexPathForDate(now)!
        #expect(cell(view, today)?.configuration.isToday == true)
        // Pretend the marker went stale, as it would across midnight, then announce the day change.
        cell(view, today)?.configuration.isToday = false
        NotificationCenter.default.post(name: .NSCalendarDayChanged, object: nil)
        view.layoutIfNeeded()
        #expect(cell(view, today)?.configuration.isToday == true)
    }
}
