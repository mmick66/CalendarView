import Testing
import UIKit

@testable import KDCalendar

/// A Gregorian calendar in UTC.
///
/// Tests build their dates through it so they do not depend on the machine's time zone.
private let utcCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

/// Dates in a UTC Gregorian calendar, for suites with or without a view.
protocol UTCDates {}

extension UTCDates {
    /// A Gregorian calendar in UTC.
    var utc: Calendar { utcCalendar }

    /// The given day, at midnight or `hour` in ``utc``.
    func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0) -> Date {
        utc.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }
}

/// Lays out calendars in a window for a suite.
///
/// A suite keeps its own window, so suites running side by side never clear each other's views, and
/// keeps what the view holds weakly in ``retained``.
@MainActor
protocol CalendarFixture: UTCDates {
    /// The suite's window, made with ``makeWindow(height:)``.
    static var window: UIWindow { get }
    /// The data sources and delegates of the suite's calendars.
    var retained: Retained { get }
}

/// The view holds its data source and delegate weakly, so each test keeps them here.
final class Retained {
    var objects: [AnyObject] = []
}

/// Fixed-range data source; every test controls its own start and end.
final class FixedDataSource: CalendarViewDataSource {
    var start: Date
    var end: Date
    var header: String?
    /// How many times the view asked for the start or the end.
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
    func headerString(_ date: Date) -> String? { header }
}

/// Records every delegate callback; `canSelect` and `styleForDate` answer the view's questions.
final class RecordingDelegate: CalendarViewDelegate {
    var scrolledTo: [Date] = []
    var selected: [Date] = []
    var deselected: [Date] = []
    /// The view's selection at each `didDeselectDate`.
    var selectionWhenDeselected: [[Date]] = []
    var ranges: [ClosedRange<Date>] = []
    var longPressed: [(Date, [CalendarEvent]?)] = []
    var canSelect: (Date) -> Bool = { _ in true }
    var styleForDate: (Date) -> CalendarView.Style? = { _ in nil }

    func calendar(_ calendar: CalendarView, didScrollToMonth date: Date) { scrolledTo.append(date) }
    func calendar(_ calendar: CalendarView, didSelectDate date: Date, withEvents events: [CalendarEvent]) {
        selected.append(date)
    }
    func calendar(_ calendar: CalendarView, canSelectDate date: Date) -> Bool { canSelect(date) }
    func calendar(_ calendar: CalendarView, didDeselectDate date: Date) {
        deselected.append(date)
        selectionWhenDeselected.append(calendar.selectedDates)
    }
    func calendar(_ calendar: CalendarView, didLongPressDate date: Date, withEvents events: [CalendarEvent]?) {
        longPressed.append((date, events))
    }
    func calendar(_ calendar: CalendarView, didSelectRange range: ClosedRange<Date>) { ranges.append(range) }
    func calendar(_ calendar: CalendarView, styleForDate date: Date) -> CalendarView.Style? { styleForDate(date) }
}

extension CalendarFixture {
    /// A shown window for a suite's ``window``.
    static func makeWindow(height: CGFloat = 500) -> UIWindow {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 350, height: height))
        window.isHidden = false
        return window
    }

    /// Empties the window before a test adds its calendar.
    static func resetWindow() {
        window.rootViewController = nil
        window.subviews.forEach { $0.removeFromSuperview() }
    }

    /// A style in `calendar` and `locale`, starting the week on `firstWeekday`.
    func makeStyle(
        firstWeekday: CalendarView.Style.FirstWeekday = .monday, calendar: Calendar = utcCalendar,
        locale: Locale = Locale(identifier: "en_US")
    ) -> CalendarView.Style {
        var style = CalendarView.Style()
        style.firstWeekday = firstWeekday
        style.locale = locale
        style.calendar = calendar
        return style
    }

    /// A laid-out calendar from `start` to `end` inside the window, so the collection view has
    /// real cells to inspect, with a ``FixedDataSource`` and a ``RecordingDelegate``.
    func makeCalendar(
        start: Date, end: Date, firstWeekday: CalendarView.Style.FirstWeekday = .monday,
        calendar: Calendar = utcCalendar, locale: Locale = Locale(identifier: "en_US"),
        direction: UICollectionView.ScrollDirection = .horizontal,
        frame: CGRect = CGRect(x: 0, y: 0, width: 350, height: 420)
    ) -> CalendarView {
        let view = CalendarView(frame: frame)
        view.style = makeStyle(firstWeekday: firstWeekday, calendar: calendar, locale: locale)
        view.direction = direction
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

    func dataSource(of view: CalendarView) -> FixedDataSource {
        view.dataSource as! FixedDataSource
    }

    func delegate(of view: CalendarView) -> RecordingDelegate {
        view.delegate as! RecordingDelegate
    }

    /// The day cell at `indexPath`, if the collection view has laid it out.
    func cell(_ view: CalendarView, _ indexPath: IndexPath) -> CalendarDayCell? {
        view.collectionView.cellForItem(at: indexPath) as? CalendarDayCell
    }
}
