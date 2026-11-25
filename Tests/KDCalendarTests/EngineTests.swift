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

    // MARK: A month without a first midnight

    /// Expects every day in the range of `grid` to have its own cell, in order, showing the start
    /// of that day, and the range to hold `days` of them.
    private func expectEveryDayRoundTrips(
        _ grid: MonthGrid, days: Int, sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let calendar = grid.calendar
        // Noon exists on every day of these zones, and adding days keeps it.
        let firstNoon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: grid.startDay)!
        var previous: IndexPath?
        var count = 0
        while let noon = calendar.date(byAdding: .day, value: count, to: firstNoon),
            calendar.startOfDay(for: noon) <= grid.endDay
        {
            let day = calendar.startOfDay(for: noon)
            count += 1
            guard let indexPath = grid.indexPath(for: noon) else {
                Issue.record("no cell for \(noon)", sourceLocation: sourceLocation)
                continue
            }
            #expect(grid.indexPath(for: day) == indexPath, "\(noon)", sourceLocation: sourceLocation)
            #expect(
                grid.content(at: indexPath) == .day(day, dayOfMonth: calendar.component(.day, from: noon)),
                "\(noon)", sourceLocation: sourceLocation)
            #expect(grid.date(at: indexPath) == day, "\(noon)", sourceLocation: sourceLocation)
            #expect(!grid.isOutOfRange(indexPath), "\(noon)", sourceLocation: sourceLocation)
            if let previous {
                #expect(previous < indexPath, "\(noon) follows the day before", sourceLocation: sourceLocation)
            }
            previous = indexPath
        }
        #expect(count == days, sourceLocation: sourceLocation)
        #expect(previous == grid.indexPath(for: grid.endDay), sourceLocation: sourceLocation)
    }

    @Test func aGridStartingAfterASkippedMidnightKeepsEveryDayInItsMonth() throws {
        // Paraguay moved to summer time on 1 October 2023 at 00:00, so that month starts at 01:00.
        let asuncion = calendar("America/Asuncion")
        let october = asuncion.startOfDay(for: date(asuncion, 2023, 10, 1, hour: 12))
        #expect(asuncion.component(.hour, from: october) == 1, "the month really starts at 01:00")
        let grid = try #require(
            MonthGrid(start: october, end: date(asuncion, 2023, 12, 31), calendar: asuncion, firstWeekday: 2))
        #expect(grid.months.map(\.firstDate) == [october, date(asuncion, 2023, 11, 1), date(asuncion, 2023, 12, 1)])
        #expect(grid.months.map(\.firstColumn) == [6, 2, 4], "a Sunday, a Wednesday and a Friday")
        #expect(grid.indexPath(for: date(asuncion, 2023, 10, 15)) == IndexPath(item: 20, section: 0))
        #expect(grid.indexPath(for: date(asuncion, 2023, 11, 15)) == IndexPath(item: 16, section: 1))
        #expect(grid.indexPath(for: date(asuncion, 2023, 12, 31)) == IndexPath(item: 34, section: 2))
        #expect(grid.date(at: IndexPath(item: 16, section: 1)) == date(asuncion, 2023, 11, 15))
        #expect(!grid.isOutOfRange(IndexPath(item: 34, section: 2)), "the last day of the range")
        #expect(grid.indexPath(for: date(asuncion, 2023, 9, 30, hour: 23)) == nil, "the day before the grid")
        #expect(grid.indexPath(for: date(asuncion, 2024, 1, 1)) == nil, "the day after the grid")
        expectEveryDayRoundTrips(grid, days: 92)
    }

    @Test func aMonthStartingAfterASkippedMidnightHandsOutTheStartOfEachDay() throws {
        // October 2023 sits in the middle: its first day starts at 01:00 and the others at 00:00.
        let asuncion = calendar("America/Asuncion")
        let grid = try #require(
            MonthGrid(
                start: date(asuncion, 2023, 9, 1), end: date(asuncion, 2023, 11, 30), calendar: asuncion,
                firstWeekday: 2))
        let fifteenth = try #require(grid.indexPath(for: date(asuncion, 2023, 10, 15, hour: 12)))
        #expect(grid.date(at: fifteenth) == date(asuncion, 2023, 10, 15))
        #expect(grid.firstDayOfMonth(inSection: 1) == asuncion.startOfDay(for: date(asuncion, 2023, 10, 1, hour: 12)))
        expectEveryDayRoundTrips(grid, days: 91)
        // Two years with both changes of each: forward at 00:00 in October, back at 00:00 in March.
        let years = try #require(
            MonthGrid(
                start: date(asuncion, 2022, 1, 1), end: date(asuncion, 2023, 12, 31), calendar: asuncion,
                firstWeekday: 1))
        expectEveryDayRoundTrips(years, days: 730)
    }

    @Test func selectionWorksInAGridStartingAfterASkippedMidnight() {
        let asuncion = calendar("America/Asuncion")
        let view = makeCalendar(
            start: date(asuncion, 2023, 10, 1, hour: 12), end: date(asuncion, 2023, 12, 31), calendar: asuncion)
        view.selectDate(date(asuncion, 2023, 11, 15, hour: 9))
        #expect(view.selectedDates == [date(asuncion, 2023, 11, 15)], "not 15 October")
        view.selectDate(date(asuncion, 2023, 12, 31, hour: 9))
        #expect(view.selectedDates.last == date(asuncion, 2023, 12, 31), "the last day is in range")
        #expect(view.selectedIndexPaths == [IndexPath(item: 16, section: 1), IndexPath(item: 34, section: 2)])
        #expect(view.dateRange.upperBound == date(asuncion, 2023, 12, 31))
    }

    @Test func selectionWorksInAMonthStartingAfterASkippedMidnight() {
        let asuncion = calendar("America/Asuncion")
        let view = makeCalendar(
            start: date(asuncion, 2023, 9, 1), end: date(asuncion, 2023, 11, 30), calendar: asuncion)
        let fifteenth = date(asuncion, 2023, 10, 15)
        view.selectDate(date(asuncion, 2023, 10, 15, hour: 15))
        #expect(view.selectedDates == [fifteenth], "the start of the day, not 01:00")
        view.clearAllSelectedDates()
        view.setSelection([fifteenth])
        #expect(view.selectedDates == [fifteenth])
        view.selectRange(date(asuncion, 2023, 9, 29)...date(asuncion, 2023, 10, 2))
        #expect(
            view.selectedDates
                == [29, 30].map { date(asuncion, 2023, 9, $0) }
                + [1, 2].map { asuncion.startOfDay(for: date(asuncion, 2023, 10, $0, hour: 12)) })
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

    @Test func anEventEndingAtMidnightLeavesThatDayUnmarked() throws {
        let utc = calendar("UTC")
        let grid = try #require(
            MonthGrid(start: date(utc, 2024, 1, 1), end: date(utc, 2024, 2, 29), calendar: utc, firstWeekday: 2))
        let index = EventIndex(
            events: [
                CalendarEvent(
                    title: "evening", startDate: date(utc, 2024, 1, 10, hour: 22), endDate: date(utc, 2024, 1, 11)),
                CalendarEvent(
                    title: "month", startDate: date(utc, 2024, 1, 30, hour: 22), endDate: date(utc, 2024, 2, 1)),
                CalendarEvent(title: "no length", startDate: date(utc, 2024, 1, 20), endDate: date(utc, 2024, 1, 20)),
                CalendarEvent(
                    title: "a second", startDate: date(utc, 2024, 1, 24, hour: 22),
                    endDate: date(utc, 2024, 1, 25).addingTimeInterval(1)),
            ], grid: grid)
        func titles(_ month: Int, _ day: Int) throws -> [String] {
            index[try #require(grid.indexPath(for: date(utc, 2024, month, day)))].map(\.title)
        }
        #expect(try titles(1, 10) == ["evening"])
        #expect(try titles(1, 11) == [], "the event ended as the day started")
        #expect(try titles(1, 30) == ["month"])
        #expect(try titles(1, 31) == ["month"])
        #expect(try titles(2, 1) == [], "in the next month too")
        #expect(try titles(1, 19) == [])
        #expect(try titles(1, 20) == ["no length"], "the day an event begins on is always marked")
        #expect(try titles(1, 21) == [])
        #expect(try titles(1, 25) == ["a second"])
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

    /// The events on each cell, found the straightforward way: one question to the calendar per
    /// event and day.
    ///
    /// It marks what ``EventIndex`` marks today, the first day of the grid for an event that ends
    /// at its first midnight included (CalendarView-4qn.19).
    private func eventsDayByDay(_ events: [CalendarEvent], in grid: MonthGrid) -> [IndexPath: [CalendarEvent]] {
        let calendar = grid.calendar
        let gridStart = grid.months[0].firstDate
        let gridEnd = calendar.dateInterval(of: .month, for: grid.months[grid.months.count - 1].firstDate)!.end
        var result: [IndexPath: [CalendarEvent]] = [:]
        for event in events {
            let eventEnd = max(event.startDate, event.endDate)
            guard event.startDate < gridEnd, eventEnd >= gridStart else { continue }
            var day = calendar.startOfDay(for: max(event.startDate, gridStart))
            let last = min(eventEnd, gridEnd)
            repeat {
                if let indexPath = grid.indexPath(for: day) {
                    result[indexPath, default: []].append(event)
                }
                day = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: day)!)
            } while day < last
        }
        return result
    }

    /// Events around every edge of `grid`, and `count` more at made-up times, the same on every run.
    private func eventsAroundTheEdges(of grid: MonthGrid, count: Int) -> [CalendarEvent] {
        let calendar = grid.calendar
        let gridStart = grid.months[0].firstDate
        let gridEnd = calendar.dateInterval(of: .month, for: grid.months[grid.months.count - 1].firstDate)!.end
        let span = gridEnd.timeIntervalSince(gridStart)
        let middle = calendar.startOfDay(for: gridStart + span / 2)
        let day: TimeInterval = 86_400
        var intervals: [(Date, Date)] = [
            (gridStart - 40 * day, gridEnd + 40 * day),  // everything
            (gridStart - 3 * day, gridStart),  // ends at the first midnight
            (gridStart - 3 * day, gridStart + 1),
            (gridStart - 3 * day, gridStart - 1),  // just outside
            (gridStart, gridStart),  // no length, at the first midnight
            (middle, middle),  // no length, at a midnight
            (middle - 3 * day, middle),  // ends at a midnight
            (middle - 3 * day, middle + 0.5),  // and half a second after it
            (middle + 3600, middle + 7200),
            (middle + day, middle - 2 * day),  // the end before the start
            (middle, gridEnd),  // ends at the last midnight
            (middle, gridEnd - 1),
            (gridEnd - 3600, gridEnd + 3 * day),  // starts in the last hour
            (gridEnd, gridEnd + day),  // just outside
            (gridEnd - day, gridEnd - day),
        ]
        // A linear congruential generator, so the events are the same on every run.
        var state: UInt64 = 0x2545_F491_4F6C_DD1D
        func random(_ bound: Double) -> Double {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(state >> 11) / Double(1 << 53) * bound
        }
        for number in 0..<count {
            var start = gridStart - 40 * day + random(span + 80 * day)
            let length = random([0, 600, 5 * 3600, 30 * 3600, 9 * day, 100 * day][number % 6])
            if number % 4 == 1 { start = calendar.startOfDay(for: start) }
            var end = start + length
            if number % 4 == 2 { end = calendar.startOfDay(for: end) }
            intervals.append((start, end))
        }
        return intervals.enumerated().map {
            CalendarEvent(title: "\($0.offset)", startDate: $0.element.0, endDate: $0.element.1)
        }
    }

    @Test func longEventsMarkTheDaysADayByDayWalkMarks() throws {
        let santiago = calendar("America/Santiago")
        let asuncion = calendar("America/Asuncion")
        let athens = calendar("Europe/Athens")
        let hebrew = calendar("UTC", identifier: .hebrew)
        let grids = [
            // Midnights skipped in the middle of a month, in both years.
            MonthGrid(
                start: date(santiago, 2024, 1, 1), end: date(santiago, 2025, 12, 31), calendar: santiago,
                firstWeekday: 2),
            // A month that starts at 01:00, and a day of 25 hours in March.
            MonthGrid(
                start: date(asuncion, 2023, 9, 10), end: date(asuncion, 2024, 4, 20), calendar: asuncion,
                firstWeekday: 1),
            MonthGrid(
                start: date(athens, 2024, 2, 10), end: date(athens, 2024, 11, 5), calendar: athens, firstWeekday: 7),
            // Thirteen months, of 29 and 30 days.
            MonthGrid(
                start: date(athens, 2023, 9, 16), end: date(athens, 2024, 10, 2), calendar: hebrew, firstWeekday: 1),
            // One month.
            MonthGrid(
                start: date(athens, 2024, 2, 10), end: date(athens, 2024, 2, 10), calendar: athens, firstWeekday: 2),
        ]
        for grid in grids {
            let grid = try #require(grid)
            let zone = grid.calendar.timeZone.identifier
            let events = eventsAroundTheEdges(of: grid, count: 240)
            let index = EventIndex(events: events, grid: grid)
            let expected = eventsDayByDay(events, in: grid)
            #expect(!expected.isEmpty)
            #expect(!index.isEmpty)
            for section in 0..<grid.numberOfSections {
                for item in 0..<MonthGrid.cellsPerMonth {
                    let indexPath = IndexPath(item: item, section: section)
                    let titles = index[indexPath].map(\.title)
                    #expect(titles == (expected[indexPath] ?? []).map(\.title), "\(zone) \(indexPath)")
                    #expect(index.count(at: indexPath) == titles.count, "\(zone) \(indexPath)")
                }
            }
            #expect(index[IndexPath(item: 0, section: grid.numberOfSections)].isEmpty, "outside the grid")
        }
    }

    @Test func eventsSpanningACenturyAreIndexedWithoutAskingTheCalendarForEveryDay() throws {
        let utc = calendar("UTC")
        let grid = try #require(
            MonthGrid(start: date(utc, 2000, 1, 1), end: date(utc, 2099, 12, 31), calendar: utc, firstWeekday: 2))
        let events = (0..<20).map {
            CalendarEvent(
                title: "\($0)", startDate: date(utc, 2000, 1, 1 + $0, hour: 9),
                endDate: date(utc, 2099, 12, 31 - $0, hour: 9))
        }
        var index = EventIndex()
        let elapsed = ContinuousClock().measure { index = EventIndex(events: events, grid: grid) }
        // About 730,000 event days: a question to the calendar for each took more than seven seconds.
        #expect(elapsed < .milliseconds(500), "took \(elapsed)")
        #expect(index.count(at: try #require(grid.indexPath(for: date(utc, 2000, 1, 1)))) == 1)
        #expect(index[try #require(grid.indexPath(for: date(utc, 2000, 1, 3)))].map(\.title) == ["0", "1", "2"])
        #expect(index.count(at: try #require(grid.indexPath(for: date(utc, 2050, 6, 15)))) == 20)
        #expect(index.count(at: try #require(grid.indexPath(for: date(utc, 2099, 12, 30)))) == 2)
        #expect(index.count(at: try #require(grid.indexPath(for: date(utc, 2099, 12, 31)))) == 1)
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

    // MARK: Fixed calendars

    /// Moves the device to `zone`, as far as this process can tell.
    ///
    /// `TimeZone.autoupdatingCurrent` follows the system's zone, which `NSTimeZone.default` does not
    /// change. Returns the way back.
    private func moveDevice(to zone: String) -> () -> Void {
        let previous = ProcessInfo.processInfo.environment["TZ"]
        setenv("TZ", zone, 1)
        NSTimeZone.resetSystemTimeZone()
        return {
            if let previous { setenv("TZ", previous, 1) } else { unsetenv("TZ") }
            NSTimeZone.resetSystemTimeZone()
        }
    }

    @Test func aFixedCalendarKeepsTheTimeZoneAndTheLocaleItHasNow() {
        var custom = Calendar(identifier: .buddhist)
        custom.timeZone = .autoupdatingCurrent
        custom.locale = .autoupdatingCurrent
        custom.firstWeekday = 5
        custom.minimumDaysInFirstWeek = 6
        let fixed = custom.fixed
        #expect(fixed.timeZone != .autoupdatingCurrent)
        #expect(fixed.timeZone.identifier == TimeZone.autoupdatingCurrent.identifier)
        #expect(fixed.locale != .autoupdatingCurrent)
        #expect(fixed.locale?.identifier == Locale.autoupdatingCurrent.identifier)
        #expect(fixed.identifier == .buddhist)
        #expect(fixed.firstWeekday == 5)
        #expect(fixed.minimumDaysInFirstWeek == 6)
        #expect(custom.fixed == fixed, "the same settings make the same calendar")

        let athens = calendar("Europe/Athens", locale: "el_GR")
        #expect(athens.fixed == athens, "a calendar with settings of its own is left alone")
        #expect(Calendar.autoupdatingCurrent.fixed != Calendar.autoupdatingCurrent)
        #expect(Calendar.autoupdatingCurrent.fixed.timeZone == Calendar.autoupdatingCurrent.timeZone)
    }

    @Test func aCalendarInTheDevicesTimeZoneShowsAMoveAsNewInputs() {
        let moveBack = moveDevice(to: "America/Phoenix")
        defer { moveBack() }
        var custom = Calendar(identifier: .gregorian)
        custom.timeZone = .autoupdatingCurrent
        #expect(custom.timeZone.identifier == "America/Phoenix", "the calendar follows the device")
        var style = CalendarView.Style()
        style.calendar = custom
        // Phoenix and Denver share their winter midnights, so the range covers the same days in
        // both and only the calendar can say that the grid is stale.
        let phoenix = calendar("America/Phoenix")
        let start = date(phoenix, 2024, 1, 1)
        let end = date(phoenix, 2024, 12, 31)
        let before = CalendarSnapshot.Inputs(start: start, end: end, style: style, events: [])
        #expect(before == CalendarSnapshot.Inputs(start: start, end: end, style: style, events: []))

        _ = moveDevice(to: "America/Denver")
        let after = CalendarSnapshot.Inputs(start: start, end: end, style: style, events: [])
        #expect(after.startDay == before.startDay)
        #expect(after.endDay == before.endDay)
        #expect(after != before)
        #expect(before.calendar.timeZone.identifier == "America/Phoenix", "fixed inputs stay where they were")
        #expect(after.calendar.timeZone.identifier == "America/Denver")
    }

    @Test func aViewWithACalendarInTheDevicesTimeZoneFollowsAMove() {
        let moveBack = moveDevice(to: "America/Phoenix")
        defer { moveBack() }
        var custom = Calendar(identifier: .gregorian)
        custom.timeZone = .autoupdatingCurrent
        let phoenix = calendar("America/Phoenix")
        let denver = calendar("America/Denver")
        let view = makeCalendar(start: date(phoenix, 2024, 1, 1), end: date(phoenix, 2024, 12, 31), calendar: custom)
        view.selectDate(date(phoenix, 2024, 7, 4, hour: 12))
        #expect(view.selectedDates == [date(phoenix, 2024, 7, 4)])

        // The device moves, but the view has not heard of it yet: its dates stay those of its grid.
        _ = moveDevice(to: "America/Denver")
        #expect(view.layoutCalendar.timeZone.identifier == "America/Phoenix")
        #expect(view.snapshot.grid?.calendar.startOfDay(for: date(denver, 2024, 7, 4)) == date(phoenix, 2024, 7, 3))

        // The reload the significant time change notification brings, for this view alone.
        view.reloadData()
        #expect(view.layoutCalendar.timeZone.identifier == "America/Denver")
        #expect(view.snapshot.grid?.firstDayOfMonth(inSection: 6) == date(denver, 2024, 7, 1))
        #expect(view.selectedDates == [date(denver, 2024, 7, 4)], "the same day, at midnight in the new zone")
        #expect(view.selectedIndexPaths == [view.indexPathForDate(date(denver, 2024, 7, 4))!])
    }

    // MARK: Delegate traffic

    @Test func theDelegateIsAskedOncePerDayWhetherItCanBeSelected() {
        let view = makeCalendar(start: date(2024, 1, 1), end: date(2024, 1, 31))
        var asked: [Date] = []
        delegate(of: view).canSelect = {
            asked.append($0)
            return true
        }
        view.selectDate(date(2024, 1, 10, hour: 15))
        #expect(asked == [date(2024, 1, 10)])

        asked = []
        let tapped = view.indexPathForDate(date(2024, 1, 11))!
        #expect(view.collectionView(view.collectionView, shouldSelectItemAt: tapped))
        view.collectionView(view.collectionView, didSelectItemAt: tapped)
        #expect(asked == [date(2024, 1, 11)])
        #expect(delegate(of: view).selected == [date(2024, 1, 10), date(2024, 1, 11)])

        asked = []
        view.deselectDate(date(2024, 1, 10, hour: 15))
        view.selectDate(date(2024, 2, 1))
        view.selectDate(date(2023, 12, 31))
        #expect(asked == [], "deselecting asks nothing, and neither does a day outside the range")
        #expect(view.selectedDates == [date(2024, 1, 11)])

        view.setSelection([date(2024, 1, 3), date(2024, 1, 5)])
        #expect(asked == [date(2024, 1, 3), date(2024, 1, 5)])

        // The second end of a range is asked about as a tap, then with every day of the range.
        view.selectionMode = .range
        asked = []
        view.selectDate(date(2024, 1, 8))
        #expect(asked == [date(2024, 1, 8)])
        asked = []
        view.selectDate(date(2024, 1, 12))
        #expect(asked == [date(2024, 1, 12)] + (8...12).map { date(2024, 1, $0) })
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

    @Test func aChineseLeapMonthKeepsEveryDayInOrder() throws {
        // The Chinese year that began in January 2023 has a leap second month, so thirteen months.
        let chinese = calendar("Asia/Shanghai", identifier: .chinese)
        let gregorian = calendar("Asia/Shanghai")
        let grid = try #require(
            MonthGrid(
                start: date(gregorian, 2023, 1, 22), end: date(gregorian, 2024, 2, 9), calendar: chinese,
                firstWeekday: 2))
        #expect(grid.numberOfSections == 13)
        #expect(grid.months.map(\.firstDate) == grid.months.map { chinese.startOfDay(for: $0.firstDate) })
        expectEveryDayRoundTrips(grid, days: 384)
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
