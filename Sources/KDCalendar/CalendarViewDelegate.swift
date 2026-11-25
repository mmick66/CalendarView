import Foundation

/// Receives scrolling and selection events from a ``CalendarView``.
///
/// Dates are the start of the day in ``CalendarView/calendar``; the month passed to
/// `didScrollToMonth` is the first day of that month.
@MainActor
public protocol CalendarViewDelegate: AnyObject {
    /// The calendar settled on a new month, or displayed its first one.
    ///
    /// Sent once per month, however the calendar got there: a swipe,
    /// ``CalendarView/setDisplayDate(_:animated:)``, or a reload after which the month it displayed
    /// is no longer in the data source's range, so that it moved to the nearest month that is. A
    /// reload that keeps the month sends nothing.
    func calendar(_ calendar: CalendarView, didScrollToMonth date: Date)
    /// A day was selected, by a tap or by ``CalendarView/selectDate(_:)``.
    func calendar(_ calendar: CalendarView, didSelectDate date: Date, withEvents events: [CalendarEvent])
    /// Whether a day in range may be selected. Defaults to `true`.
    ///
    /// Asked when a day is tapped or selected in code, and also whenever a day is drawn, so that
    /// VoiceOver announces the days refused as dimmed: for each day of a month as its cells are
    /// laid out, after a reload and while scrolling, and again for the days on screen at the
    /// layout that follows a change of the selection. Keep the answer quick and free of side
    /// effects: an alert shown from here would appear for every refused day of the month.
    ///
    /// An answer that depends on the selection, such as a limit of three days, is therefore kept
    /// up to date. When the answers change for any other reason, call
    /// ``CalendarView/reloadData()``; until then a tap follows the new answer while VoiceOver
    /// keeps the old one.
    func calendar(_ calendar: CalendarView, canSelectDate date: Date) -> Bool
    /// A day was deselected, by a tap or by ``CalendarView/deselectDate(_:)``.
    func calendar(_ calendar: CalendarView, didDeselectDate date: Date)
    /// A day was long-pressed. `events` is `nil` when the day has none.
    ///
    /// Unlike a tap, a long press is reported for every day of the displayed months: also for the
    /// days before the data source's `startDate()` and after its `endDate()`, and for the days
    /// `canSelectDate` refuses, none of which can be selected or highlighted. That is deliberate:
    /// apps add an event to any day this way. Check ``CalendarView/dateRange`` to ignore the days
    /// out of range. The days of the neighbouring months that
    /// ``CalendarView/Style/showAdjacentDays`` shows are never reported.
    func calendar(_ calendar: CalendarView, didLongPressDate date: Date, withEvents events: [CalendarEvent]?)
    /// A range of days was selected, by the second tap in ``CalendarView/SelectionMode/range`` mode or
    /// by ``CalendarView/selectRange(_:)``. `selectedDates` holds every selectable day in it.
    func calendar(_ calendar: CalendarView, didSelectRange range: ClosedRange<Date>)
    /// A style for one day, or `nil` for the calendar's own ``CalendarView/style``. Use it to colour
    /// a holiday, grey out days that `canSelectDate` refuses, or change a single day's font.
    func calendar(_ calendar: CalendarView, styleForDate date: Date) -> CalendarView.Style?
}

extension CalendarViewDelegate {
    /// `true`: every day in range may be selected.
    public func calendar(_ calendar: CalendarView, canSelectDate date: Date) -> Bool { true }
    /// Does nothing.
    public func calendar(_ calendar: CalendarView, didDeselectDate date: Date) {}
    /// Does nothing.
    public func calendar(_ calendar: CalendarView, didLongPressDate date: Date, withEvents events: [CalendarEvent]?) {}
    /// Does nothing.
    public func calendar(_ calendar: CalendarView, didSelectRange range: ClosedRange<Date>) {}
    /// `nil`: every day uses the calendar's own style.
    public func calendar(_ calendar: CalendarView, styleForDate date: Date) -> CalendarView.Style? { nil }
}
