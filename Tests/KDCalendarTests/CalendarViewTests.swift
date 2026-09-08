import Testing
import UIKit

@testable import KDCalendar

/// Characterization tests. They pin the behaviour of the 1.8.9 date arithmetic
/// before the modernization touches it. Known bugs are wrapped in
/// `withKnownIssue` so the suite is green while documenting what is wrong.
///
/// Serialized because every test lays its calendar out in a shared window.
@Suite(.serialized)
@MainActor
struct CalendarViewTests {

    /// Fixed-range data source; every test controls its own start and end.
    final class FixedDataSource: CalendarViewDataSource {
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

    final class RecordingDelegate: CalendarViewDelegate {
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

    /// The library's default calendar: Gregorian in UTC. Tests build every
    /// date through it so they do not depend on the machine's time zone.
    let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// One window for the whole suite; each test clears it before adding its calendar.
    static let window: UIWindow = {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 350, height: 500))
        window.isHidden = false
        return window
    }()

    init() {
        Self.window.subviews.forEach { $0.removeFromSuperview() }
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0) -> Date {
        utc.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    /// A laid-out calendar inside the window, so the collection view has real
    /// cells to inspect. The data source and delegate are retained by the
    /// view (strongly, which is finding F2) for the life of the test.
    private func makeCalendar(
        start: Date, end: Date, firstWeekday: CalendarView.Style.FirstWeekdayOptions = .monday
    ) -> CalendarView {
        let style = CalendarView.Style()
        style.firstWeekday = firstWeekday
        style.locale = Locale(identifier: "en_US")
        let view = CalendarView(frame: CGRect(x: 0, y: 0, width: 350, height: 420))
        view.style = style
        view.dataSource = FixedDataSource(start: start, end: end)
        view.delegate = RecordingDelegate()
        Self.window.addSubview(view)
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

    @Test func sectionInfoUsesMondayAsIndexZero() {
        let view = makeCalendar(start: date(2024, 1, 10), end: date(2024, 3, 10))
        // January 2024 starts on a Monday, February on a Thursday, March on a Friday.
        #expect(view.getCachedSectionInfo(0)?.firstDay == 0)
        #expect(view.getCachedSectionInfo(0)?.daysTotal == 31)
        #expect(view.getCachedSectionInfo(1)?.firstDay == 3)
        #expect(view.getCachedSectionInfo(1)?.daysTotal == 29)
        #expect(view.getCachedSectionInfo(2)?.firstDay == 4)
        #expect(view.getCachedSectionInfo(2)?.daysTotal == 31)
    }

    @Test func sectionInfoUsesSundayAsIndexZeroWhenConfigured() {
        let view = makeCalendar(start: date(2024, 1, 10), end: date(2024, 3, 10), firstWeekday: .sunday)
        #expect(view.getCachedSectionInfo(0)?.firstDay == 1)
        #expect(view.getCachedSectionInfo(1)?.firstDay == 4)
        #expect(view.getCachedSectionInfo(2)?.firstDay == 5)
    }

    @Test func numberOfSectionsCoversEveryMonthTouchedByTheRange() {
        let view = makeCalendar(start: date(2024, 1, 15), end: date(2024, 3, 10))
        #expect(view.numberOfSections(in: view.collectionView) == 3)
        #expect(view.startIndexPath == IndexPath(item: 14, section: 0))
        #expect(view.endIndexPath == IndexPath(item: 9, section: 2))
    }

    @Test func singleMonthRangeHasOneSection() {
        let view = makeCalendar(start: date(2024, 9, 15), end: date(2024, 9, 18))
        #expect(view.numberOfSections(in: view.collectionView) == 1)
    }

    @Test func dateRangeSpansTheDataSource() {
        let view = makeCalendar(start: date(2024, 1, 15), end: date(2024, 3, 10))
        #expect(view.dateRange == date(2024, 1, 15)...date(2024, 3, 10))
    }

    @Test func everyDayInRangeRoundTripsThroughAnIndexPath() {
        let view = makeCalendar(start: date(2024, 1, 15), end: date(2024, 3, 10))
        var day = date(2024, 1, 1)
        let last = date(2024, 3, 31)
        while day <= last {
            let indexPath = view.indexPathForDate(day)
            #expect(indexPath != nil, "\(day)")
            #expect(view.dateFromIndexPath(indexPath!) == day, "\(day)")
            day = utc.date(byAdding: .day, value: 1, to: day)!
        }
    }

    @Test func indexPathForDateIgnoresTheTimeOfDay() {
        let view = makeCalendar(start: date(2024, 1, 15), end: date(2024, 3, 10))
        #expect(view.indexPathForDate(date(2024, 2, 10)) == view.indexPathForDate(date(2024, 2, 10, hour: 23)))
        // February 2024 starts on Thursday (index 3), so the 10th sits at item 12.
        #expect(view.indexPathForDate(date(2024, 2, 10)) == IndexPath(item: 12, section: 1))
    }

    // MARK: Cell configuration

    @Test func cellsOutsideTheMonthAreHidden() {
        let view = makeCalendar(start: date(2024, 2, 1), end: date(2024, 2, 29))
        // February 2024: Thursday first, so items 0...2 and 32...41 are not days.
        #expect(cell(view, IndexPath(item: 0, section: 0))?.isHidden == true)
        #expect(cell(view, IndexPath(item: 2, section: 0))?.isHidden == true)
        #expect(cell(view, IndexPath(item: 3, section: 0))?.isHidden == false)
        #expect(cell(view, IndexPath(item: 3, section: 0))?.day == 1)
        #expect(cell(view, IndexPath(item: 31, section: 0))?.day == 29)
        #expect(cell(view, IndexPath(item: 32, section: 0))?.isHidden == true)
    }

    @Test func outOfRangeFlagsRespectBothEndsInsideASingleMonth() {
        // Issue #131: 15 to 18 September 2024, one section, both edges apply.
        let view = makeCalendar(start: date(2024, 9, 15), end: date(2024, 9, 18))
        // September 2024 starts on a Sunday: Monday-first index 6.
        func flag(_ day: Int) -> Bool? { cell(view, IndexPath(item: 6 + day - 1, section: 0))?.isOutOfRange }
        #expect(flag(14) == true)
        #expect(flag(15) == false)
        #expect(flag(18) == false)
        #expect(flag(19) == true)
    }

    @Test func outOfRangeFlagsAcrossMonths() {
        let view = makeCalendar(start: date(2024, 1, 15), end: date(2024, 3, 10))
        #expect(cell(view, IndexPath(item: 13, section: 0))?.isOutOfRange == true)  // 14 January
        #expect(cell(view, IndexPath(item: 14, section: 0))?.isOutOfRange == false)  // 15 January
        view.setDisplayDate(date(2024, 3, 1))
        view.layoutIfNeeded()
        // March 2024 starts on a Friday (index 4): the 10th is item 13, the 11th item 14.
        #expect(cell(view, IndexPath(item: 13, section: 2))?.isOutOfRange == false)
        #expect(cell(view, IndexPath(item: 14, section: 2))?.isOutOfRange == true)
    }

    @Test func weekendFlagsFollowTheFirstWeekday() {
        let monday = makeCalendar(start: date(2024, 1, 1), end: date(2024, 1, 31))
        #expect(cell(monday, IndexPath(item: 4, section: 0))?.isWeekend == false)  // Friday 5th
        #expect(cell(monday, IndexPath(item: 5, section: 0))?.isWeekend == true)  // Saturday 6th
        #expect(cell(monday, IndexPath(item: 6, section: 0))?.isWeekend == true)  // Sunday 7th

        let sunday = makeCalendar(start: date(2024, 1, 1), end: date(2024, 1, 31), firstWeekday: .sunday)
        #expect(cell(sunday, IndexPath(item: 7, section: 0))?.isWeekend == true)  // Sunday 7th
        #expect(cell(sunday, IndexPath(item: 8, section: 0))?.isWeekend == false)  // Monday 8th
        #expect(cell(sunday, IndexPath(item: 13, section: 0))?.isWeekend == true)  // Saturday 13th
    }

    @Test func eventsAreBucketedByStartDay() {
        let view = makeCalendar(start: date(2024, 1, 1), end: date(2024, 1, 31))
        view.events = [
            CalendarEvent(title: "a", startDate: date(2024, 1, 10, hour: 9), endDate: date(2024, 1, 10, hour: 10)),
            CalendarEvent(title: "b", startDate: date(2024, 1, 10, hour: 14), endDate: date(2024, 1, 12, hour: 10)),
            CalendarEvent(title: "c", startDate: date(2024, 2, 1), endDate: date(2024, 2, 2)),
        ]
        #expect(view.eventsByIndexPath[IndexPath(item: 9, section: 0)]?.count == 2)
        #expect(view.eventsByIndexPath[IndexPath(item: 10, section: 0)] == nil)
        #expect(view.eventsByIndexPath[IndexPath(item: 11, section: 0)] == nil)
    }

    // MARK: Header and display date

    @Test func headerShowsMonthAndYearInTheStyleLocale() {
        let view = makeCalendar(start: date(2024, 1, 15), end: date(2024, 3, 10))
        view.setDisplayDate(date(2024, 2, 10))
        #expect(view.headerView.monthLabel.text == "February 2024")
        #expect(view.displayDate == date(2024, 2, 10))
    }

    @Test func headerStringFromTheDataSourceWins() {
        let view = makeCalendar(start: date(2024, 1, 15), end: date(2024, 3, 10))
        (view.dataSource as! FixedDataSource).header = "Custom"
        view.setDisplayDate(date(2024, 2, 10))
        #expect(view.headerView.monthLabel.text == "Custom")
    }

    @Test func setDisplayDateOutsideTheRangeIsIgnored() {
        let view = makeCalendar(start: date(2024, 1, 15), end: date(2024, 3, 10))
        view.setDisplayDate(date(2024, 2, 10))
        view.setDisplayDate(date(2024, 6, 1))
        #expect(view.displayDate == date(2024, 2, 10))
    }

    @Test func weekdayLabelsStartOnTheConfiguredDay() {
        let monday = makeCalendar(start: date(2024, 1, 1), end: date(2024, 1, 31))
        #expect(monday.headerView.dayLabels.map(\.text) == ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"])
        let sunday = makeCalendar(start: date(2024, 1, 1), end: date(2024, 1, 31), firstWeekday: .sunday)
        #expect(sunday.headerView.dayLabels.map(\.text) == ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"])
    }

    // MARK: Selection

    @Test func selectDateRecordsTheDateAndNotifiesTheDelegate() {
        let view = makeCalendar(start: date(2024, 1, 1), end: date(2024, 1, 31))
        view.selectDate(date(2024, 1, 10))
        #expect(view.selectedDates == [date(2024, 1, 10)])
        #expect(view.selectedIndexPaths == [IndexPath(item: 9, section: 0)])
        #expect(delegate(of: view).selected == [date(2024, 1, 10)])
    }

    @Test func deselectDateRemovesTheDateAndNotifiesTheDelegate() {
        let view = makeCalendar(start: date(2024, 1, 1), end: date(2024, 1, 31))
        view.selectDate(date(2024, 1, 10))
        view.deselectDate(date(2024, 1, 10))
        #expect(view.selectedDates == [])
        #expect(delegate(of: view).deselected == [date(2024, 1, 10)])
    }

    @Test func singleSelectionReplacesThePreviousDate() {
        let view = makeCalendar(start: date(2024, 1, 1), end: date(2024, 1, 31))
        view.multipleSelectionEnable = false
        view.selectDate(date(2024, 1, 10))
        view.layoutIfNeeded()
        view.selectDate(date(2024, 1, 12))
        #expect(view.selectedDates == [date(2024, 1, 12)])
    }

    @Test func multipleSelectionAccumulates() {
        let view = makeCalendar(start: date(2024, 1, 1), end: date(2024, 1, 31))
        view.selectDate(date(2024, 1, 10))
        view.selectDate(date(2024, 1, 12))
        #expect(view.selectedDates == [date(2024, 1, 10), date(2024, 1, 12)])
    }

    @Test func clearAllSelectedDatesDoesNotNotify() {
        let view = makeCalendar(start: date(2024, 1, 1), end: date(2024, 1, 31))
        view.selectDate(date(2024, 1, 10))
        view.clearAllSelectedDates()
        #expect(view.selectedDates == [])
        #expect(delegate(of: view).deselected == [])
    }

    @Test func outOfRangeVisibleCellsAreNotSelectable() {
        let view = makeCalendar(start: date(2024, 1, 15), end: date(2024, 3, 10))
        view.selectDate(date(2024, 1, 5))
        #expect(view.selectedDates == [])
        #expect(delegate(of: view).selected == [])
    }

    // MARK: Pinned bugs (known issues until phase 3)

    @Test func deselectingADateThatIsNotSelectedShouldDoNothing() {
        let view = makeCalendar(start: date(2024, 1, 1), end: date(2024, 1, 31))
        withKnownIssue("deselectDate routes through didSelectItemAt and selects the date instead") {
            view.deselectDate(date(2024, 1, 10))
            #expect(view.selectedDates == [])
        }
    }

    @Test func programmaticSelectionOfAHiddenCellShouldHonourSingleSelection() {
        let view = makeCalendar(start: date(2024, 1, 15), end: date(2024, 3, 10))
        view.multipleSelectionEnable = false
        view.selectDate(date(2024, 1, 20))
        withKnownIssue("a date on a non-visible page bypasses multipleSelectionEnable and the delegate") {
            view.selectDate(date(2024, 3, 5))
            #expect(view.selectedDates == [date(2024, 3, 5)])
            #expect(delegate(of: view).selected == [date(2024, 1, 20), date(2024, 3, 5)])
        }
    }

    @Test func singleSelectionShouldNotDependOnALayoutPassBetweenCalls() {
        let view = makeCalendar(start: date(2024, 1, 1), end: date(2024, 1, 31))
        view.multipleSelectionEnable = false
        view.selectDate(date(2024, 1, 10))
        withKnownIssue("reloadData after a selection leaves no visible cell, so the next selectDate accumulates") {
            view.selectDate(date(2024, 1, 12))
            #expect(view.selectedDates == [date(2024, 1, 12)])
        }
    }

    @Test func eachCalendarShouldOwnItsStyle() {
        let a = CalendarView(frame: .zero)
        let b = CalendarView(frame: .zero)
        withKnownIssue("Style is a class and Style.Default is shared by every calendar") {
            #expect(a.style !== b.style)
        }
    }

    @Test func reusedCellShouldNotKeepTheTodayFlag() {
        let view = makeCalendar(start: date(2024, 1, 15), end: date(2024, 3, 10))
        let reused = cell(view, IndexPath(item: 20, section: 0))!
        reused.isToday = true
        withKnownIssue("cellForItemAt returns early for out-of-range cells without resetting isToday") {
            reused.prepareForReuse()
            _ = view.collectionView(view.collectionView, cellForItemAt: IndexPath(item: 2, section: 0))
            #expect(reused.isToday == false)
        }
    }

    @Test func didScrollToMonthShouldFireOncePerSettledPage() {
        let view = makeCalendar(start: date(2024, 1, 15), end: date(2024, 3, 10))
        withKnownIssue("cellForItemAt(0,0) fires didScrollToMonth for month zero on every reload") {
            view.reloadData()
            view.layoutIfNeeded()
            #expect(delegate(of: view).scrolledTo == [])
        }
    }

    @Test func enableDeselectionFalseShouldNotReportADeselection() {
        let view = makeCalendar(start: date(2024, 1, 1), end: date(2024, 1, 31))
        view.enableDeselection = false
        view.selectDate(date(2024, 1, 10))
        withKnownIssue("didDeselectDate is sent before enableDeselection is checked") {
            view.deselectDate(date(2024, 1, 10))
            #expect(view.selectedDates == [date(2024, 1, 10)])
            #expect(delegate(of: view).deselected == [])
        }
    }
}
