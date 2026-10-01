import Testing
import UIKit

@testable import KDCalendar

/// Behavioural tests for the month grid, cell configuration, header, scrolling and selection.
///
/// Serialized because every test lays its calendar out in a shared window.
@Suite(.serialized)
@MainActor
struct CalendarViewTests: CalendarFixture {

    static let window = makeWindow()
    let retained = Retained()

    init() {
        Self.resetWindow()
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

    @Test func automaticFirstWeekdayFollowsTheStyleLocaleWhenTheCalendarHasNone() {
        // `utc` is made with Calendar(identifier:), so it has no locale and says Sunday.
        let british = makeCalendar(
            start: date(2024, 1, 10), end: date(2024, 1, 20), firstWeekday: .automatic,
            locale: Locale(identifier: "en_GB"))
        #expect(british.style.effectiveFirstWeekday == 2)
        #expect(british.calendar.firstWeekday == 2)
        #expect(british.getCachedSectionInfo(0)?.firstDay == 0)
        #expect(british.headerView.dayLabels.first?.text == "Mon")

        let american = makeCalendar(
            start: date(2024, 1, 10), end: date(2024, 1, 20), firstWeekday: .automatic,
            locale: Locale(identifier: "en_US"))
        #expect(american.style.effectiveFirstWeekday == 1)
        #expect(american.getCachedSectionInfo(0)?.firstDay == 1)
        #expect(american.headerView.dayLabels.first?.text == "Sun")
    }

    @Test func numberOfSectionsCoversEveryMonthTouchedByTheRange() {
        let view = makeCalendar(start: date(2024, 1, 15), end: date(2024, 3, 10))
        #expect(view.numberOfSections(in: view.collectionView) == 3)
        #expect(view.indexPathForDate(view.startDay) == IndexPath(item: 14, section: 0))
        #expect(view.indexPathForDate(view.endDay) == IndexPath(item: 13, section: 2))
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
        let source = dataSource(of: view)
        source.end = date(2024, 5, 1)
        view.reloadData()
        #expect(view.numberOfSections(in: view.collectionView) == 5)
        // A different time on the same days does not rebuild the grid.
        let grid = view.months
        source.start = date(2024, 1, 15, hour: 20)
        view.reloadData()
        #expect(view.months?.startDay == grid?.startDay)
    }

    @Test func assigningADataSourceReplacesAGridBuiltWithoutIt() {
        var style = CalendarView.Style()
        style.calendar = utc
        let view = CalendarView(frame: CGRect(x: 0, y: 0, width: 350, height: 420))
        view.style = style
        #expect(view.months != nil, "setting the style builds the current month alone")
        let source = FixedDataSource(start: date(2024, 1, 15), end: date(2024, 3, 10))
        retained.objects.append(source)
        view.dataSource = source
        #expect(view.indexPathForDate(date(2024, 2, 10)) == IndexPath(item: 12, section: 1))
        view.setDisplayDate(date(2024, 2, 10))
        #expect(view.displayDate == date(2024, 2, 1))
        #expect(view.numberOfSections(in: view.collectionView) == 3)
        // Another data source over other days replaces the grid too.
        let other = FixedDataSource(start: date(2025, 6, 1), end: date(2025, 6, 30))
        retained.objects.append(other)
        view.dataSource = other
        #expect(view.indexPathForDate(date(2024, 2, 10)) == nil)
        #expect(view.indexPathForDate(date(2025, 6, 10)) != nil)
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
        #expect(cell(view, indexPath)?.configuration.isToday == true)
        #expect(cell(view, indexPath)?.configuration.day == local.component(.day, from: now))
    }

    @Test func theDefaultCalendarAndLocaleFollowTheUsersSettings() {
        #expect(CalendarView.Style().calendar == Calendar.autoupdatingCurrent)
        #expect(CalendarView.Style().locale == Locale.autoupdatingCurrent)
    }

    @Test func theDefaultCalendarFollowsTheDeviceToAnotherTimeZone() {
        let original = NSTimeZone.default
        defer { NSTimeZone.default = original }
        NSTimeZone.default = TimeZone(identifier: "America/New_York")!
        let before = Calendar.current
        let now = Date()
        // Midnights in New York, which stay on the same days once the device moves east, so only
        // the calendar can tell the view that its grid is stale.
        let view = makeCalendar(
            start: before.startOfDay(for: before.date(byAdding: .month, value: -1, to: now)!),
            end: before.startOfDay(for: before.date(byAdding: .month, value: 1, to: now)!),
            calendar: CalendarView.Style().calendar)
        view.selectDate(now)
        #expect(view.dateFromIndexPath(view.todayIndexPath!) == before.startOfDay(for: now))

        NSTimeZone.default = TimeZone(identifier: "Europe/Athens")!
        NotificationCenter.default.post(name: UIApplication.significantTimeChangeNotification, object: nil)
        view.setDisplayDate(now)
        view.layoutIfNeeded()

        let after = Calendar.current
        let today = view.todayIndexPath!
        #expect(view.dateFromIndexPath(today) == after.startOfDay(for: now))
        #expect(cell(view, today)?.configuration.isToday == true)
        #expect(cell(view, today)?.configuration.day == after.component(.day, from: now))
        // The selected day stays the same calendar day, now at midnight in the new zone.
        let selectedDay = after.date(from: before.dateComponents([.era, .year, .month, .day], from: now))!
        #expect(view.selectedDates == [selectedDay])
        #expect(view.collectionView.indexPathsForSelectedItems == [view.indexPathForDate(selectedDay)!])
        #expect(view.formatters.calendar.timeZone == after.timeZone, "the formatters follow the grid")
        #expect(view.formatters.accessibility.timeZone == after.timeZone)
    }

    // MARK: Cell configuration

    @Test func cellsOutsideTheMonthAreHidden() {
        let view = makeCalendar(start: date(2024, 2, 1), end: date(2024, 2, 29))
        // February 2024: Thursday first, so items 0...2 and 32...41 are not days.
        #expect(cell(view, IndexPath(item: 0, section: 0))?.isHidden == true)
        #expect(cell(view, IndexPath(item: 0, section: 0))?.dotsView.isHidden == true, "a fresh cell has no dot")
        #expect(cell(view, IndexPath(item: 2, section: 0))?.isHidden == true)
        #expect(cell(view, IndexPath(item: 3, section: 0))?.isHidden == false)
        #expect(cell(view, IndexPath(item: 3, section: 0))?.configuration.day == 1)
        #expect(cell(view, IndexPath(item: 31, section: 0))?.configuration.day == 29)
        #expect(cell(view, IndexPath(item: 32, section: 0))?.isHidden == true)
    }

    @Test func adjacentDaysShowThePreviousAndNextMonth() {
        let view = makeCalendar(start: date(2024, 1, 1), end: date(2024, 2, 29))
        view.style.showAdjacentDays = true
        view.setDisplayDate(date(2024, 2, 1))
        view.layoutIfNeeded()
        // February 2024 starts on a Thursday: the three cells before it are 29, 30, 31 January.
        #expect(cell(view, IndexPath(item: 0, section: 1))?.configuration.day == 29)
        #expect(cell(view, IndexPath(item: 0, section: 1))?.configuration.isAdjacent == true)
        #expect(cell(view, IndexPath(item: 2, section: 1))?.configuration.day == 31)
        #expect(cell(view, IndexPath(item: 32, section: 1))?.configuration.day == 1)
        #expect(cell(view, IndexPath(item: 32, section: 1))?.configuration.isAdjacent == true)
        #expect(
            cell(view, IndexPath(item: 32, section: 1))?.dotsView.isHidden == true, "adjacent days never show events")
        #expect(cell(view, IndexPath(item: 32, section: 1))?.bgView.backgroundColor == .clear)
        view.setDisplayDate(date(2024, 1, 1))
        view.layoutIfNeeded()
        #expect(cell(view, IndexPath(item: 31, section: 0))?.configuration.day == 1)
        #expect(view.shouldSelect(IndexPath(item: 31, section: 0)) == false, "adjacent days are not selectable")
        let februaryOnly = makeCalendar(start: date(2024, 2, 1), end: date(2024, 2, 29))
        februaryOnly.style.showAdjacentDays = true
        februaryOnly.layoutIfNeeded()
        #expect(
            cell(februaryOnly, IndexPath(item: 0, section: 0))?.configuration.day == 29,
            "January ends before the first month")
        #expect(cell(februaryOnly, IndexPath(item: 0, section: 0))?.configuration.isAdjacent == true)
        #expect(cell(februaryOnly, IndexPath(item: 0, section: 0))?.isHidden == false)
        #expect(
            cell(februaryOnly, IndexPath(item: 32, section: 0))?.configuration.day == 1,
            "March continues after the 29th")
    }

    @Test func outOfRangeFlagsRespectBothEndsInsideASingleMonth() {
        // Issue #131: 15 to 18 September 2024, one section, both edges apply.
        let view = makeCalendar(start: date(2024, 9, 15), end: date(2024, 9, 18))
        // September 2024 starts on a Sunday: Monday-first index 6.
        func flag(_ day: Int) -> Bool? {
            cell(view, IndexPath(item: 6 + day - 1, section: 0))?.configuration.isOutOfRange
        }
        #expect(flag(14) == true)
        #expect(flag(15) == false)
        #expect(flag(18) == false)
        #expect(flag(19) == true)
    }

    @Test func outOfRangeFlagsAcrossMonths() {
        let view = makeCalendar(start: date(2024, 1, 15), end: date(2024, 3, 10))
        #expect(cell(view, IndexPath(item: 13, section: 0))?.configuration.isOutOfRange == true)  // 14 January
        #expect(cell(view, IndexPath(item: 14, section: 0))?.configuration.isOutOfRange == false)  // 15 January
        view.setDisplayDate(date(2024, 3, 1))
        view.layoutIfNeeded()
        // March 2024 starts on a Friday (index 4): the 10th is item 13, the 11th item 14.
        #expect(cell(view, IndexPath(item: 13, section: 2))?.configuration.isOutOfRange == false)
        #expect(cell(view, IndexPath(item: 14, section: 2))?.configuration.isOutOfRange == true)
    }

    @Test func weekendFlagsFollowTheCalendar() {
        let monday = makeCalendar(start: date(2024, 1, 1), end: date(2024, 1, 31))
        #expect(cell(monday, IndexPath(item: 4, section: 0))?.configuration.isWeekend == false)  // Friday 5th
        #expect(cell(monday, IndexPath(item: 5, section: 0))?.configuration.isWeekend == true)  // Saturday 6th
        #expect(cell(monday, IndexPath(item: 6, section: 0))?.configuration.isWeekend == true)  // Sunday 7th

        let sunday = makeCalendar(start: date(2024, 1, 1), end: date(2024, 1, 31), firstWeekday: .sunday)
        #expect(cell(sunday, IndexPath(item: 7, section: 0))?.configuration.isWeekend == true)  // Sunday 7th
        #expect(cell(sunday, IndexPath(item: 8, section: 0))?.configuration.isWeekend == false)  // Monday 8th
        #expect(cell(sunday, IndexPath(item: 13, section: 0))?.configuration.isWeekend == true)  // Saturday 13th

        let unmarked = makeCalendar(start: date(2024, 1, 1), end: date(2024, 1, 31))
        unmarked.marksWeekends = false
        unmarked.layoutIfNeeded()
        #expect(cell(unmarked, IndexPath(item: 5, section: 0))?.configuration.isWeekend == false)
    }

    @Test func reusedCellsStartClean() {
        // Issues #120 and #127: a recycled "today" or selected cell kept its look.
        let view = makeCalendar(start: date(2024, 1, 15), end: date(2024, 3, 10))
        let reused = cell(view, IndexPath(item: 20, section: 0))!
        reused.configuration.isToday = true
        reused.configuration.isWeekend = true
        reused.configuration.eventsCount = 3
        reused.prepareForReuse()
        #expect(reused.configuration.isToday == false)
        #expect(reused.configuration.isWeekend == false)
        #expect(reused.configuration.eventsCount == 0)
        #expect(reused.configuration.day == nil)
        #expect(reused.isHidden == false)
        // An out-of-range cell is fully configured, so a flag can never survive on it.
        let outOfRange =
            view.collectionView(view.collectionView, cellForItemAt: IndexPath(item: 2, section: 0)) as! CalendarDayCell
        #expect(outOfRange.configuration.isOutOfRange == true)
        #expect(outOfRange.configuration.isToday == false)
        #expect(outOfRange.textLabel.textColor == view.style.cellColorOutOfRange)
    }

    @Test func outOfRangeWinsOverTodayForTheTextColour() {
        let dayCell = CalendarDayCell(frame: CGRect(x: 0, y: 0, width: 40, height: 40))
        dayCell.configuration.isToday = true
        #expect(dayCell.textLabel.textColor == dayCell.style.cellTextColorToday)
        #expect(dayCell.bgView.backgroundColor == dayCell.style.cellColorToday)
        dayCell.configuration.isOutOfRange = true
        #expect(dayCell.textLabel.textColor == dayCell.style.cellColorOutOfRange)
        #expect(dayCell.bgView.backgroundColor == dayCell.style.cellColorDefault)
        dayCell.isSelected = true
        #expect(dayCell.textLabel.textColor == dayCell.style.cellSelectedTextColor)
        #expect(dayCell.bgView.layer.borderWidth == dayCell.style.cellSelectedBorderWidth)
    }

    @Test func dayCellLookFollowsItsPrecedence() {
        typealias Day = DayCellConfiguration
        let style = CalendarView.Style.default
        #expect(Day().appearance(isSelected: false).textColor == style.cellTextColorDefault)
        #expect(Day(isWeekend: true).appearance(isSelected: false).textColor == style.cellTextColorWeekend)
        #expect(
            Day(isAdjacent: true, isWeekend: true).appearance(isSelected: false).textColor == style.cellColorAdjacent)
        #expect(
            Day(isToday: true, isAdjacent: true).appearance(isSelected: false).textColor == style.cellTextColorToday)
        #expect(
            Day(isToday: true, isOutOfRange: true).appearance(isSelected: false).textColor == style.cellColorOutOfRange)
        #expect(Day(isOutOfRange: true).appearance(isSelected: true).textColor == style.cellSelectedTextColor)

        #expect(Day(isToday: true).appearance(isSelected: false).backgroundColor == style.cellColorToday)
        #expect(
            Day(isToday: true, isOutOfRange: true).appearance(isSelected: false).backgroundColor
                == style.cellColorDefault)
        #expect(Day(isAdjacent: true).appearance(isSelected: false).backgroundColor == .clear)
        #expect(Day(isAdjacent: true).appearance(isSelected: true).backgroundColor == style.cellSelectedColor)

        let adjacent = Day(isAdjacent: true).appearance(isSelected: false)
        #expect(adjacent.isAccessibilityElement == false)
        #expect(adjacent.accessibilityTraits == [.button, .notEnabled])
        let selected = Day().appearance(isSelected: true)
        #expect(selected.accessibilityTraits == [.button, .selected])
        #expect(selected.borderWidth == style.cellSelectedBorderWidth)
        #expect(Day().appearance(isSelected: false).borderWidth == style.cellBorderWidth)
    }

    @Test func configuringACellShowsTheDayWithoutParsingItBack() {
        let dayCell = CalendarDayCell(frame: CGRect(x: 0, y: 0, width: 40, height: 40))
        dayCell.configuration = DayCellConfiguration(day: 7, eventsCount: 2, accessibilityLabel: "Seventh")
        #expect(dayCell.textLabel.text == "7")
        #expect(dayCell.dotsView.isHidden == false)
        #expect(dayCell.accessibilityLabel == "Seventh")
        dayCell.configuration.isHidden = true
        #expect(dayCell.isHidden == true)
        dayCell.prepareForReuse()
        #expect(dayCell.textLabel.text == nil)
        #expect(dayCell.dotsView.isHidden == true)
        #expect(dayCell.isHidden == false)
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
        #expect(cell(view, IndexPath(item: 9, section: 0))?.configuration.eventsCount == 2)
        #expect(cell(view, IndexPath(item: 9, section: 0))?.dotsView.isHidden == false)
    }

    @Test func eventsCanBeSetBeforeTheViewHasADataSource() {
        let view = CalendarView(frame: .zero)
        view.events = [CalendarEvent(title: "a", startDate: Date(), endDate: Date())]
        #expect(view.numberOfSections(in: view.collectionView) == 1, "the current month stands in for a data source")
        #expect(view.eventsByIndexPath[view.indexPathForDate(Date())!]?.count == 1)
    }

    @Test func theCellShapeSetsTheBackgroundsFrameAndCorners() {
        let rect = CGRect(x: 3, y: 3, width: 40, height: 30)
        let circle = CGRect(x: 8, y: 3, width: 30, height: 30)
        #expect(CalendarView.Style.CellShapeOptions.round.backgroundFrame(in: rect) == circle)
        #expect(CalendarView.Style.CellShapeOptions.round.cornerRadius(for: circle) == 15)
        #expect(CalendarView.Style.CellShapeOptions.square.backgroundFrame(in: rect) == rect)
        #expect(CalendarView.Style.CellShapeOptions.square.cornerRadius(for: rect) == 0)
        #expect(CalendarView.Style.CellShapeOptions.bevel(6).backgroundFrame(in: rect) == rect)
        #expect(CalendarView.Style.CellShapeOptions.bevel(6).cornerRadius(for: rect) == 6)

        // The cell insets its content, then asks the shape for the background.
        var style = CalendarView.Style.default
        style.cellShape = .round
        let dayCell = CalendarDayCell(frame: CGRect(x: 0, y: 0, width: 46, height: 36))
        dayCell.configuration = DayCellConfiguration(day: 1, eventsCount: 1, style: style)
        dayCell.layoutIfNeeded()
        #expect(dayCell.bgView.frame == circle)
        #expect(dayCell.bgView.layer.cornerRadius == 15)
        #expect(dayCell.textLabel.frame == circle)
        #expect(dayCell.dotsView.center.x == circle.midX)
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
        dataSource(of: view).header = "Custom"
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
        #expect(cell(view, view.indexPathForDate(date(2024, 2, 10))!)?.configuration.day == 21)
    }

    @Test func formattersAreBuiltOncePerStyleWithTheGridsCalendar() {
        let view = makeCalendar(start: date(2024, 1, 15), end: date(2024, 3, 10), locale: Locale(identifier: "de_DE"))
        let formatters = view.formatters
        #expect(formatters.calendar == view.calendar, "the style's calendar with its locale filled in")
        #expect(formatters.calendar.locale == Locale(identifier: "de_DE"))
        view.setDisplayDate(date(2024, 2, 10))
        view.setDisplayDate(date(2024, 3, 1))
        view.reloadData()
        #expect(view.formatters.monthTitle === formatters.monthTitle, "settling on a month reuses them")
        #expect(view.formatters.accessibility === formatters.accessibility, "so does every cell")

        view.style.weekDayTransform = .uppercase
        #expect(view.formatters.monthTitle !== formatters.monthTitle, "a new style builds new ones")
        #expect(view.headerView.formatters.monthTitle === view.formatters.monthTitle, "the header shares them")
        #expect(view.headerView.dayLabels.first?.text == "MO.")
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

    @Test func headerLaysOutItsLabelsFromTheStyleMargins() {
        let view = makeCalendar(start: date(2024, 1, 1), end: date(2024, 1, 31))
        let header = view.headerView
        func frames() -> [CGRect] { header.dayLabels.map { header.convert($0.bounds, from: $0) } }

        #expect(header.monthLabel.frame == CGRect(x: 0, y: 5, width: 350, height: 30), "80 - 5 - 5 - 35 - 5")
        #expect(frames().map(\.minX) == [0, 50, 100, 150, 200, 250, 300], "seven equal columns")
        #expect(frames().allSatisfy { $0.minY == 40 && $0.size == CGSize(width: 50, height: 35) })

        view.style.headerHeight = 100
        view.style.headerTopMargin = 10
        view.style.weekdaysHeight = 40
        view.layoutIfNeeded()
        #expect(header.monthLabel.frame == CGRect(x: 0, y: 10, width: 350, height: 40), "100 - 10 - 5 - 40 - 5")
        #expect(frames().allSatisfy { $0.minY == 55 && $0.height == 40 }, "a new style moves the labels")
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

    // MARK: Selection across grid rebuilds

    @Test func selectionFollowsItsDayWhenTheRangeGainsAMonth() {
        let view = makeCalendar(start: date(2024, 3, 1), end: date(2024, 4, 30))
        view.selectDate(date(2024, 3, 15))
        let before = view.indexPathForDate(date(2024, 3, 15))!

        // February joins the grid, so March moves to the second page.
        dataSource(of: view).start = date(2024, 2, 10)
        view.reloadData()

        let after = view.indexPathForDate(date(2024, 3, 15))!
        #expect(after.section == before.section + 1)
        #expect(view.selectedDates == [date(2024, 3, 15)])
        #expect(view.selectedIndexPaths == [after])
        #expect(view.collectionView.indexPathsForSelectedItems == [after])
        #expect(delegate(of: view).deselected == [])
        view.setDisplayDate(date(2024, 3, 15))
        view.layoutIfNeeded()
        #expect(cell(view, after)?.isSelected == true)

        // The old cell shows another day now, and tapping it selects that day.
        let other = view.dateFromIndexPath(before)!
        #expect(other == date(2024, 2, 16))
        view.collectionView.selectItem(at: before, animated: false, scrollPosition: [])
        view.collectionView(view.collectionView, didSelectItemAt: before)
        #expect(view.selectedDates == [date(2024, 3, 15), other])

        view.deselectDate(date(2024, 3, 15))
        #expect(view.selectedDates == [other])
        #expect(delegate(of: view).deselected == [date(2024, 3, 15)])
        #expect(view.collectionView.indexPathsForSelectedItems == [before])
    }

    @Test func tappingASelectedDayAfterTheGridMovedDeselectsIt() {
        let view = makeCalendar(start: date(2024, 3, 1), end: date(2024, 4, 30))
        view.selectDate(date(2024, 3, 15))
        dataSource(of: view).start = date(2024, 2, 10)
        view.reloadData()

        let indexPath = view.indexPathForDate(date(2024, 3, 15))!
        #expect(view.collectionView(view.collectionView, shouldDeselectItemAt: indexPath) == true)
        view.collectionView.deselectItem(at: indexPath, animated: false)
        view.collectionView(view.collectionView, didDeselectItemAt: indexPath)
        #expect(view.selectedDates == [])
        #expect(delegate(of: view).deselected == [date(2024, 3, 15)])
        #expect(view.collectionView.indexPathsForSelectedItems == [])
    }

    @Test func selectionFollowsItsDayWhenTheFirstWeekdayChanges() {
        let view = makeCalendar(start: date(2024, 1, 1), end: date(2024, 1, 31))
        view.selectDate(date(2024, 1, 10))
        #expect(view.selectedIndexPaths == [IndexPath(item: 9, section: 0)])

        view.style.firstWeekday = .sunday
        #expect(view.selectedDates == [date(2024, 1, 10)])
        #expect(view.selectedIndexPaths == [IndexPath(item: 10, section: 0)])
        #expect(view.collectionView.indexPathsForSelectedItems == [IndexPath(item: 10, section: 0)])
        view.layoutIfNeeded()
        #expect(cell(view, IndexPath(item: 10, section: 0))?.isSelected == true)
        #expect(cell(view, IndexPath(item: 9, section: 0))?.isSelected == false)

        view.deselectDate(date(2024, 1, 10))
        #expect(view.selectedDates == [])
        #expect(view.collectionView.indexPathsForSelectedItems == [])
    }

    @Test func selectedDaysThatLeaveTheRangeAreDeselectedAndReported() {
        let view = makeCalendar(start: date(2024, 1, 1), end: date(2024, 3, 31))
        view.selectDate(date(2024, 1, 10))
        view.selectDate(date(2024, 2, 3))
        view.selectDate(date(2024, 2, 20))
        view.selectDate(date(2024, 3, 5))

        // Down to one month: January and March leave the grid, and 3 February is still on the
        // page but before the new start.
        dataSource(of: view).start = date(2024, 2, 5)
        dataSource(of: view).end = date(2024, 2, 29)
        view.reloadData()
        view.layoutIfNeeded()

        #expect(view.numberOfSections(in: view.collectionView) == 1)
        #expect(view.selectedDates == [date(2024, 2, 20)])
        #expect(delegate(of: view).deselected == [date(2024, 1, 10), date(2024, 2, 3), date(2024, 3, 5)])
        #expect(view.collectionView.indexPathsForSelectedItems == [view.indexPathForDate(date(2024, 2, 20))!])
    }

    @Test func aRangeAnchorFollowsItsDayAndGoesWithIt() {
        let view = makeCalendar(start: date(2024, 3, 1), end: date(2024, 4, 30))
        view.selectionMode = .range
        view.selectDate(date(2024, 3, 15))
        dataSource(of: view).start = date(2024, 2, 10)
        view.reloadData()
        view.selectDate(date(2024, 3, 18))
        #expect(view.selectedDates == [date(2024, 3, 15), date(2024, 3, 16), date(2024, 3, 17), date(2024, 3, 18)])

        // A new anchor that leaves the range takes the half-picked range with it.
        view.selectDate(date(2024, 4, 20))
        dataSource(of: view).end = date(2024, 3, 31)
        view.reloadData()
        #expect(view.selectedDates == [])
        #expect(delegate(of: view).deselected.last == date(2024, 4, 20))
        view.selectDate(date(2024, 3, 1))
        #expect(view.selectedDates == [date(2024, 3, 1)], "the next tap starts a new range")
    }

    @Test func selectionKeepsItsDayWhenTheTimeZoneChanges() {
        let view = makeCalendar(start: date(2024, 3, 10), end: date(2024, 3, 20))
        view.selectDate(date(2024, 3, 15))

        // Midnight UTC is the evening before in New York.
        var newYork = utc
        newYork.timeZone = TimeZone(identifier: "America/New_York")!
        view.style.calendar = newYork
        let fifteenth = newYork.date(from: DateComponents(year: 2024, month: 3, day: 15))!
        #expect(view.selectedDates == [fifteenth])
        #expect(view.selectedIndexPaths == [view.indexPathForDate(fifteenth)!])
        #expect(view.collectionView.indexPathsForSelectedItems == view.selectedIndexPaths)
        #expect(delegate(of: view).deselected == [])

        view.deselectDate(fifteenth)
        #expect(view.selectedDates == [])
        #expect(delegate(of: view).deselected == [fifteenth])
    }

    @Test func clearAllSelectedDatesDoesNotNotify() {
        let view = makeCalendar(start: date(2024, 1, 1), end: date(2024, 1, 31))
        view.selectDate(date(2024, 1, 10))
        view.clearAllSelectedDates()
        #expect(view.selectedDates == [])
        #expect(delegate(of: view).deselected == [])
        #expect(view.collectionView.indexPathsForSelectedItems == [])
    }

    @Test func changingTheSelectionModeReportsTheDaysItDrops() {
        let view = makeCalendar(start: date(2024, 1, 1), end: date(2024, 1, 31))
        view.selectDate(date(2024, 1, 8))
        view.selectDate(date(2024, 1, 10))
        view.selectDate(date(2024, 1, 12))

        // Single mode keeps the last day; the delegate hears once the view shows it alone.
        view.selectionMode = .single
        #expect(view.selectedDates == [date(2024, 1, 12)])
        #expect(view.collectionView.indexPathsForSelectedItems == [IndexPath(item: 11, section: 0)])
        #expect(delegate(of: view).deselected == [date(2024, 1, 8), date(2024, 1, 10)])
        #expect(delegate(of: view).selectionWhenDeselected == [[date(2024, 1, 12)], [date(2024, 1, 12)]])

        // Back to multiple drops nothing.
        view.selectionMode = .multiple
        view.selectDate(date(2024, 1, 20))
        #expect(view.selectedDates == [date(2024, 1, 12), date(2024, 1, 20)])
        #expect(delegate(of: view).deselected.count == 2)

        // Range mode starts clean.
        view.selectionMode = .range
        #expect(view.selectedDates == [])
        #expect(view.collectionView.indexPathsForSelectedItems == [])
        #expect(delegate(of: view).deselected.suffix(2) == [date(2024, 1, 12), date(2024, 1, 20)])
        #expect(delegate(of: view).selectionWhenDeselected.suffix(2) == [[], []])

        // Setting the same mode again, or single mode with one day, drops nothing.
        view.selectionMode = .range
        view.selectDate(date(2024, 1, 5))
        view.selectionMode = .single
        #expect(view.selectedDates == [date(2024, 1, 5)])
        #expect(delegate(of: view).deselected.count == 4)
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

    @Test func setSelectionKeepsEverySelectableDayInMultipleModeWithoutNotifying() {
        let view = makeCalendar(start: date(2024, 1, 3), end: date(2024, 1, 31))
        delegate(of: view).canSelect = { [utc] in utc.component(.day, from: $0) != 10 }
        view.selectDate(date(2024, 1, 20))
        view.setSelection([
            date(2024, 1, 12, hour: 9), date(2024, 1, 2), date(2024, 1, 10), date(2024, 1, 5), date(2024, 1, 12),
        ])
        #expect(view.selectedDates == [date(2024, 1, 12), date(2024, 1, 5)], "in order, once, in range and allowed")
        #expect(
            Set(view.collectionView.indexPathsForSelectedItems ?? []) == [
                IndexPath(item: 11, section: 0), IndexPath(item: 4, section: 0),
            ])
        #expect(delegate(of: view).selected == [date(2024, 1, 20)])
        #expect(delegate(of: view).deselected == [])
    }

    @Test func setSelectionKeepsTheLastSelectableDayInSingleMode() {
        let view = makeCalendar(start: date(2024, 1, 1), end: date(2024, 1, 31))
        view.selectionMode = .single
        delegate(of: view).canSelect = { [utc] in utc.component(.day, from: $0) != 10 }
        view.setSelection([date(2024, 1, 5), date(2024, 1, 8), date(2024, 1, 10)])
        #expect(view.selectedDates == [date(2024, 1, 8)])
        #expect(view.collectionView.indexPathsForSelectedItems == [IndexPath(item: 7, section: 0)])
        view.selectDate(date(2024, 1, 12))
        #expect(view.selectedDates == [date(2024, 1, 12)], "a later selection still replaces it")
    }

    @Test func setSelectionFillsARangeFromTheEarliestDayToTheLatest() {
        let view = makeCalendar(start: date(2024, 1, 1), end: date(2024, 2, 29))
        view.selectionMode = .range
        delegate(of: view).canSelect = { [utc] in utc.component(.day, from: $0) != 10 }
        view.setSelection([date(2024, 1, 12), date(2024, 1, 8), date(2024, 1, 11)])
        #expect(view.selectedDates == [date(2024, 1, 8), date(2024, 1, 9), date(2024, 1, 11), date(2024, 1, 12)])
        #expect(Set(view.collectionView.indexPathsForSelectedItems ?? []).count == 4)
        view.selectDate(date(2024, 1, 20))
        #expect(view.selectedDates == [date(2024, 1, 20)], "the range is complete, so the next day starts a new one")

        // A lone day is the first end of a range.
        view.setSelection([date(2024, 1, 30)])
        #expect(view.selectedDates == [date(2024, 1, 30)])
        view.selectDate(date(2024, 2, 2))
        #expect(view.selectedDates == [date(2024, 1, 30), date(2024, 1, 31), date(2024, 2, 1), date(2024, 2, 2)])
        #expect(delegate(of: view).selected == [date(2024, 1, 20), date(2024, 2, 2)], "only the taps are reported")

        // Ends outside the data source's range keep the days inside it.
        view.setSelection([date(2023, 6, 1), date(2024, 1, 2)])
        #expect(view.selectedDates == [date(2024, 1, 1), date(2024, 1, 2)])

        view.setSelection([])
        #expect(view.selectedDates == [])
        #expect(view.collectionView.indexPathsForSelectedItems == [])
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
        #expect(cell(view, IndexPath(item: 1, section: 0))?.configuration.day == 1)
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
