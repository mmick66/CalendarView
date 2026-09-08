import Testing
import UIKit

@testable import KDCalendar

/// Behavioural tests for the month grid, cell configuration, header, scrolling and selection.
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

    /// A Gregorian calendar in UTC. Tests build every date through it so they do not depend
    /// on the machine's time zone.
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

    /// The view holds its data source and delegate weakly, so each test keeps them here.
    final class Retained {
        var objects: [AnyObject] = []
    }
    let retained = Retained()

    init() {
        Self.window.subviews.forEach { $0.removeFromSuperview() }
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0) -> Date {
        utc.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    /// A laid-out calendar inside the window, so the collection view has real
    /// cells to inspect.
    private func makeCalendar(
        start: Date, end: Date, firstWeekday: CalendarView.Style.FirstWeekdayOptions = .monday,
        calendar: Calendar? = nil, locale: Locale = Locale(identifier: "en_US")
    ) -> CalendarView {
        var style = CalendarView.Style()
        style.firstWeekday = firstWeekday
        style.locale = locale
        style.calendar = calendar ?? utc
        let view = CalendarView(frame: CGRect(x: 0, y: 0, width: 350, height: 420))
        view.style = style
        let dataSource = FixedDataSource(start: start, end: end)
        let delegate = RecordingDelegate()
        retained.objects.append(dataSource)
        retained.objects.append(delegate)
        view.dataSource = dataSource
        view.delegate = delegate
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
        #expect(view.getCachedSectionInfo(3) == nil)
    }

    @Test func sectionInfoUsesSundayAsIndexZeroWhenConfigured() {
        let view = makeCalendar(start: date(2024, 1, 10), end: date(2024, 3, 10), firstWeekday: .sunday)
        #expect(view.getCachedSectionInfo(0)?.firstDay == 1)
        #expect(view.getCachedSectionInfo(1)?.firstDay == 4)
        #expect(view.getCachedSectionInfo(2)?.firstDay == 5)
    }

    @Test func sectionInfoSupportsSaturdayAndTheCalendarsOwnFirstWeekday() {
        let saturday = makeCalendar(start: date(2024, 1, 10), end: date(2024, 1, 20), firstWeekday: .saturday)
        #expect(saturday.getCachedSectionInfo(0)?.firstDay == 2)
        #expect(saturday.headerView.dayLabels.first?.text == "Sat")

        var wednesdayFirst = utc
        wednesdayFirst.firstWeekday = 4
        let automatic = makeCalendar(
            start: date(2024, 1, 10), end: date(2024, 1, 20), firstWeekday: .automatic, calendar: wednesdayFirst)
        #expect(automatic.style.effectiveFirstWeekday == 4)
        #expect(automatic.getCachedSectionInfo(0)?.firstDay == 5)
        #expect(automatic.headerView.dayLabels.map(\.text) == ["Wed", "Thu", "Fri", "Sat", "Sun", "Mon", "Tue"])
    }

    @Test func numberOfSectionsCoversEveryMonthTouchedByTheRange() {
        let view = makeCalendar(start: date(2024, 1, 15), end: date(2024, 3, 10))
        #expect(view.numberOfSections(in: view.collectionView) == 3)
        #expect(view.months?.startIndexPath == IndexPath(item: 14, section: 0))
        #expect(view.months?.endIndexPath == IndexPath(item: 13, section: 2))
    }

    @Test func singleMonthRangeHasOneSection() {
        let view = makeCalendar(start: date(2024, 9, 15), end: date(2024, 9, 18))
        #expect(view.numberOfSections(in: view.collectionView) == 1)
    }

    @Test func startAfterEndShowsNoMonths() {
        // Issue #132: this used to be a fatalError.
        let view = makeCalendar(start: date(2024, 3, 10), end: date(2024, 1, 15))
        #expect(view.numberOfSections(in: view.collectionView) == 0)
        #expect(view.indexPathForDate(date(2024, 2, 1)) == nil)
        view.selectDate(date(2024, 2, 1))
        #expect(view.selectedDates == [])
    }

    @Test func rangeFollowsTheDataSourceWhenItsDatesChange() {
        let view = makeCalendar(start: date(2024, 1, 15), end: date(2024, 3, 10))
        let source = view.dataSource as! FixedDataSource
        source.end = date(2024, 5, 1)
        view.reloadData()
        #expect(view.numberOfSections(in: view.collectionView) == 5)
        // A different time on the same days does not rebuild the grid.
        let grid = view.months
        source.start = date(2024, 1, 15, hour: 20)
        view.reloadData()
        #expect(view.months?.startDay == grid?.startDay)
    }

    @Test func dateRangeSpansTheDataSourceAtTheStartOfEachDay() {
        let view = makeCalendar(start: date(2024, 1, 15, hour: 9), end: date(2024, 3, 10, hour: 18))
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

    @Test func datesOutsideTheDisplayedMonthsHaveNoIndexPath() {
        let view = makeCalendar(start: date(2024, 1, 15), end: date(2024, 3, 10))
        #expect(view.indexPathForDate(date(2023, 12, 31)) == nil)
        #expect(view.indexPathForDate(date(2024, 4, 1)) == nil)
        #expect(view.dateFromIndexPath(IndexPath(item: 0, section: 0)) == date(2024, 1, 1))
        #expect(view.dateFromIndexPath(IndexPath(item: 31, section: 0)) == nil, "empty cell after the 31st")
        #expect(view.dateFromIndexPath(IndexPath(item: 0, section: 7)) == nil)
    }

    @Test func indexPathsUseTheStyleCalendar() {
        // 2024-01-15 23:30 UTC is already the 16th in Athens.
        var athens = Calendar(identifier: .gregorian)
        athens.timeZone = TimeZone(identifier: "Europe/Athens")!
        let view = makeCalendar(start: date(2024, 1, 1), end: date(2024, 1, 31), calendar: athens)
        let lateEvening = date(2024, 1, 15, hour: 23).addingTimeInterval(30 * 60)
        #expect(view.indexPathForDate(lateEvening) == IndexPath(item: 15, section: 0))
        #expect(view.dateFromIndexPath(IndexPath(item: 15, section: 0)) == athens.startOfDay(for: lateEvening))
    }

    @Test func todayIsMarkedInTheStyleCalendar() {
        let now = Date()
        let local = Calendar.current
        let view = makeCalendar(
            start: local.date(byAdding: .month, value: -1, to: now)!,
            end: local.date(byAdding: .month, value: 1, to: now)!,
            calendar: local)
        view.setDisplayDate(now)
        view.layoutIfNeeded()
        let indexPath = view.indexPathForDate(now)!
        #expect(view.todayIndexPath == indexPath)
        #expect(cell(view, indexPath)?.isToday == true)
        #expect(cell(view, indexPath)?.day == local.component(.day, from: now))
    }

    @Test func theDefaultCalendarIsTheUsersCurrentOne() {
        #expect(CalendarView.Style().calendar == Calendar.current)
    }

    // MARK: Cell configuration

    @Test func cellsOutsideTheMonthAreHidden() {
        let view = makeCalendar(start: date(2024, 2, 1), end: date(2024, 2, 29))
        // February 2024: Thursday first, so items 0...2 and 32...41 are not days.
        #expect(cell(view, IndexPath(item: 0, section: 0))?.isHidden == true)
        #expect(cell(view, IndexPath(item: 0, section: 0))?.dotsView.isHidden == true, "a fresh cell has no dot")
        #expect(cell(view, IndexPath(item: 2, section: 0))?.isHidden == true)
        #expect(cell(view, IndexPath(item: 3, section: 0))?.isHidden == false)
        #expect(cell(view, IndexPath(item: 3, section: 0))?.day == 1)
        #expect(cell(view, IndexPath(item: 31, section: 0))?.day == 29)
        #expect(cell(view, IndexPath(item: 32, section: 0))?.isHidden == true)
    }

    @Test func adjacentDaysShowThePreviousAndNextMonth() {
        let view = makeCalendar(start: date(2024, 1, 1), end: date(2024, 2, 29))
        view.style.showAdjacentDays = true
        view.setDisplayDate(date(2024, 2, 1))
        view.layoutIfNeeded()
        // February 2024 starts on a Thursday: the three cells before it are 29, 30, 31 January.
        #expect(cell(view, IndexPath(item: 0, section: 1))?.day == 29)
        #expect(cell(view, IndexPath(item: 0, section: 1))?.isAdjacent == true)
        #expect(cell(view, IndexPath(item: 2, section: 1))?.day == 31)
        #expect(cell(view, IndexPath(item: 32, section: 1))?.day == 1)
        #expect(cell(view, IndexPath(item: 32, section: 1))?.isAdjacent == true)
        #expect(
            cell(view, IndexPath(item: 32, section: 1))?.dotsView.isHidden == true, "adjacent days never show events")
        #expect(cell(view, IndexPath(item: 32, section: 1))?.bgView.backgroundColor == .clear)
        // The first month has no previous month to borrow from.
        view.setDisplayDate(date(2024, 1, 1))
        view.layoutIfNeeded()
        #expect(cell(view, IndexPath(item: 31, section: 0))?.day == 1)
        #expect(view.shouldSelect(IndexPath(item: 31, section: 0)) == false, "adjacent days are not selectable")
        let februaryOnly = makeCalendar(start: date(2024, 2, 1), end: date(2024, 2, 29))
        februaryOnly.style.showAdjacentDays = true
        februaryOnly.layoutIfNeeded()
        #expect(cell(februaryOnly, IndexPath(item: 0, section: 0))?.isHidden == true, "nothing before the first month")
        #expect(cell(februaryOnly, IndexPath(item: 32, section: 0))?.day == 1, "March continues after the 29th")
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

    @Test func weekendFlagsFollowTheCalendar() {
        let monday = makeCalendar(start: date(2024, 1, 1), end: date(2024, 1, 31))
        #expect(cell(monday, IndexPath(item: 4, section: 0))?.isWeekend == false)  // Friday 5th
        #expect(cell(monday, IndexPath(item: 5, section: 0))?.isWeekend == true)  // Saturday 6th
        #expect(cell(monday, IndexPath(item: 6, section: 0))?.isWeekend == true)  // Sunday 7th

        let sunday = makeCalendar(start: date(2024, 1, 1), end: date(2024, 1, 31), firstWeekday: .sunday)
        #expect(cell(sunday, IndexPath(item: 7, section: 0))?.isWeekend == true)  // Sunday 7th
        #expect(cell(sunday, IndexPath(item: 8, section: 0))?.isWeekend == false)  // Monday 8th
        #expect(cell(sunday, IndexPath(item: 13, section: 0))?.isWeekend == true)  // Saturday 13th

        let unmarked = makeCalendar(start: date(2024, 1, 1), end: date(2024, 1, 31))
        unmarked.marksWeekends = false
        unmarked.layoutIfNeeded()
        #expect(cell(unmarked, IndexPath(item: 5, section: 0))?.isWeekend == false)
    }

    @Test func reusedCellsStartClean() {
        // Issues #120 and #127: a recycled "today" or selected cell kept its look.
        let view = makeCalendar(start: date(2024, 1, 15), end: date(2024, 3, 10))
        let reused = cell(view, IndexPath(item: 20, section: 0))!
        reused.isToday = true
        reused.isWeekend = true
        reused.eventsCount = 3
        reused.prepareForReuse()
        #expect(reused.isToday == false)
        #expect(reused.isWeekend == false)
        #expect(reused.eventsCount == 0)
        #expect(reused.day == nil)
        #expect(reused.isHidden == false)
        // An out-of-range cell is fully configured, so a flag can never survive on it.
        let outOfRange =
            view.collectionView(view.collectionView, cellForItemAt: IndexPath(item: 2, section: 0)) as! CalendarDayCell
        #expect(outOfRange.isOutOfRange == true)
        #expect(outOfRange.isToday == false)
        #expect(outOfRange.textLabel.textColor == view.style.cellColorOutOfRange)
    }

    @Test func outOfRangeWinsOverTodayForTheTextColour() {
        let dayCell = CalendarDayCell(frame: CGRect(x: 0, y: 0, width: 40, height: 40))
        dayCell.isToday = true
        #expect(dayCell.textLabel.textColor == dayCell.style.cellTextColorToday)
        #expect(dayCell.bgView.backgroundColor == dayCell.style.cellColorToday)
        dayCell.isOutOfRange = true
        #expect(dayCell.textLabel.textColor == dayCell.style.cellColorOutOfRange)
        #expect(dayCell.bgView.backgroundColor == dayCell.style.cellColorDefault)
        dayCell.isSelected = true
        #expect(dayCell.textLabel.textColor == dayCell.style.cellSelectedTextColor)
        #expect(dayCell.bgView.layer.borderWidth == dayCell.style.cellSelectedBorderWidth)
    }

    @Test func eventsMarkEveryDayTheyCover() {
        let view = makeCalendar(start: date(2024, 1, 1), end: date(2024, 1, 31))
        view.events = [
            CalendarEvent(title: "a", startDate: date(2024, 1, 10, hour: 9), endDate: date(2024, 1, 10, hour: 10)),
            CalendarEvent(title: "b", startDate: date(2024, 1, 10, hour: 14), endDate: date(2024, 1, 12, hour: 10)),
            CalendarEvent(title: "midnight", startDate: date(2024, 1, 20), endDate: date(2024, 1, 21)),
            CalendarEvent(title: "c", startDate: date(2024, 2, 1), endDate: date(2024, 2, 2)),
        ]
        #expect(view.eventsByIndexPath[IndexPath(item: 9, section: 0)]?.count == 2)
        #expect(view.eventsByIndexPath[IndexPath(item: 10, section: 0)]?.map(\.title) == ["b"])
        #expect(view.eventsByIndexPath[IndexPath(item: 11, section: 0)]?.map(\.title) == ["b"])
        #expect(view.eventsByIndexPath[IndexPath(item: 12, section: 0)] == nil)
        #expect(
            view.eventsByIndexPath[IndexPath(item: 19, section: 0)]?.count == 1,
            "an event ending at midnight stays on its day")
        #expect(view.eventsByIndexPath[IndexPath(item: 20, section: 0)] == nil)
        view.layoutIfNeeded()
        #expect(cell(view, IndexPath(item: 9, section: 0))?.eventsCount == 2)
        #expect(cell(view, IndexPath(item: 9, section: 0))?.dotsView.isHidden == false)
    }

    @Test func eventsCanBeSetBeforeTheViewHasADataSource() {
        let view = CalendarView(frame: .zero)
        view.events = [CalendarEvent(title: "a", startDate: Date(), endDate: Date())]
        #expect(view.eventsByIndexPath.isEmpty)
        #expect(view.numberOfSections(in: view.collectionView) == 0)
    }

    // MARK: Header and display date

    @Test func headerShowsMonthAndYearInTheStyleLocale() {
        let view = makeCalendar(start: date(2024, 1, 15), end: date(2024, 3, 10))
        view.setDisplayDate(date(2024, 2, 10))
        #expect(view.headerView.monthLabel.text == "February 2024")
        #expect(view.displayDate == date(2024, 2, 1), "displayDate is the first day of the month shown")

        let german = makeCalendar(start: date(2024, 1, 15), end: date(2024, 3, 10), locale: Locale(identifier: "de_DE"))
        german.setDisplayDate(date(2024, 2, 10))
        #expect(german.headerView.monthLabel.text == "Februar 2024")
    }

    @Test func headerStringFromTheDataSourceWins() {
        let view = makeCalendar(start: date(2024, 1, 15), end: date(2024, 3, 10))
        (view.dataSource as! FixedDataSource).header = "Custom"
        view.setDisplayDate(date(2024, 2, 10))
        #expect(view.headerView.monthLabel.text == "Custom")
    }

    @Test func nonGregorianCalendarsUseTheirOwnMonthNames() {
        // Issue #134. 10 February 2024 is 21 Bahman 1402 in the Persian calendar.
        var persian = Calendar(identifier: .persian)
        persian.timeZone = TimeZone(identifier: "UTC")!
        let view = makeCalendar(start: date(2024, 1, 15), end: date(2024, 3, 10), calendar: persian)
        view.setDisplayDate(date(2024, 2, 10))
        view.layoutIfNeeded()
        #expect(view.headerView.monthLabel.text == "Bahman 1402")
        #expect(view.numberOfSections(in: view.collectionView) == 3, "Dey, Bahman and Esfand 1402")
        #expect(cell(view, view.indexPathForDate(date(2024, 2, 10))!)?.day == 21)
    }

    @Test func setDisplayDateOutsideTheRangeIsIgnored() {
        let view = makeCalendar(start: date(2024, 1, 15), end: date(2024, 3, 10))
        view.setDisplayDate(date(2024, 2, 10))
        view.setDisplayDate(date(2024, 6, 1))
        #expect(view.displayDate == date(2024, 2, 1))
    }

    @Test func weekdayLabelsStartOnTheConfiguredDay() {
        let monday = makeCalendar(start: date(2024, 1, 1), end: date(2024, 1, 31))
        #expect(monday.headerView.dayLabels.map(\.text) == ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"])
        let sunday = makeCalendar(start: date(2024, 1, 1), end: date(2024, 1, 31), firstWeekday: .sunday)
        #expect(sunday.headerView.dayLabels.map(\.text) == ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"])
    }

    @Test func didScrollToMonthFiresOncePerSettledMonth() {
        // Issue #109: the delegate used to hear about month zero on every reload.
        let view = makeCalendar(start: date(2024, 1, 15), end: date(2024, 3, 10))
        #expect(delegate(of: view).scrolledTo == [date(2024, 1, 1)], "the first month is announced once")
        view.reloadData()
        view.layoutIfNeeded()
        #expect(delegate(of: view).scrolledTo == [date(2024, 1, 1)])
        view.setDisplayDate(date(2024, 2, 10))
        #expect(delegate(of: view).scrolledTo == [date(2024, 1, 1), date(2024, 2, 1)])
        view.setDisplayDate(date(2024, 2, 20))
        #expect(delegate(of: view).scrolledTo == [date(2024, 1, 1), date(2024, 2, 1)], "same month, no repeat")
        view.setDisplayDate(date(2024, 3, 1))
        #expect(delegate(of: view).scrolledTo.last == date(2024, 3, 1))
    }

    @Test func goToNextAndPreviousMonthMoveTheDisplayDate() {
        let view = makeCalendar(start: date(2024, 1, 15), end: date(2024, 3, 10))
        view.goToNextMonth()
        #expect(view.displayDate == date(2024, 2, 1))
        view.goToNextMonth()
        #expect(view.displayDate == date(2024, 3, 1))
        view.goToNextMonth()
        #expect(view.displayDate == date(2024, 3, 1), "cannot leave the last month")
        view.goToPreviousMonth()
        #expect(view.displayDate == date(2024, 2, 1))
    }

    // MARK: Selection

    @Test func selectDateRecordsTheDateAndNotifiesTheDelegate() {
        let view = makeCalendar(start: date(2024, 1, 1), end: date(2024, 1, 31))
        view.selectDate(date(2024, 1, 10))
        #expect(view.selectedDates == [date(2024, 1, 10)])
        #expect(view.selectedIndexPaths == [IndexPath(item: 9, section: 0)])
        #expect(delegate(of: view).selected == [date(2024, 1, 10)])
        #expect(view.collectionView.indexPathsForSelectedItems == [IndexPath(item: 9, section: 0)])
        #expect(cell(view, IndexPath(item: 9, section: 0))?.isSelected == true)
    }

    @Test func selectingTheSameDateTwiceIsANoOp() {
        let view = makeCalendar(start: date(2024, 1, 1), end: date(2024, 1, 31))
        view.selectDate(date(2024, 1, 10))
        view.selectDate(date(2024, 1, 10, hour: 12))
        #expect(view.selectedDates == [date(2024, 1, 10)])
        #expect(delegate(of: view).selected.count == 1)
    }

    @Test func deselectDateRemovesTheDateAndNotifiesTheDelegate() {
        let view = makeCalendar(start: date(2024, 1, 1), end: date(2024, 1, 31))
        view.selectDate(date(2024, 1, 10))
        view.deselectDate(date(2024, 1, 10))
        #expect(view.selectedDates == [])
        #expect(delegate(of: view).deselected == [date(2024, 1, 10)])
        #expect(view.collectionView.indexPathsForSelectedItems == [])
    }

    @Test func deselectingADateThatIsNotSelectedDoesNothing() {
        let view = makeCalendar(start: date(2024, 1, 1), end: date(2024, 1, 31))
        view.deselectDate(date(2024, 1, 10))
        #expect(view.selectedDates == [])
        #expect(delegate(of: view).deselected == [])
    }

    @Test func singleSelectionReplacesThePreviousDate() {
        let view = makeCalendar(start: date(2024, 1, 1), end: date(2024, 1, 31))
        view.multipleSelectionEnable = false
        view.selectDate(date(2024, 1, 10))
        view.selectDate(date(2024, 1, 12))
        #expect(view.selectedDates == [date(2024, 1, 12)])
        #expect(delegate(of: view).deselected == [date(2024, 1, 10)])
        #expect(delegate(of: view).selected == [date(2024, 1, 10), date(2024, 1, 12)])
        #expect(view.collectionView.indexPathsForSelectedItems == [IndexPath(item: 11, section: 0)])
    }

    @Test func singleSelectionAppliesToDaysOnOtherPages() {
        let view = makeCalendar(start: date(2024, 1, 15), end: date(2024, 3, 10))
        view.multipleSelectionEnable = false
        view.selectDate(date(2024, 1, 20))
        view.selectDate(date(2024, 3, 5))
        #expect(view.selectedDates == [date(2024, 3, 5)])
        #expect(delegate(of: view).selected == [date(2024, 1, 20), date(2024, 3, 5)])
        view.setDisplayDate(date(2024, 3, 5))
        view.layoutIfNeeded()
        #expect(cell(view, view.indexPathForDate(date(2024, 3, 5))!)?.isSelected == true)
    }

    @Test func turningOffMultipleSelectionKeepsTheLastDate() {
        let view = makeCalendar(start: date(2024, 1, 1), end: date(2024, 1, 31))
        view.selectDate(date(2024, 1, 10))
        view.selectDate(date(2024, 1, 12))
        view.multipleSelectionEnable = false
        #expect(view.selectedDates == [date(2024, 1, 12)])
        #expect(view.collectionView.indexPathsForSelectedItems == [IndexPath(item: 11, section: 0)])
    }

    @Test func multipleSelectionAccumulates() {
        let view = makeCalendar(start: date(2024, 1, 1), end: date(2024, 1, 31))
        view.selectDate(date(2024, 1, 10))
        view.selectDate(date(2024, 1, 12))
        #expect(view.selectedDates == [date(2024, 1, 10), date(2024, 1, 12)])
        #expect(
            Set(view.collectionView.indexPathsForSelectedItems ?? []) == [
                IndexPath(item: 9, section: 0), IndexPath(item: 11, section: 0),
            ])
    }

    @Test func selectionSurvivesAReload() {
        let view = makeCalendar(start: date(2024, 1, 1), end: date(2024, 1, 31))
        view.selectDate(date(2024, 1, 10))
        view.reloadData()
        view.layoutIfNeeded()
        #expect(cell(view, IndexPath(item: 9, section: 0))?.isSelected == true)
        #expect(view.collectionView.indexPathsForSelectedItems == [IndexPath(item: 9, section: 0)])
        // Setting events, the style or the weekend flag reloads too.
        view.events = [CalendarEvent(title: "a", startDate: date(2024, 1, 3), endDate: date(2024, 1, 3, hour: 1))]
        view.style.cellShape = .round
        view.marksWeekends = false
        view.layoutIfNeeded()
        #expect(cell(view, IndexPath(item: 9, section: 0))?.isSelected == true)
        #expect(view.collectionView.indexPathsForSelectedItems == [IndexPath(item: 9, section: 0)])
    }

    @Test func clearAllSelectedDatesDoesNotNotify() {
        let view = makeCalendar(start: date(2024, 1, 1), end: date(2024, 1, 31))
        view.selectDate(date(2024, 1, 10))
        view.clearAllSelectedDates()
        #expect(view.selectedDates == [])
        #expect(delegate(of: view).deselected == [])
        #expect(view.collectionView.indexPathsForSelectedItems == [])
    }

    @Test func outOfRangeDaysAreNotSelectable() {
        let view = makeCalendar(start: date(2024, 1, 15), end: date(2024, 3, 10))
        view.selectDate(date(2024, 1, 5))
        view.selectDate(date(2024, 3, 11))
        view.selectDate(date(2024, 5, 1))
        #expect(view.selectedDates == [])
        #expect(delegate(of: view).selected == [])
        #expect(view.collectionView(view.collectionView, shouldSelectItemAt: IndexPath(item: 4, section: 0)) == false)
        #expect(
            view.collectionView(view.collectionView, shouldHighlightItemAt: IndexPath(item: 4, section: 0)) == false)
        #expect(view.collectionView(view.collectionView, shouldSelectItemAt: IndexPath(item: 14, section: 0)) == true)
    }

    @Test func canSelectDateGatesTapsAndProgrammaticSelection() {
        let view = makeCalendar(start: date(2024, 1, 1), end: date(2024, 1, 31))
        delegate(of: view).canSelect = { [utc] in utc.component(.day, from: $0) != 10 }
        view.selectDate(date(2024, 1, 10))
        #expect(view.selectedDates == [])
        #expect(view.collectionView(view.collectionView, shouldSelectItemAt: IndexPath(item: 9, section: 0)) == false)
        view.selectDate(date(2024, 1, 11))
        #expect(view.selectedDates == [date(2024, 1, 11)])
    }

    @Test func tapsGoThroughTheCollectionViewCallbacks() {
        let view = makeCalendar(start: date(2024, 1, 1), end: date(2024, 1, 31))
        let indexPath = IndexPath(item: 9, section: 0)
        #expect(view.collectionView(view.collectionView, shouldSelectItemAt: indexPath) == true)
        view.collectionView.selectItem(at: indexPath, animated: false, scrollPosition: [])
        view.collectionView(view.collectionView, didSelectItemAt: indexPath)
        #expect(view.selectedDates == [date(2024, 1, 10)])
        #expect(delegate(of: view).selected == [date(2024, 1, 10)])
        #expect(view.collectionView(view.collectionView, shouldDeselectItemAt: indexPath) == true)
        view.collectionView.deselectItem(at: indexPath, animated: false)
        view.collectionView(view.collectionView, didDeselectItemAt: indexPath)
        #expect(view.selectedDates == [])
        #expect(delegate(of: view).deselected == [date(2024, 1, 10)])
    }

    @Test func enableDeselectionFalseBlocksTapsButNotProgrammaticDeselection() {
        let view = makeCalendar(start: date(2024, 1, 1), end: date(2024, 1, 31))
        view.enableDeselection = false
        view.selectDate(date(2024, 1, 10))
        #expect(view.collectionView(view.collectionView, shouldDeselectItemAt: IndexPath(item: 9, section: 0)) == false)
        #expect(delegate(of: view).deselected == [])
        view.deselectDate(date(2024, 1, 10))
        #expect(view.selectedDates == [])
        #expect(delegate(of: view).deselected == [date(2024, 1, 10)])
    }

    // MARK: Style and references

    @Test func eachCalendarOwnsItsStyle() {
        let a = CalendarView(frame: .zero)
        let b = CalendarView(frame: .zero)
        a.style.headerHeight = 123
        #expect(a.style.headerHeight == 123)
        #expect(b.style.headerHeight == CalendarView.Style.default.headerHeight)
        #expect(a.headerView.style.headerHeight == 123, "in-place mutation restyles the header")
    }

    @Test func changingTheFirstWeekdayRebuildsTheGrid() {
        let view = makeCalendar(start: date(2024, 1, 10), end: date(2024, 1, 20))
        #expect(view.getCachedSectionInfo(0)?.firstDay == 0)
        view.style.firstWeekday = .sunday
        #expect(view.getCachedSectionInfo(0)?.firstDay == 1)
        view.layoutIfNeeded()
        #expect(cell(view, IndexPath(item: 1, section: 0))?.day == 1)
    }

    @Test func delegateAndDataSourceAreHeldWeakly() {
        let view = CalendarView(frame: .zero)
        var dataSource: FixedDataSource? = FixedDataSource(start: Date(), end: Date())
        var delegate: RecordingDelegate? = RecordingDelegate()
        view.dataSource = dataSource
        view.delegate = delegate
        dataSource = nil
        delegate = nil
        #expect(view.dataSource == nil)
        #expect(view.delegate == nil)
    }
}
