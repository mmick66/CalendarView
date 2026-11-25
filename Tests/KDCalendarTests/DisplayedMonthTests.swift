import Testing
import UIKit

@testable import KDCalendar

/// The displayed month across reloads: whatever a reload changes, the view stays on the month it
/// displayed, or moves to the nearest one, and its title, offset and delegate agree.
///
/// UIKit does not run scroll animations in a test process, so the tests move the content offset
/// and deliver the scroll view callbacks themselves, as UIKit would.
@Suite(.serialized)
@MainActor
struct DisplayedMonthTests: CalendarFixture {

    static let window = makeWindow()
    let retained = Retained()

    init() {
        Self.resetWindow()
    }

    /// Expects everything the view keeps about its month to say `month`: the display date, the
    /// title, the page on screen and the cells laid out.
    private func expectDisplayed(
        _ view: CalendarView, _ month: Date, title: String, sourceLocation: SourceLocation = #_sourceLocation
    ) {
        view.layoutIfNeeded()
        #expect(view.displayDate == month, sourceLocation: sourceLocation)
        #expect(view.headerView.monthLabel.text == title, sourceLocation: sourceLocation)
        guard let firstDay = view.indexPathForDate(month) else {
            Issue.record("the displayed month is not in the grid", sourceLocation: sourceLocation)
            return
        }
        #expect(
            view.collectionView.contentOffset == view.flowLayout.contentOffset(forSection: firstDay.section),
            sourceLocation: sourceLocation)
        #expect(view.dateFromScrollViewPosition() == month, sourceLocation: sourceLocation)
        #expect(
            cell(view, firstDay)?.configuration.day == 1, "the month's cells are on screen",
            sourceLocation: sourceLocation)
    }

    // MARK: A new range

    @Test func aRangeThatGainsEarlierMonthsKeepsTheDisplayedMonth() {
        let view = makeCalendar(start: date(2024, 1, 15), end: date(2024, 3, 10))
        view.setDisplayDate(date(2024, 3, 1))
        view.layoutIfNeeded()
        let width = view.collectionView.bounds.width
        #expect(view.collectionView.contentOffset.x == 2 * width)

        // November and December join the grid, so March moves from the third page to the fifth.
        dataSource(of: view).start = date(2023, 11, 5)
        view.reloadData()

        expectDisplayed(view, date(2024, 3, 1), title: "March 2024")
        #expect(view.collectionView.contentOffset.x == 4 * width)
        #expect(
            delegate(of: view).scrolledTo == [date(2024, 1, 1), date(2024, 3, 1)],
            "the month did not change, so it is not announced again")
    }

    @Test func aDataSourceAssignedAfterTheFirstLayoutDisplaysAMonthOfItsRange() {
        let view = CalendarView(frame: CGRect(x: 0, y: 0, width: 350, height: 420))
        view.style = makeStyle()
        let delegate = RecordingDelegate()
        retained.objects.append(delegate)
        view.delegate = delegate
        Self.window.addSubview(view)
        view.layoutIfNeeded()
        let thisMonth = utc.dateInterval(of: .month, for: Date())!.start
        #expect(view.displayDate == thisMonth)

        // A range in the past: its last month is the nearest to the month on screen.
        let past = FixedDataSource(start: date(2024, 1, 15), end: date(2024, 3, 10))
        retained.objects.append(past)
        view.dataSource = past
        expectDisplayed(view, date(2024, 3, 1), title: "March 2024")
        #expect(delegate.scrolledTo == [thisMonth, date(2024, 3, 1)])

        // A range in the future: its first month is.
        let future = FixedDataSource(start: date(2100, 1, 15), end: date(2100, 3, 10))
        retained.objects.append(future)
        view.dataSource = future
        expectDisplayed(view, date(2100, 1, 1), title: "January 2100")
        #expect(delegate.scrolledTo == [thisMonth, date(2024, 3, 1), date(2100, 1, 1)])
    }

    @Test func aDisplayedMonthThatLeavesTheRangeMovesToTheNearestMonth() {
        let view = makeCalendar(start: date(2024, 1, 15), end: date(2024, 3, 10))
        view.setDisplayDate(date(2024, 3, 1))
        view.layoutIfNeeded()

        dataSource(of: view).start = date(2025, 6, 1)
        dataSource(of: view).end = date(2025, 8, 31)
        view.reloadData()
        expectDisplayed(view, date(2025, 6, 1), title: "June 2025")
        #expect(delegate(of: view).scrolledTo == [date(2024, 1, 1), date(2024, 3, 1), date(2025, 6, 1)])

        // The view is on a month of the grid again, so the next and previous month work.
        view.goToNextMonth()
        #expect(view.displayDate == date(2025, 7, 1))
        view.goToPreviousMonth()
        #expect(view.displayDate == date(2025, 6, 1))

        // A range before the displayed month: its last month is the nearest.
        view.setDisplayDate(date(2025, 7, 1))
        dataSource(of: view).start = date(2024, 1, 15)
        dataSource(of: view).end = date(2024, 3, 10)
        view.reloadData()
        expectDisplayed(view, date(2024, 3, 1), title: "March 2024")
        #expect(delegate(of: view).scrolledTo.suffix(2) == [date(2025, 7, 1), date(2024, 3, 1)])
    }

    @Test func theMonthComesBackAfterAnInvalidRange() {
        let view = makeCalendar(start: date(2024, 1, 15), end: date(2024, 3, 10))
        view.setDisplayDate(date(2024, 2, 10))
        view.layoutIfNeeded()

        dataSource(of: view).start = date(2024, 4, 1)
        view.reloadData()
        view.layoutIfNeeded()
        #expect(view.numberOfSections(in: view.collectionView) == 0)
        #expect(view.displayDate == date(2024, 2, 1), "kept while there is no month to display")

        dataSource(of: view).start = date(2023, 12, 1)
        view.reloadData()
        expectDisplayed(view, date(2024, 2, 1), title: "February 2024")
        #expect(delegate(of: view).scrolledTo == [date(2024, 1, 1), date(2024, 2, 1)])
    }

    @Test func aRangeThatBecomesValidAfterTheFirstLayoutDisplaysItsFirstMonth() {
        let view = makeCalendar(start: date(2024, 3, 10), end: date(2024, 1, 15))
        #expect(view.displayDate == nil)
        #expect(delegate(of: view).scrolledTo == [])

        dataSource(of: view).start = date(2024, 1, 15)
        dataSource(of: view).end = date(2024, 3, 10)
        view.reloadData()
        expectDisplayed(view, date(2024, 1, 1), title: "January 2024")
        #expect(delegate(of: view).scrolledTo == [date(2024, 1, 1)])
    }

    @Test func aRightToLeftCalendarKeepsItsMonthWhenTheRangeGainsMonths() {
        // Right to left the first month is the last page, so a month's page depends on how many
        // months there are: a month added at the end moves the pages that one at the start leaves.
        let view = makeCalendar(start: date(2024, 1, 15), end: date(2024, 3, 10))
        view.forceLtr = false
        view.semanticContentAttribute = .forceRightToLeft
        view.setDisplayDate(date(2024, 2, 1))
        view.layoutIfNeeded()
        let width = view.collectionView.bounds.width
        #expect(view.collectionView.effectiveUserInterfaceLayoutDirection == .rightToLeft)
        #expect(view.collectionView.contentOffset.x == width, "February is the middle page of three")

        // April and May join the grid: February moves from the second page to the fourth.
        dataSource(of: view).end = date(2024, 5, 20)
        view.reloadData()
        expectDisplayed(view, date(2024, 2, 1), title: "February 2024")
        #expect(view.collectionView.contentOffset.x == 3 * width)

        // November and December join it: the pages to the left of February's are all still there.
        dataSource(of: view).start = date(2023, 11, 5)
        view.reloadData()
        expectDisplayed(view, date(2024, 2, 1), title: "February 2024")
        #expect(view.collectionView.contentOffset.x == 3 * width)

        // The months after February go: it is the first page now, the leftmost.
        dataSource(of: view).end = date(2024, 2, 20)
        view.reloadData()
        expectDisplayed(view, date(2024, 2, 1), title: "February 2024")
        #expect(view.collectionView.contentOffset.x == 0)

        // February goes too, and January is the nearest month left.
        dataSource(of: view).end = date(2024, 1, 20)
        view.reloadData()
        expectDisplayed(view, date(2024, 1, 1), title: "January 2024")
        #expect(view.collectionView.contentOffset.x == 0)
        #expect(
            delegate(of: view).scrolledTo == [date(2024, 1, 1), date(2024, 2, 1), date(2024, 1, 1)],
            "only the month that changed is announced")
    }

    // MARK: A new calendar

    @Test func aTimeZoneChangeKeepsTheDisplayedMonth() {
        let original = NSTimeZone.default
        defer { NSTimeZone.default = original }
        NSTimeZone.default = TimeZone(identifier: "Europe/Athens")!
        let athens = gregorian(in: "Europe/Athens")
        func day(_ calendar: Calendar, _ month: Int, _ day: Int) -> Date {
            calendar.date(from: DateComponents(year: 2024, month: month, day: day))!
        }
        let view = makeCalendar(
            start: day(athens, 1, 15), end: day(athens, 3, 10), calendar: CalendarView.Style().calendar)
        view.setDisplayDate(day(athens, 3, 5))
        view.layoutIfNeeded()
        #expect(view.displayDate == day(athens, 3, 1))

        // The device moves west. Midnight on 1 March in Athens is 17:00 on 29 February there.
        NSTimeZone.default = TimeZone(identifier: "America/New_York")!
        NotificationCenter.default.post(name: UIApplication.significantTimeChangeNotification, object: nil)

        let newYork = gregorian(in: "America/New_York")
        expectDisplayed(view, day(newYork, 3, 1), title: "March 2024")
        #expect(view.lastNotifiedMonth == day(newYork, 3, 1))
        #expect(
            delegate(of: view).scrolledTo == [day(athens, 1, 1), day(athens, 3, 1)],
            "the month did not change, so it is not announced again")
        view.goToPreviousMonth()
        #expect(view.displayDate == day(newYork, 2, 1))
    }

    @Test func datesMovedToAnotherTimeZoneAreReportedButNotToTheDelegate() {
        let athens = gregorian(in: "Europe/Athens")
        let newYork = gregorian(in: "America/New_York")
        func day(_ calendar: Calendar, _ month: Int, _ day: Int) -> Date {
            calendar.date(from: DateComponents(year: 2024, month: month, day: day))!
        }
        let view = makeCalendar(start: day(athens, 1, 15), end: day(athens, 6, 15), calendar: athens)
        let delegate = delegate(of: view)
        view.setDisplayDate(day(athens, 3, 5))
        view.selectDate(day(athens, 3, 15))
        view.selectDate(day(athens, 6, 15))
        /// What the view and its delegate held each time the view said that its dates had moved.
        var moves: [(selected: [Date], displayed: Date?, deselections: Int)] = []
        view.calendarDidChange = { [unowned view] in
            moves.append((view.selectedDates, view.displayDate, delegate.deselected.count))
        }

        // Reloads that leave every date at its instant are not moves, a new locale included,
        // although it makes another calendar.
        view.reloadData()
        view.style.locale = Locale(identifier: "de_DE")
        dataSource(of: view).start = day(athens, 2, 1)
        view.reloadData()
        #expect(moves.isEmpty)

        // In New York the days are the same ones, at other instants. The range ends at the
        // instant it did, which is 14 June there, so 15 June is dropped.
        view.style.calendar = newYork
        #expect(view.selectedDates == [day(newYork, 3, 15)])
        #expect(view.displayDate == day(newYork, 3, 1))
        #expect(moves.count == 1)
        #expect(moves.first?.selected == [day(newYork, 3, 15)], "the view shows the whole reload by then")
        #expect(moves.first?.displayed == day(newYork, 3, 1))
        #expect(moves.first?.deselections == 0, "and the delegate hears of the dropped day afterwards")
        #expect(delegate.deselected == [day(newYork, 6, 15)])
        #expect(delegate.selected == [day(athens, 3, 15), day(athens, 6, 15)], "no day was selected again")
        #expect(delegate.scrolledTo == [day(athens, 1, 1), day(athens, 3, 1)], "nor a month scrolled to")

        // The same calendar again is no move.
        view.style.calendar = newYork
        view.reloadData()
        #expect(moves.count == 1)
    }

    @Test func aNewCalendarSystemDisplaysTheMonthThatHoldsMostOfTheOldOne() {
        let view = makeCalendar(start: date(2024, 1, 15), end: date(2024, 3, 10))
        view.setDisplayDate(date(2024, 2, 10))
        view.layoutIfNeeded()

        // Bahman 1402 runs from 21 January to 19 February 2024, Esfand from 20 February.
        var persian = Calendar(identifier: .persian)
        persian.timeZone = TimeZone(identifier: "UTC")!
        view.style.calendar = persian
        expectDisplayed(view, date(2024, 1, 21), title: "Bahman 1402")
        #expect(delegate(of: view).scrolledTo.last == date(2024, 1, 21), "another month, so it is announced")

        view.style.calendar = utc
        expectDisplayed(view, date(2024, 2, 1), title: "February 2024")
        #expect(delegate(of: view).scrolledTo.last == date(2024, 2, 1))
    }

    // MARK: A new style or title

    @Test func aNewLocaleRewritesTheTitle() {
        let view = makeCalendar(start: date(2024, 1, 15), end: date(2024, 3, 10))
        #expect(view.headerView.monthLabel.text == "January 2024")
        view.style.locale = Locale(identifier: "de_DE")
        #expect(view.headerView.monthLabel.text == "Januar 2024")
        #expect(view.headerView.dayLabels.first?.text == "Mo", "the stand-alone name, as a column heading")
        #expect(delegate(of: view).scrolledTo == [date(2024, 1, 1)])
    }

    @Test func aReloadAsksTheDataSourceForTheTitleAgain() {
        let view = makeCalendar(start: date(2024, 1, 15), end: date(2024, 3, 10))
        view.setDisplayDate(date(2024, 2, 10))
        dataSource(of: view).header = "Custom"
        view.reloadData()
        #expect(view.headerView.monthLabel.text == "Custom")
        #expect(dataSource(of: view).titledMonths.last == date(2024, 2, 1))
        dataSource(of: view).header = nil
        view.reloadData()
        #expect(view.headerView.monthLabel.text == "February 2024")

        // Another data source brings its own title.
        let other = FixedDataSource(start: date(2024, 1, 15), end: date(2024, 3, 10))
        other.header = "Other"
        retained.objects.append(other)
        view.dataSource = other
        #expect(view.headerView.monthLabel.text == "Other")
    }

    @Test func aNewHeaderHeightKeepsAVerticalCalendarOnItsPage() {
        let view = makeCalendar(start: date(2024, 1, 15), end: date(2024, 3, 10), direction: .vertical)
        view.setDisplayDate(date(2024, 2, 10))
        view.layoutIfNeeded()
        #expect(view.collectionView.contentOffset.y == 340)

        // The header grows, so every page is shorter and February starts higher up.
        view.style.headerHeight = 140
        view.layoutIfNeeded()
        #expect(view.collectionView.bounds.height == 280)
        #expect(view.collectionView.contentOffset == CGPoint(x: 0, y: 280))
        expectDisplayed(view, date(2024, 2, 1), title: "February 2024")
    }

    // MARK: The delegate

    /// Records what the view displays at each callback.
    private final class ObservingDelegate: CalendarViewDelegate {
        /// The display date, the title and the offset at each callback, in order.
        var seen: [String] = []

        private func record(_ callback: String, _ calendar: CalendarView) {
            let month = calendar.displayDate.map { $0.formatted(.iso8601.year().month().day()) } ?? "nil"
            let title = calendar.headerView.monthLabel.text ?? "nil"
            seen.append("\(callback): \(month), \(title), \(Int(calendar.collectionView.contentOffset.x))")
        }

        func calendar(_ calendar: CalendarView, didScrollToMonth date: Date) { record("scrolled", calendar) }
        func calendar(_ calendar: CalendarView, didSelectDate date: Date, withEvents events: [CalendarEvent]) {}
        func calendar(_ calendar: CalendarView, didDeselectDate date: Date) { record("deselected", calendar) }
    }

    @Test func theDelegateHearsOfAReloadOnceTheViewShowsAllOfIt() {
        let view = makeCalendar(start: date(2024, 1, 15), end: date(2024, 3, 10))
        view.setDisplayDate(date(2024, 3, 1))
        view.selectDate(date(2024, 3, 5))
        let observer = ObservingDelegate()
        retained.objects.append(observer)
        view.delegate = observer

        // The selected day and the displayed month both leave the range.
        dataSource(of: view).start = date(2025, 6, 1)
        dataSource(of: view).end = date(2025, 8, 31)
        view.reloadData()
        #expect(observer.seen == ["deselected: 2025-06-01, June 2025, 0", "scrolled: 2025-06-01, June 2025, 0"])
    }

    // MARK: A reload during a scroll

    @Test func aReloadThatKeepsThePageDoesNotMoveADragOrAnAnimation() {
        let view = makeCalendar(start: date(2024, 1, 15), end: date(2024, 3, 10))
        let width = view.collectionView.bounds.width
        let event = CalendarEvent(title: "a", startDate: date(2024, 2, 3), endDate: date(2024, 2, 3, hour: 1))

        // Events arrive while the user drags from January towards February.
        view.scrollViewWillBeginDragging(view.collectionView)
        view.collectionView.contentOffset = CGPoint(x: 0.4 * width, y: 0)
        view.events = [event]
        #expect(view.collectionView.contentOffset.x == 0.4 * width, "the grid stays under the finger")
        #expect(view.displayDate == date(2024, 1, 1))
        view.collectionView.contentOffset = CGPoint(x: width, y: 0)
        view.scrollViewDidEndDecelerating(view.collectionView)
        #expect(view.displayDate == date(2024, 2, 1))

        // A reload half way through an animated scroll to March.
        view.setDisplayDate(date(2024, 3, 1), animated: true)
        view.collectionView.contentOffset = CGPoint(x: 1.5 * width, y: 0)
        view.reloadData()
        #expect(view.collectionView.contentOffset.x == 1.5 * width)
        #expect(view.animationTargetMonth == date(2024, 3, 1), "the animation is still on its way")
        #expect(delegate(of: view).scrolledTo == [date(2024, 1, 1), date(2024, 2, 1)])
        view.collectionView.contentOffset = CGPoint(x: 2 * width, y: 0)
        view.scrollViewDidEndScrollingAnimation(view.collectionView)
        #expect(delegate(of: view).scrolledTo == [date(2024, 1, 1), date(2024, 2, 1), date(2024, 3, 1)])
    }

    @Test func aReloadDuringADragThatCaughtAnAnimationWaitsForTheMonthTheDragEndsOn() {
        let view = makeCalendar(start: date(2024, 1, 15), end: date(2024, 3, 10))
        let width = view.collectionView.bounds.width
        let event = CalendarEvent(title: "a", startDate: date(2024, 2, 3), endDate: date(2024, 2, 3, hour: 1))

        // The user catches the grid on its way to February, and events arrive under the finger.
        view.goToNextMonth()
        view.collectionView.contentOffset = CGPoint(x: 0.6 * width, y: 0)
        view.scrollViewWillBeginDragging(view.collectionView)
        view.events = [event]
        #expect(view.collectionView.contentOffset.x == 0.6 * width, "the grid stays under the finger")
        #expect(delegate(of: view).scrolledTo == [date(2024, 1, 1)], "February is not where the calendar settled")

        // Let go back on January: the calendar never left it, as far as the delegate knows.
        view.collectionView.contentOffset = .zero
        view.scrollViewDidEndDragging(view.collectionView, willDecelerate: true)
        view.reloadData()
        #expect(delegate(of: view).scrolledTo == [date(2024, 1, 1)], "still moving")
        view.scrollViewDidEndDecelerating(view.collectionView)
        expectDisplayed(view, date(2024, 1, 1), title: "January 2024")
        #expect(delegate(of: view).scrolledTo == [date(2024, 1, 1)])

        // The same drag let go on February reports February, once.
        view.goToNextMonth()
        view.scrollViewWillBeginDragging(view.collectionView)
        view.reloadData()
        view.collectionView.contentOffset = CGPoint(x: width, y: 0)
        view.scrollViewDidEndDragging(view.collectionView, willDecelerate: false)
        expectDisplayed(view, date(2024, 2, 1), title: "February 2024")
        #expect(delegate(of: view).scrolledTo == [date(2024, 1, 1), date(2024, 2, 1)])

        // A reload that moves the page under the finger puts a month on screen and says so.
        view.goToNextMonth()
        view.scrollViewWillBeginDragging(view.collectionView)
        dataSource(of: view).start = date(2023, 12, 5)
        view.reloadData()
        expectDisplayed(view, date(2024, 3, 1), title: "March 2024")
        #expect(delegate(of: view).scrolledTo == [date(2024, 1, 1), date(2024, 2, 1), date(2024, 3, 1)])
    }

    @Test func aReloadThatMovesThePageEndsAnAnimatedScrollOnItsMonth() {
        let view = makeCalendar(start: date(2024, 1, 15), end: date(2024, 3, 10))
        let width = view.collectionView.bounds.width
        view.setDisplayDate(date(2024, 3, 1), animated: true)
        view.collectionView.contentOffset = CGPoint(x: 1.5 * width, y: 0)
        #expect(delegate(of: view).scrolledTo == [date(2024, 1, 1)])

        // December joins the grid in mid-animation: March is another page now.
        dataSource(of: view).start = date(2023, 12, 5)
        view.reloadData()
        expectDisplayed(view, date(2024, 3, 1), title: "March 2024")
        #expect(view.collectionView.contentOffset.x == 3 * width)
        #expect(view.animationTargetMonth == nil)
        #expect(
            delegate(of: view).scrolledTo == [date(2024, 1, 1), date(2024, 3, 1)],
            "announced without waiting for the animation")
    }

    @Test func aNewPageSizeEndsAnAnimatedScrollOnItsMonth() {
        let view = makeCalendar(start: date(2024, 1, 15), end: date(2024, 3, 10))
        view.setDisplayDate(date(2024, 3, 1), animated: true)
        view.frame.size = CGSize(width: 280, height: 420)
        view.layoutIfNeeded()
        #expect(view.collectionView.contentOffset == CGPoint(x: 560, y: 0), "March is still the third page")
        #expect(view.animationTargetMonth == nil)
        #expect(delegate(of: view).scrolledTo == [date(2024, 1, 1), date(2024, 3, 1)])
    }

    // MARK: The date arithmetic

    @Test func theNearestMonthOfAGridIsItsOwnOrItsFirstOrLast() throws {
        let grid = try #require(
            MonthGrid(start: date(2024, 1, 15), end: date(2024, 3, 10), calendar: utc, firstWeekday: 2))
        #expect(grid.nearestMonth(to: date(2024, 2, 20, hour: 13)) == date(2024, 2, 1))
        #expect(grid.nearestMonth(to: date(2024, 1, 1)) == date(2024, 1, 1), "a day before the start, in its month")
        #expect(grid.nearestMonth(to: date(2023, 12, 31)) == date(2024, 1, 1))
        #expect(grid.nearestMonth(to: date(1999, 6, 1)) == date(2024, 1, 1))
        #expect(grid.nearestMonth(to: date(2024, 4, 1)) == date(2024, 3, 1))
        #expect(grid.nearestMonth(to: date(2030, 6, 1)) == date(2024, 3, 1))

        let single = try #require(
            MonthGrid(start: date(2024, 2, 5), end: date(2024, 2, 6), calendar: utc, firstWeekday: 1))
        #expect(single.nearestMonth(to: date(2020, 1, 1)) == date(2024, 2, 1))
        #expect(single.nearestMonth(to: date(2030, 1, 1)) == date(2024, 2, 1))
    }

    @Test func aMonthKeepsItsNameInAnotherTimeZone() {
        let athens = gregorian(in: "Europe/Athens")
        let newYork = gregorian(in: "America/New_York")
        let tokyo = gregorian(in: "Asia/Tokyo")
        for month in 1...12 {
            let components = DateComponents(year: 2024, month: month, day: 1)
            let inAthens = athens.date(from: components)!
            #expect(newYork.firstDayOfMonth(matching: inAthens, in: athens) == newYork.date(from: components)!)
            #expect(tokyo.firstDayOfMonth(matching: inAthens, in: athens) == tokyo.date(from: components)!)
            #expect(athens.firstDayOfMonth(matching: tokyo.date(from: components)!, in: tokyo) == inAthens)
            #expect(athens.firstDayOfMonth(matching: inAthens, in: athens) == inAthens)
        }
    }

    @Test func aShortMonthKeepsItsNameInAnotherTimeZone() throws {
        // Pagumen, the thirteenth Ethiopian month, has five or six days.
        var addisAbaba = Calendar(identifier: .ethiopicAmeteMihret)
        addisAbaba.timeZone = TimeZone(identifier: "Africa/Addis_Ababa")!
        var honolulu = addisAbaba
        honolulu.timeZone = TimeZone(identifier: "Pacific/Honolulu")!
        let pagumen = DateComponents(year: 2015, month: 13, day: 1)
        let month = try #require(addisAbaba.date(from: pagumen))
        #expect(addisAbaba.range(of: .day, in: .month, for: month)?.count == 6)
        #expect(honolulu.firstDayOfMonth(matching: month, in: addisAbaba) == honolulu.date(from: pagumen))
        #expect(
            addisAbaba.firstDayOfMonth(matching: try #require(honolulu.date(from: pagumen)), in: honolulu) == month)
    }

    @Test func aMonthOfAnotherCalendarSystemBecomesTheMonthHoldingItsMiddle() {
        var persian = Calendar(identifier: .persian)
        persian.timeZone = TimeZone(identifier: "UTC")!
        // The middle of February 2024 is in Bahman 1402, which starts on 21 January.
        #expect(persian.firstDayOfMonth(matching: date(2024, 2, 1), in: utc) == date(2024, 1, 21))
        // The middle of Bahman, 4 February, is in February.
        #expect(utc.firstDayOfMonth(matching: date(2024, 1, 21), in: persian) == date(2024, 2, 1))
    }

    @Test func onlyTheFirstLetterOfATitleIsCapitalised() {
        let spanish = Locale(identifier: "es_ES")
        #expect("enero de 2024".capitalizingFirstLetter(with: spanish) == "Enero de 2024")
        #expect("Enero de 2024".capitalizingFirstLetter(with: spanish) == "Enero de 2024")
        #expect("2024年1月".capitalizingFirstLetter(with: Locale(identifier: "ja_JP")) == "2024年1月")
        #expect("".capitalizingFirstLetter(with: spanish) == "")
        // Turkish has a dotted capital I.
        #expect("ilkbahar".capitalizingFirstLetter(with: Locale(identifier: "tr_TR")) == "İlkbahar")
        #expect("ilkbahar".capitalizingFirstLetter(with: Locale(identifier: "en_US")) == "Ilkbahar")
        // Georgian has capitals only for text set all in capitals, so a title keeps its letter.
        #expect("იანვარი, 2024".capitalizingFirstLetter(with: Locale(identifier: "ka_GE")) == "იანვარი, 2024")
        // A letter that is two in one has a title case of its own, between lower and upper.
        #expect("ǆep".capitalizingFirstLetter(with: Locale(identifier: "hr_HR")) == "ǅep")
    }
}
