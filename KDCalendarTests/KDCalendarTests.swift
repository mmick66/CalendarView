//
//  KDCalendarTests.swift
//  KDCalendarTests
//
//  Characterization tests. They pin the behaviour of the 1.8.9 date arithmetic
//  before the modernization touches it. Known bugs are marked with
//  XCTExpectFailure so the suite is green while documenting what is wrong.
//

import UIKit
import XCTest

@testable import CalendarView

/// Fixed-range data source; every test controls its own start and end.
private final class FixedDataSource: CalendarViewDataSource {
    var start: Date
    var end: Date
    var header: String?
    init(start: Date, end: Date) {
        self.start = start
        self.end = end
    }
    func startDate() -> Date { start }
    func endDate() -> Date { end }
    func headerString(_ date: Date) -> String? { header }
}

private final class RecordingDelegate: CalendarViewDelegate {
    var scrolledTo: [Date] = []
    var selected: [Date] = []
    var deselected: [Date] = []
    var canSelect: (Date) -> Bool = { _ in true }

    func calendar(_ calendar: CalendarView, didScrollToMonth date: Date) { scrolledTo.append(date) }
    func calendar(_ calendar: CalendarView, didSelectDate date: Date, withEvents events: [CalendarEvent]) {
        selected.append(date)
    }
    func calendar(_ calendar: CalendarView, canSelectDate date: Date) -> Bool { canSelect(date) }
    func calendar(_ calendar: CalendarView, didDeselectDate date: Date) { deselected.append(date) }
    func calendar(_ calendar: CalendarView, didLongPressDate date: Date, withEvents events: [CalendarEvent]?) {}
}

final class KDCalendarTests: XCTestCase {

    /// The library's default calendar: Gregorian in UTC. Tests build every
    /// date through it so they do not depend on the machine's time zone.
    private let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private var window: UIWindow!
    private var dataSources: [FixedDataSource] = []
    private var delegates: [RecordingDelegate] = []

    override func setUp() {
        super.setUp()
        window = UIWindow(frame: CGRect(x: 0, y: 0, width: 350, height: 500))
        window.isHidden = false
    }

