import SwiftUI
import Testing
import UIKit

@testable import KDCalendar

/// Dark mode, Dynamic Type, accessibility, scrolling control and the SwiftUI wrapper.
@Suite(.serialized)
@MainActor
struct PlatformTests: CalendarFixture {

    static let window = makeWindow(height: 600)
    let retained = Retained()

    init() {
        Self.resetWindow()
    }

    @Test func defaultColoursAdaptToDarkMode() {
        let style = CalendarView.Style.default
        let light = UITraitCollection(userInterfaceStyle: .light)
        let dark = UITraitCollection(userInterfaceStyle: .dark)
        #expect(
            style.headerBackgroundColor.resolvedColor(with: light)
                != style.headerBackgroundColor.resolvedColor(with: dark))
        #expect(style.cellColorDefault.resolvedColor(with: light) != style.cellColorDefault.resolvedColor(with: dark))
        #expect(
            style.cellSelectedTextColor.resolvedColor(with: light)
                != style.cellSelectedTextColor.resolvedColor(with: dark))
        #expect(CalendarView.Style() == CalendarView.Style.default, "two default styles are equal")
    }

    @Test func defaultFontsScaleWithDynamicType() {
        let style = CalendarView.Style.default
        let large = UITraitCollection(preferredContentSizeCategory: .accessibilityExtraLarge)
        let scaled = UIFontMetrics(forTextStyle: .body).scaledFont(
            for: UIFont.systemFont(ofSize: 17), compatibleWith: large)
        #expect(scaled.pointSize > style.cellFont.pointSize)
        let view = makeCalendar(start: date(2024, 1, 1), end: date(2024, 1, 31))
        #expect(cell(view, IndexPath(item: 0, section: 0))?.textLabel.adjustsFontForContentSizeCategory == true)
        #expect(view.headerView.monthLabel.adjustsFontForContentSizeCategory == true)
    }

    @Test func dayCellsDescribeThemselvesToVoiceOver() {
        let view = makeCalendar(start: date(2024, 1, 10), end: date(2024, 1, 20))
        view.events = [
            CalendarEvent(title: "a", startDate: date(2024, 1, 15), endDate: date(2024, 1, 15).addingTimeInterval(3600))
        ]
        view.layoutIfNeeded()
        // January 2024 starts on a Monday, so day n is item n - 1.
        let fifteenth = cell(view, IndexPath(item: 14, section: 0))
        #expect(fifteenth?.isAccessibilityElement == true)
        #expect(fifteenth?.accessibilityLabel == "Monday, January 15, 2024, 1 event")
        #expect(fifteenth?.accessibilityTraits.contains(.button) == true)
        #expect(fifteenth?.accessibilityTraits.contains(.notEnabled) == false)
        let outOfRange = cell(view, IndexPath(item: 2, section: 0))
        #expect(outOfRange?.accessibilityLabel == "Wednesday, January 3, 2024")
        #expect(outOfRange?.accessibilityTraits.contains(.notEnabled) == true)
        view.selectDate(date(2024, 1, 15))
        #expect(fifteenth?.accessibilityTraits.contains(.selected) == true)
        #expect(view.headerView.monthLabel.accessibilityTraits.contains(.header) == true)
    }

    @Test func reusedCellsDoNotKeepTheirVoiceOverLabelAsAdjacentDays() {
        let view = makeCalendar(start: date(2024, 1, 1), end: date(2024, 3, 31))
        view.style.showAdjacentDays = true
        view.layoutIfNeeded()
        // January 2024 starts on a Monday, so the 5th is item 4.
        let reused = cell(view, IndexPath(item: 4, section: 0))!
        #expect(reused.accessibilityLabel == "Friday, January 5, 2024")
        reused.prepareForReuse()
        #expect(reused.accessibilityLabel == nil)
        reused.configuration.isAdjacent = true
        #expect(reused.isAccessibilityElement == false, "adjacent days cannot be selected")
        reused.configuration.isAdjacent = false
        #expect(reused.isAccessibilityElement == true)
        // Scrolling recycles in-month cells as adjacent days of the next months.
        for month in [2, 3] {
            view.setDisplayDate(date(2024, month, 1))
            view.layoutIfNeeded()
        }
        let adjacent = view.collectionView.visibleCells.compactMap { $0 as? CalendarDayCell }.filter(
            \.configuration.isAdjacent)
        #expect(!adjacent.isEmpty)
        for dayCell in adjacent {
            #expect(dayCell.accessibilityLabel == nil)
            #expect(dayCell.isAccessibilityElement == false)
        }
    }

    @Test func todayIsSpokenAsSuch() {
        let now = Date()
        let local = Calendar.current
        let view = makeCalendar(
            start: local.date(byAdding: .day, value: -3, to: now)!, end: local.date(byAdding: .day, value: 3, to: now)!,
            calendar: local)
        view.setDisplayDate(now)
        view.layoutIfNeeded()
        let today = cell(view, view.indexPathForDate(now)!)
        #expect(today?.accessibilityLabel?.hasSuffix(", Today") == true)
    }

    @Test func scrollingCanBeDisabled() {
        // Issue #126.
        let view = makeCalendar(start: date(2024, 1, 1), end: date(2024, 3, 31))
        #expect(view.isScrollEnabled == true)
        view.isScrollEnabled = false
        #expect(view.collectionView.isScrollEnabled == false)
        view.setDisplayDate(date(2024, 2, 1))
        #expect(view.displayDate == date(2024, 2, 1), "programmatic scrolling still works")
    }

    // MARK: SwiftUI

    /// Holds a selection for a `Binding`, standing in for `@State`.
    final class SelectionBox: @unchecked Sendable {
        var dates: [Date] = []
        var changes = 0
        var binding: Binding<[Date]> {
            Binding(
                get: { self.dates },
                set: {
                    self.dates = $0; self.changes += 1
                })
        }
    }

    private func findCalendarView(in view: UIView) -> CalendarView? {
        if let calendar = view as? CalendarView { return calendar }
        for subview in view.subviews {
            if let found = findCalendarView(in: subview) { return found }
        }
        return nil
    }

    @Test func swiftUIWrapperHostsACalendarAndReportsSelection() {
        let box = SelectionBox()
        let style = makeStyle()
        let range = date(2024, 1, 1)...date(2024, 3, 31)
        let host = UIHostingController(
            rootView: KDCalendarView(range: range, selection: box.binding)
                .calendarStyle(style)
                .allowsMultipleSelection(false)
                .events([CalendarEvent(title: "a", startDate: date(2024, 1, 5), endDate: date(2024, 1, 6))]))
        Self.window.rootViewController = host
        host.view.frame = Self.window.bounds
        host.view.layoutIfNeeded()

        let calendar = findCalendarView(in: host.view)
        #expect(calendar != nil)
        guard let calendar else { return }
        #expect(calendar.dateRange == range)
        #expect(calendar.multipleSelectionEnable == false)
        #expect(calendar.style == style)
        #expect(calendar.events.count == 1)
        #expect(calendar.headerView.monthLabel.text == "January 2024")

        // A selection in the view flows into the binding.
        calendar.selectDate(date(2024, 1, 10))
        #expect(box.dates == [date(2024, 1, 10)])
        #expect(box.changes == 1)

        // A new value from SwiftUI flows into the view.
        box.dates = [date(2024, 2, 14)]
        host.rootView = KDCalendarView(range: range, selection: box.binding).calendarStyle(style)
            .allowsMultipleSelection(false)
        host.view.layoutIfNeeded()
        #expect(calendar.selectedDates == [date(2024, 2, 14)])
        #expect(box.dates == [date(2024, 2, 14)], "the sync does not echo back into the binding")
    }

    @Test func swiftUIRangeChangeKeepsTheSelectedDayHighlighted() {
        let box = SelectionBox()
        let style = makeStyle()
        let host = UIHostingController(
            rootView: KDCalendarView(range: date(2024, 3, 1)...date(2024, 4, 30), selection: box.binding)
                .calendarStyle(style))
        Self.window.rootViewController = host
        host.view.frame = Self.window.bounds
        host.view.layoutIfNeeded()
        guard let calendar = findCalendarView(in: host.view) else {
            Issue.record("no calendar view hosted")
            return
        }
        calendar.selectDate(date(2024, 3, 15))

        // An earlier start adds February in front of March.
        host.rootView = KDCalendarView(range: date(2024, 2, 10)...date(2024, 4, 30), selection: box.binding)
            .calendarStyle(style)
        host.view.layoutIfNeeded()
        let indexPath = calendar.indexPathForDate(date(2024, 3, 15))!
        #expect(indexPath.section == 1)
        #expect(calendar.selectedDates == [date(2024, 3, 15)])
        #expect(calendar.collectionView.indexPathsForSelectedItems == [indexPath])
        #expect(box.dates == [date(2024, 3, 15)])
    }

    @Test func swiftUIRangeChangeDropsTheLeftDaysFromTheBinding() async {
        let box = SelectionBox()
        let style = makeStyle()
        var range = date(2024, 3, 1)...date(2024, 4, 30)
        var mode = CalendarView.SelectionMode.multiple
        func view() -> KDCalendarView {
            KDCalendarView(range: range, selection: box.binding).calendarStyle(style).selectionMode(mode)
        }
        guard let hosted = hostCalendar(view()) else { return }
        let (host, calendar) = hosted

        // A range that now ends in March leaves 20 April out of both the view and the binding.
        calendar.selectDate(date(2024, 3, 15))
        calendar.selectDate(date(2024, 4, 20))
        #expect(box.dates == [date(2024, 3, 15), date(2024, 4, 20)])
        range = date(2024, 3, 1)...date(2024, 3, 31)
        host.rootView = view()
        host.view.layoutIfNeeded()
        await settle()
        #expect(calendar.selectedDates == [date(2024, 3, 15)])
        #expect(box.dates == [date(2024, 3, 15)])

        // A picked range is cut at the new end.
        range = date(2024, 3, 1)...date(2024, 4, 30)
        mode = .range
        box.dates = []
        host.rootView = view()
        host.view.layoutIfNeeded()
        calendar.selectDate(date(2024, 3, 28))
        calendar.selectDate(date(2024, 4, 2))
        #expect(box.dates.count == 6)
        range = date(2024, 3, 1)...date(2024, 3, 30)
        host.rootView = view()
        host.view.layoutIfNeeded()
        await settle()
        let kept = (28...30).map { date(2024, 3, $0) }
        #expect(calendar.selectedDates == kept)
        #expect(box.dates == kept)
    }

    @Test func swiftUIModifiersReachTheCalendar() async {
        let box = SelectionBox()
        let style = makeStyle()
        var holiday = style
        holiday.cellColorDefault = .systemPink
        let scrolled = SelectionBox()
        let pressed = SelectionBox()
        let range = date(2024, 1, 1)...date(2024, 3, 31)
        let events = [CalendarEvent(title: "a", startDate: date(2024, 2, 5), endDate: date(2024, 2, 6))]

        let host = UIHostingController(
            rootView: KDCalendarView(range: range, selection: box.binding)
                .calendarStyle(style)
                .direction(.vertical)
                .selectionMode(.range)
                .allowsDeselection(false)
                .marksWeekends(false)
                .scrollEnabled(false)
                .events(events)
                .displayDate(date(2024, 2, 14))
                .canSelect { [utc] in utc.component(.day, from: $0) != 13 }
                .styleForDate { [utc] in utc.component(.day, from: $0) == 14 ? holiday : nil }
                .onScrollToMonth { scrolled.dates.append($0) }
                .onLongPress { date, _ in pressed.dates.append(date) })
        Self.window.rootViewController = host
        host.view.frame = Self.window.bounds
        host.view.layoutIfNeeded()

        guard let calendar = findCalendarView(in: host.view) else {
            Issue.record("no calendar view hosted")
            return
        }
        #expect(calendar.direction == .vertical)
        #expect(calendar.selectionMode == .range)
        #expect(calendar.enableDeselection == false)
        #expect(calendar.marksWeekends == false)
        #expect(calendar.isScrollEnabled == false)
        #expect(calendar.events.count == 1)
        #expect(calendar.displayDate == date(2024, 2, 1))
        await settle()
        #expect(scrolled.dates == [date(2024, 2, 1)], "the display date applies before the first month is announced")
        #expect(calendar.shouldSelect(calendar.indexPathForDate(date(2024, 2, 13))!) == false)
        #expect(calendar.shouldSelect(calendar.indexPathForDate(date(2024, 2, 12))!) == true)
        calendar.layoutIfNeeded()
        let fourteenth =
            calendar.collectionView.cellForItem(at: calendar.indexPathForDate(date(2024, 2, 14))!) as? CalendarDayCell
        #expect(fourteenth?.dayBackgroundView.backgroundColor == .systemPink)
        calendar.delegate?.calendar(calendar, didLongPressDate: date(2024, 2, 20), withEvents: nil)
        #expect(pressed.dates == [date(2024, 2, 20)])

        // A range picked in the view reaches the binding as every day in it.
        calendar.selectDate(date(2024, 2, 5))
        calendar.selectDate(date(2024, 2, 7))
        #expect(box.dates == [date(2024, 2, 5), date(2024, 2, 6), date(2024, 2, 7)])

        // New range and events from SwiftUI reach the view.
        host.rootView = KDCalendarView(range: date(2024, 1, 1)...date(2024, 6, 30), selection: box.binding)
            .calendarStyle(style)
            .events(events + [CalendarEvent(title: "b", startDate: date(2024, 3, 1), endDate: date(2024, 3, 2))])
        host.view.layoutIfNeeded()
        #expect(calendar.numberOfSections(in: calendar.collectionView) == 6)
        #expect(calendar.events.count == 2)
        #expect(calendar.direction == .horizontal, "modifiers not repeated fall back to their defaults")
    }

    @Test func swiftUIDisplayDateChangeReportsTheMonthAfterTheViewUpdate() async {
        let box = SelectionBox()
        let scrolled = SelectionBox()
        let style = makeStyle()
        var displayDate = date(2024, 1, 10)
        func view() -> KDCalendarView {
            KDCalendarView(range: date(2024, 1, 1)...date(2024, 6, 30), selection: box.binding)
                .calendarStyle(style)
                .displayDate(displayDate)
                .onScrollToMonth { scrolled.dates.append($0) }
        }
        guard let hosted = hostCalendar(view()) else { return }
        let (host, calendar) = hosted
        await settle()
        scrolled.dates = []

        // The month is applied during the update, but announced only once the update has ended,
        // so the action may change state.
        displayDate = date(2024, 4, 20)
        host.rootView = view()
        host.view.layoutIfNeeded()
        #expect(calendar.displayDate == date(2024, 4, 1))
        #expect(scrolled.dates == [])
        await settle()
        #expect(scrolled.dates == [date(2024, 4, 1)])

        // A scroll outside a view update is still announced right away.
        calendar.setDisplayDate(date(2024, 5, 3))
        #expect(scrolled.dates == [date(2024, 4, 1), date(2024, 5, 1)])
    }

    /// Hosts `view` in the window and returns the host with the calendar inside it.
    private func hostCalendar(_ view: KDCalendarView) -> (UIHostingController<KDCalendarView>, CalendarView)? {
        let host = UIHostingController(rootView: view)
        Self.window.rootViewController = host
        host.view.frame = Self.window.bounds
        host.view.layoutIfNeeded()
        guard let calendar = findCalendarView(in: host.view) else {
            Issue.record("no calendar view hosted")
            return nil
        }
        return (host, calendar)
    }

    /// Lets work queued on the main actor run, such as the wrapper correcting its binding.
    private func settle() async {
        for _ in 0..<5 { await Task.yield() }
    }

    @Test func swiftUIRangeSetFromTheBindingSelectsEveryDayInIt() async {
        let box = SelectionBox()
        let style = makeStyle()
        let range = date(2024, 1, 1)...date(2024, 3, 31)
        func view() -> KDCalendarView {
            KDCalendarView(range: range, selection: box.binding).calendarStyle(style).selectionMode(.range)
        }
        guard let hosted = hostCalendar(view()) else { return }
        let (host, calendar) = hosted

        // A whole week, as the demo's "Select this week" sets it.
        let week = (8...14).map { date(2024, 1, $0) }
        box.dates = week
        host.rootView = view()
        host.view.layoutIfNeeded()
        await settle()
        #expect(calendar.selectedDates == week)
        #expect(box.dates == week)
        #expect(box.changes == 0, "a value the view shows as given is left alone")

        // The ends of a range fill in, and the binding learns the days between them.
        box.dates = [date(2024, 2, 9), date(2024, 2, 5)]
        host.rootView = view()
        host.view.layoutIfNeeded()
        await settle()
        let filled = (5...9).map { date(2024, 2, $0) }
        #expect(calendar.selectedDates == filled)
        #expect(box.dates == filled)
        #expect(box.changes == 1)

        // The range is complete: the next tap starts a new one and the one after completes it.
        calendar.selectDate(date(2024, 2, 20))
        #expect(box.dates == [date(2024, 2, 20)])
        calendar.selectDate(date(2024, 2, 22))
        #expect(box.dates == (20...22).map { date(2024, 2, $0) })
    }

    @Test func swiftUIBindingIsCorrectedToWhatTheViewShows() async {
        let box = SelectionBox()
        let style = makeStyle()
        let range = date(2024, 1, 1)...date(2024, 3, 31)
        var mode = CalendarView.SelectionMode.single
        func view() -> KDCalendarView {
            KDCalendarView(range: range, selection: box.binding)
                .calendarStyle(style)
                .selectionMode(mode)
                .canSelect { [utc] in utc.component(.day, from: $0) != 13 }
        }
        guard let hosted = hostCalendar(view()) else { return }
        let (host, calendar) = hosted

        // Single mode keeps the last day, not each one in turn.
        box.dates = [date(2024, 1, 8), date(2024, 1, 10), date(2024, 1, 12)]
        host.rootView = view()
        host.view.layoutIfNeeded()
        await settle()
        #expect(calendar.selectedDates == [date(2024, 1, 12)])
        #expect(box.dates == [date(2024, 1, 12)])

        // A correction gives way to a newer value.
        box.dates = [date(2024, 1, 8), date(2024, 1, 10)]
        host.rootView = view()
        host.view.layoutIfNeeded()
        box.dates = [date(2024, 1, 20)]
        await settle()
        #expect(box.dates == [date(2024, 1, 20)])

        // Refused days are dropped; a time of day alone is not worth a correction.
        mode = .multiple
        let changes = box.changes
        let morning = utc.date(byAdding: .hour, value: 9, to: date(2024, 1, 5))!
        box.dates = [morning]
        host.rootView = view()
        host.view.layoutIfNeeded()
        await settle()
        #expect(calendar.selectedDates == [date(2024, 1, 5)])
        #expect(box.changes == changes)
        box.dates = [morning, date(2024, 1, 13)]
        host.rootView = view()
        host.view.layoutIfNeeded()
        await settle()
        #expect(calendar.selectedDates == [date(2024, 1, 5)])
        #expect(box.dates == [date(2024, 1, 5)])
    }

    @Test func swiftUIModeChangeLeavesTheBindingWithTheDaysKept() async {
        let box = SelectionBox()
        let style = makeStyle()
        let range = date(2024, 1, 1)...date(2024, 3, 31)
        var mode = CalendarView.SelectionMode.multiple
        func view() -> KDCalendarView {
            KDCalendarView(range: range, selection: box.binding).calendarStyle(style).selectionMode(mode)
        }
        guard let hosted = hostCalendar(view()) else { return }
        let (host, calendar) = hosted

        // As in the demo: three days in multiple mode, then the picker switches to single.
        for day in [8, 10, 12] { calendar.selectDate(date(2024, 1, day)) }
        #expect(box.dates == [date(2024, 1, 8), date(2024, 1, 10), date(2024, 1, 12)])
        mode = .single
        host.rootView = view()
        host.view.layoutIfNeeded()
        await settle()
        #expect(calendar.selectedDates == [date(2024, 1, 12)])
        #expect(box.dates == [date(2024, 1, 12)])

        // Range mode starts clean rather than filling the days in between.
        mode = .multiple
        host.rootView = view()
        host.view.layoutIfNeeded()
        for day in [8, 10] { calendar.selectDate(date(2024, 1, day)) }
        #expect(box.dates == [date(2024, 1, 12), date(2024, 1, 8), date(2024, 1, 10)])
        mode = .range
        host.rootView = view()
        host.view.layoutIfNeeded()
        await settle()
        #expect(calendar.selectedDates == [])
        #expect(box.dates == [])

        // A selection that comes with the new mode is applied in its shape.
        mode = .multiple
        box.dates = [date(2024, 2, 9), date(2024, 2, 5)]
        host.rootView = view()
        host.view.layoutIfNeeded()
        await settle()
        #expect(calendar.selectedDates == [date(2024, 2, 9), date(2024, 2, 5)])
        mode = .range
        box.dates = [date(2024, 2, 20), date(2024, 2, 22)]
        host.rootView = view()
        host.view.layoutIfNeeded()
        await settle()
        #expect(calendar.selectedDates == (20...22).map { date(2024, 2, $0) })
        #expect(box.dates == (20...22).map { date(2024, 2, $0) })
    }
}
