import Testing
import UIKit

@testable import KDCalendar

/// Edge cases of the date engine: DST, calendars, locales, long events and data source traffic.
@Suite(.serialized)
@MainActor
struct EngineTests {

    final class CountingDataSource: CalendarViewDataSource {
        var start: Date
        var end: Date
        var calls = 0
        init(start: Date, end: Date) {
            self.start = start
            self.end = end
        }
        func startDate() -> Date {
            calls += 1
            return start
        }
        func endDate() -> Date {
            calls += 1
            return end
        }
    }

    static let window: UIWindow = {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 350, height: 500))
        window.isHidden = false
        return window
    }()

    final class Retained {
        var objects: [AnyObject] = []
    }
    let retained = Retained()

    init() {
        Self.window.subviews.forEach { $0.removeFromSuperview() }
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

    private func makeCalendar(start: Date, end: Date, calendar: Calendar, locale: String = "en_US") -> CalendarView {
        var style = CalendarView.Style()
        style.locale = Locale(identifier: locale)
        style.calendar = calendar
        let view = CalendarView(frame: CGRect(x: 0, y: 0, width: 350, height: 420))
        view.style = style
        let dataSource = CountingDataSource(start: start, end: end)
        retained.objects.append(dataSource)
        view.dataSource = dataSource
        Self.window.addSubview(view)
        view.layoutIfNeeded()
        return view
    }

    private func cell(_ view: CalendarView, _ indexPath: IndexPath) -> CalendarDayCell? {
        view.collectionView.cellForItem(at: indexPath) as? CalendarDayCell
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

    @Test func anEventWithAFarEndDateIsClampedToTheGrid() {
        let utc = calendar("UTC")
        let view = makeCalendar(start: date(utc, 2024, 1, 1), end: date(utc, 2024, 1, 31), calendar: utc)
        let started = Date()
        view.events = [
            CalendarEvent(title: "forever", startDate: date(utc, 2024, 1, 30), endDate: date(utc, 4000, 1, 1)),
            CalendarEvent(title: "ancient", startDate: date(utc, 1, 1, 1), endDate: date(utc, 2024, 1, 2)),
            CalendarEvent(title: "elsewhere", startDate: date(utc, 2030, 1, 1), endDate: date(utc, 2031, 1, 1)),
        ]
        #expect(Date().timeIntervalSince(started) < 1.0, "no per-day loop over the centuries")
        #expect(view.eventsByIndexPath[IndexPath(item: 29, section: 0)]?.map(\.title) == ["forever"])
        #expect(view.eventsByIndexPath[IndexPath(item: 30, section: 0)]?.map(\.title) == ["forever"])
        #expect(view.eventsByIndexPath[IndexPath(item: 0, section: 0)]?.map(\.title) == ["ancient"])
        #expect(view.eventsByIndexPath[IndexPath(item: 1, section: 0)] == nil)
        #expect(view.eventsByIndexPath.values.flatMap { $0 }.filter { $0.title == "elsewhere" }.isEmpty)
    }

    // MARK: Data source traffic

    @Test func theDataSourceIsAskedOncePerReloadNotOncePerCell() {
        let utc = calendar("UTC")
        let view = makeCalendar(start: date(utc, 2024, 1, 1), end: date(utc, 2024, 3, 31), calendar: utc)
        let source = view.dataSource as! CountingDataSource
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
            start: date(utc, 2024, 1, 1), end: date(utc, 2024, 1, 31), calendar: utc, locale: "ar_SA")
        #expect(view.calendar.locale?.identifier == "ar_SA")
        #expect(view.calendar.isDateInWeekend(date(utc, 2024, 1, 5)) == true, "Friday")
        #expect(view.calendar.isDateInWeekend(date(utc, 2024, 1, 7)) == false, "Sunday")
        // January 2024 starts on a Monday: Friday the 5th is item 4, Sunday the 7th item 6.
        #expect(cell(view, IndexPath(item: 4, section: 0))?.configuration.isWeekend == true)
        #expect(cell(view, IndexPath(item: 6, section: 0))?.configuration.isWeekend == false)
        // A calendar that already has a locale keeps it.
        let explicit = makeCalendar(
            start: date(utc, 2024, 1, 1), end: date(utc, 2024, 1, 31), calendar: calendar("UTC", locale: "en_US"),
            locale: "ar_SA")
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