    override func tearDown() {
        window.isHidden = true
        window = nil
        dataSources.removeAll()
        delegates.removeAll()
        super.tearDown()
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0) -> Date {
        utc.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    /// A laid-out calendar inside a window, so the collection view has real
    /// cells to inspect.
    private func makeCalendar(
        start: Date, end: Date, firstWeekday: CalendarView.Style.FirstWeekdayOptions = .monday
    ) -> CalendarView {
        let style = CalendarView.Style()
        style.firstWeekday = firstWeekday
        style.locale = Locale(identifier: "en_US")
        let view = CalendarView(frame: CGRect(x: 0, y: 0, width: 350, height: 420))
        view.style = style
        let source = FixedDataSource(start: start, end: end)
        dataSources.append(source)
        view.dataSource = source
        let delegate = RecordingDelegate()
        delegates.append(delegate)
        view.delegate = delegate
        window.addSubview(view)
        view.layoutIfNeeded()
        return view
    }

    private func delegate(of view: CalendarView) -> RecordingDelegate {
        view.delegate as! RecordingDelegate
    }

    private func cell(_ view: CalendarView, _ indexPath: IndexPath) -> CalendarDayCell? {
        view.collectionView.cellForItem(at: indexPath) as? CalendarDayCell
    }

    // MARK: Section arithmetic

    func testSectionInfoUsesMondayAsIndexZero() {
        let view = makeCalendar(start: date(2024, 1, 10), end: date(2024, 3, 10))
        // January 2024 starts on a Monday, February on a Thursday, March on a Friday.
        XCTAssertEqual(view.getCachedSectionInfo(0)?.firstDay, 0)
        XCTAssertEqual(view.getCachedSectionInfo(0)?.daysTotal, 31)
        XCTAssertEqual(view.getCachedSectionInfo(1)?.firstDay, 3)
        XCTAssertEqual(view.getCachedSectionInfo(1)?.daysTotal, 29)
        XCTAssertEqual(view.getCachedSectionInfo(2)?.firstDay, 4)
        XCTAssertEqual(view.getCachedSectionInfo(2)?.daysTotal, 31)
    }

    func testSectionInfoUsesSundayAsIndexZeroWhenConfigured() {
        let view = makeCalendar(start: date(2024, 1, 10), end: date(2024, 3, 10), firstWeekday: .sunday)
        XCTAssertEqual(view.getCachedSectionInfo(0)?.firstDay, 1)
        XCTAssertEqual(view.getCachedSectionInfo(1)?.firstDay, 4)
        XCTAssertEqual(view.getCachedSectionInfo(2)?.firstDay, 5)
    }

    func testNumberOfSectionsCoversEveryMonthTouchedByTheRange() {
        let view = makeCalendar(start: date(2024, 1, 15), end: date(2024, 3, 10))
        XCTAssertEqual(view.numberOfSections(in: view.collectionView), 3)
        XCTAssertEqual(view.startIndexPath, IndexPath(item: 14, section: 0))
        XCTAssertEqual(view.endIndexPath, IndexPath(item: 9, section: 2))
    }

    func testSingleMonthRangeHasOneSection() {
        let view = makeCalendar(start: date(2024, 9, 15), end: date(2024, 9, 18))
        XCTAssertEqual(view.numberOfSections(in: view.collectionView), 1)
    }

    func testEveryDayInRangeRoundTripsThroughAnIndexPath() {
        let view = makeCalendar(start: date(2024, 1, 15), end: date(2024, 3, 10))
        var day = date(2024, 1, 1)
        let last = date(2024, 3, 31)
        while day <= last {
            let indexPath = view.indexPathForDate(day)
            XCTAssertNotNil(indexPath, "\(day)")
            XCTAssertEqual(view.dateFromIndexPath(indexPath!), day, "\(day)")
            day = utc.date(byAdding: .day, value: 1, to: day)!
        }
    }

    func testIndexPathForDateIgnoresTheTimeOfDay() {
        let view = makeCalendar(start: date(2024, 1, 15), end: date(2024, 3, 10))
        XCTAssertEqual(view.indexPathForDate(date(2024, 2, 10)), view.indexPathForDate(date(2024, 2, 10, hour: 23)))
        // February 2024 starts on Thursday (index 3), so the 10th sits at item 12.
        XCTAssertEqual(view.indexPathForDate(date(2024, 2, 10)), IndexPath(item: 12, section: 1))
    }

    // MARK: Cell configuration

    func testCellsOutsideTheMonthAreHidden() {
        let view = makeCalendar(start: date(2024, 2, 1), end: date(2024, 2, 29))
        // February 2024: Thursday first, so items 0...2 and 32...41 are not days.
        XCTAssertEqual(cell(view, IndexPath(item: 0, section: 0))?.isHidden, true)
        XCTAssertEqual(cell(view, IndexPath(item: 2, section: 0))?.isHidden, true)
        XCTAssertEqual(cell(view, IndexPath(item: 3, section: 0))?.isHidden, false)
        XCTAssertEqual(cell(view, IndexPath(item: 3, section: 0))?.day, 1)
        XCTAssertEqual(cell(view, IndexPath(item: 31, section: 0))?.day, 29)
        XCTAssertEqual(cell(view, IndexPath(item: 32, section: 0))?.isHidden, true)
    }

    func testOutOfRangeFlagsRespectBothEndsInsideASingleMonth() {
        // Issue #131: 15 to 18 September 2024, one section, both edges apply.
        let view = makeCalendar(start: date(2024, 9, 15), end: date(2024, 9, 18))
        // September 2024 starts on a Sunday: Monday-first index 6.
        func flag(_ day: Int) -> Bool? { cell(view, IndexPath(item: 6 + day - 1, section: 0))?.isOutOfRange }
        XCTAssertEqual(flag(14), true)
        XCTAssertEqual(flag(15), false)
        XCTAssertEqual(flag(18), false)
        XCTAssertEqual(flag(19), true)
    }

    func testOutOfRangeFlagsAcrossMonths() {
        let view = makeCalendar(start: date(2024, 1, 15), end: date(2024, 3, 10))
        XCTAssertEqual(cell(view, IndexPath(item: 13, section: 0))?.isOutOfRange, true)  // 14 January
        XCTAssertEqual(cell(view, IndexPath(item: 14, section: 0))?.isOutOfRange, false)  // 15 January
        view.setDisplayDate(date(2024, 3, 1))
        view.layoutIfNeeded()
        // March 2024 starts on a Friday (index 4): the 10th is item 13, the 11th item 14.
        XCTAssertEqual(cell(view, IndexPath(item: 13, section: 2))?.isOutOfRange, false)
        XCTAssertEqual(cell(view, IndexPath(item: 14, section: 2))?.isOutOfRange, true)
    }

    func testWeekendFlagsFollowTheFirstWeekday() {
        let monday = makeCalendar(start: date(2024, 1, 1), end: date(2024, 1, 31))
        XCTAssertEqual(cell(monday, IndexPath(item: 4, section: 0))?.isWeekend, false)  // Friday 5th
        XCTAssertEqual(cell(monday, IndexPath(item: 5, section: 0))?.isWeekend, true)  // Saturday 6th
        XCTAssertEqual(cell(monday, IndexPath(item: 6, section: 0))?.isWeekend, true)  // Sunday 7th

        let sunday = makeCalendar(start: date(2024, 1, 1), end: date(2024, 1, 31), firstWeekday: .sunday)
        XCTAssertEqual(cell(sunday, IndexPath(item: 7, section: 0))?.isWeekend, true)  // Sunday 7th
        XCTAssertEqual(cell(sunday, IndexPath(item: 8, section: 0))?.isWeekend, false)  // Monday 8th
        XCTAssertEqual(cell(sunday, IndexPath(item: 13, section: 0))?.isWeekend, true)  // Saturday 13th
    }

    func testEventsAreBucketedByStartDay() {
        let view = makeCalendar(start: date(2024, 1, 1), end: date(2024, 1, 31))
        view.events = [
            CalendarEvent(title: "a", startDate: date(2024, 1, 10, hour: 9), endDate: date(2024, 1, 10, hour: 10)),
            CalendarEvent(title: "b", startDate: date(2024, 1, 10, hour: 14), endDate: date(2024, 1, 12, hour: 10)),
            CalendarEvent(title: "c", startDate: date(2024, 2, 1), endDate: date(2024, 2, 2)),
        ]
        XCTAssertEqual(view.eventsByIndexPath[IndexPath(item: 9, section: 0)]?.count, 2)
        XCTAssertNil(view.eventsByIndexPath[IndexPath(item: 10, section: 0)])
        XCTAssertNil(view.eventsByIndexPath[IndexPath(item: 11, section: 0)])
    }

    // MARK: Header and display date

    func testHeaderShowsMonthAndYearInTheStyleLocale() {
        let view = makeCalendar(start: date(2024, 1, 15), end: date(2024, 3, 10))
        view.setDisplayDate(date(2024, 2, 10))
        XCTAssertEqual(view.headerView.monthLabel.text, "February 2024")
        XCTAssertEqual(view.displayDate, date(2024, 2, 10))
    }

    func testHeaderStringFromTheDataSourceWins() {
        let view = makeCalendar(start: date(2024, 1, 15), end: date(2024, 3, 10))
        (view.dataSource as! FixedDataSource).header = "Custom"
        view.setDisplayDate(date(2024, 2, 10))
        XCTAssertEqual(view.headerView.monthLabel.text, "Custom")
    }

    func testSetDisplayDateOutsideTheRangeIsIgnored() {
        let view = makeCalendar(start: date(2024, 1, 15), end: date(2024, 3, 10))
        view.setDisplayDate(date(2024, 2, 10))
        view.setDisplayDate(date(2024, 6, 1))
        XCTAssertEqual(view.displayDate, date(2024, 2, 10))
    }

    func testWeekdayLabelsStartOnTheConfiguredDay() {
        let monday = makeCalendar(start: date(2024, 1, 1), end: date(2024, 1, 31))
        XCTAssertEqual(monday.headerView.dayLabels.map(\.text), ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"])
        let sunday = makeCalendar(start: date(2024, 1, 1), end: date(2024, 1, 31), firstWeekday: .sunday)
        XCTAssertEqual(sunday.headerView.dayLabels.map(\.text), ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"])
    }

    // MARK: Selection

    func testSelectDateRecordsTheDateAndNotifiesTheDelegate() {
        let view = makeCalendar(start: date(2024, 1, 1), end: date(2024, 1, 31))
        view.selectDate(date(2024, 1, 10))
        XCTAssertEqual(view.selectedDates, [date(2024, 1, 10)])
        XCTAssertEqual(view.selectedIndexPaths, [IndexPath(item: 9, section: 0)])
        XCTAssertEqual(delegate(of: view).selected, [date(2024, 1, 10)])
    }

    func testDeselectDateRemovesTheDateAndNotifiesTheDelegate() {
        let view = makeCalendar(start: date(2024, 1, 1), end: date(2024, 1, 31))
        view.selectDate(date(2024, 1, 10))
        view.deselectDate(date(2024, 1, 10))
        XCTAssertEqual(view.selectedDates, [])
        XCTAssertEqual(delegate(of: view).deselected, [date(2024, 1, 10)])
    }

    func testSingleSelectionReplacesThePreviousDate() {
        let view = makeCalendar(start: date(2024, 1, 1), end: date(2024, 1, 31))
        view.multipleSelectionEnable = false
        view.selectDate(date(2024, 1, 10))
        view.layoutIfNeeded()
        view.selectDate(date(2024, 1, 12))
        XCTAssertEqual(view.selectedDates, [date(2024, 1, 12)])
    }

    func testMultipleSelectionAccumulates() {
        let view = makeCalendar(start: date(2024, 1, 1), end: date(2024, 1, 31))
        view.selectDate(date(2024, 1, 10))
        view.selectDate(date(2024, 1, 12))
        XCTAssertEqual(view.selectedDates, [date(2024, 1, 10), date(2024, 1, 12)])
    }

    func testClearAllSelectedDatesDoesNotNotify() {
        let view = makeCalendar(start: date(2024, 1, 1), end: date(2024, 1, 31))
        view.selectDate(date(2024, 1, 10))
        view.clearAllSelectedDates()
        XCTAssertEqual(view.selectedDates, [])
        XCTAssertEqual(delegate(of: view).deselected, [])
    }

    func testOutOfRangeVisibleCellsAreNotSelectable() {
        let view = makeCalendar(start: date(2024, 1, 15), end: date(2024, 3, 10))
        view.selectDate(date(2024, 1, 5))
        XCTAssertEqual(view.selectedDates, [])
        XCTAssertEqual(delegate(of: view).selected, [])
    }

    // MARK: Pinned bugs (expected failures until phase 3)

    func testDeselectingADateThatIsNotSelectedShouldDoNothing() {
        let view = makeCalendar(start: date(2024, 1, 1), end: date(2024, 1, 31))
        XCTExpectFailure("deselectDate routes through didSelectItemAt and selects the date instead") {
            view.deselectDate(date(2024, 1, 10))
            XCTAssertEqual(view.selectedDates, [])
        }
    }

    func testProgrammaticSelectionOfAHiddenCellShouldHonourSingleSelection() {
        let view = makeCalendar(start: date(2024, 1, 15), end: date(2024, 3, 10))
        view.multipleSelectionEnable = false
        view.selectDate(date(2024, 1, 20))
        XCTExpectFailure("a date on a non-visible page bypasses multipleSelectionEnable and the delegate") {
            view.selectDate(date(2024, 3, 5))
            XCTAssertEqual(view.selectedDates, [date(2024, 3, 5)])
            XCTAssertEqual(delegate(of: view).selected, [date(2024, 1, 20), date(2024, 3, 5)])
        }
    }

    func testSingleSelectionShouldNotDependOnALayoutPassBetweenCalls() {
        let view = makeCalendar(start: date(2024, 1, 1), end: date(2024, 1, 31))
        view.multipleSelectionEnable = false
        view.selectDate(date(2024, 1, 10))
        XCTExpectFailure("reloadData after a selection leaves no visible cell, so the next selectDate accumulates") {
            view.selectDate(date(2024, 1, 12))
            XCTAssertEqual(view.selectedDates, [date(2024, 1, 12)])
        }
    }

    func testEachCalendarShouldOwnItsStyle() {
        let a = CalendarView(frame: .zero)
        let b = CalendarView(frame: .zero)
        XCTExpectFailure("Style is a class and Style.Default is shared by every calendar") {
            XCTAssertFalse(a.style === b.style)
        }
    }

    func testReusedCellShouldNotKeepTheTodayFlag() {
        let view = makeCalendar(start: date(2024, 1, 15), end: date(2024, 3, 10))
        let reused = cell(view, IndexPath(item: 20, section: 0))!
        reused.isToday = true
        XCTExpectFailure("cellForItemAt returns early for out-of-range cells without resetting isToday") {
            reused.prepareForReuse()
            let configured = view.collectionView(view.collectionView, cellForItemAt: IndexPath(item: 2, section: 0))
            XCTAssertNotEqual(configured, reused, "no reuse pool is expected in a fresh layout; the flag is the point")
            _ = configured
            XCTAssertFalse(reused.isToday)
        }
    }

    func testDidScrollToMonthShouldFireOncePerSettledPage() {
        let view = makeCalendar(start: date(2024, 1, 15), end: date(2024, 3, 10))
        XCTExpectFailure("cellForItemAt(0,0) fires didScrollToMonth for month zero on every reload") {
            view.reloadData()
            view.layoutIfNeeded()
            XCTAssertEqual(delegate(of: view).scrolledTo, [])
        }
    }

    func testEnableDeselectionFalseShouldNotReportADeselection() {
        let view = makeCalendar(start: date(2024, 1, 1), end: date(2024, 1, 31))
        view.enableDeselection = false
        view.selectDate(date(2024, 1, 10))
        XCTExpectFailure("didDeselectDate is sent before enableDeselection is checked") {
            view.deselectDate(date(2024, 1, 10))
            XCTAssertEqual(view.selectedDates, [date(2024, 1, 10)])
            XCTAssertEqual(delegate(of: view).deselected, [])
        }
    }
}
