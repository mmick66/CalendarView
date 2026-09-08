import SwiftUI
import Testing
import UIKit

@testable import KDCalendar

/// Dark mode, Dynamic Type, accessibility, scrolling control and the SwiftUI wrapper.
@Suite(.serialized)
@MainActor
struct PlatformTests {

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

    static let window: UIWindow = {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 350, height: 600))
        window.isHidden = false
        return window
    }()

    final class Retained {
        var objects: [AnyObject] = []
    }
    let retained = Retained()

    init() {
        Self.window.rootViewController = nil
        Self.window.subviews.forEach { $0.removeFromSuperview() }
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        utc.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func makeCalendar(start: Date, end: Date) -> CalendarView {
        var style = CalendarView.Style()
        style.locale = Locale(identifier: "en_US")
        style.calendar = utc
        let view = CalendarView(frame: CGRect(x: 0, y: 0, width: 350, height: 420))
        view.style = style
        let dataSource = FixedDataSource(start: start, end: end)
        retained.objects.append(dataSource)
        view.dataSource = dataSource
        Self.window.addSubview(view)
        view.layoutIfNeeded()
        return view
    }

    private func cell(_ view: CalendarView, _ indexPath: IndexPath) -> CalendarDayCell? {
        view.collectionView.cellForItem(at: indexPath) as? CalendarDayCell
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

    @Test func todayIsSpokenAsSuch() {
        let now = Date()
        let local = Calendar.current
        var style = CalendarView.Style()
        style.calendar = local
        style.locale = Locale(identifier: "en_US")
        let view = CalendarView(frame: CGRect(x: 0, y: 0, width: 350, height: 420))
        view.style = style
        let dataSource = FixedDataSource(
            start: local.date(byAdding: .day, value: -3, to: now)!, end: local.date(byAdding: .day, value: 3, to: now)!)
        retained.objects.append(dataSource)
        view.dataSource = dataSource
        Self.window.addSubview(view)
        view.layoutIfNeeded()
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
        var style = CalendarView.Style()
        style.calendar = utc
        style.locale = Locale(identifier: "en_US")
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
}
