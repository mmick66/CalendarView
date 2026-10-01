import Foundation

/// Receives scrolling and selection events from a ``CalendarView``.
///
/// Dates are the start of the day in ``CalendarView/calendar``; the month passed to
/// `didScrollToMonth` is the first day of that month.
@MainActor
public protocol CalendarViewDelegate: AnyObject {
    /// The calendar settled on a new month, or displayed its first one.
    func calendar(_ calendar: CalendarView, didScrollToMonth date: Date)
    /// A day was selected, by a tap or by ``CalendarView/selectDate(_:)``.
    func calendar(_ calendar: CalendarView, didSelectDate date: Date, withEvents events: [CalendarEvent])
    /// Whether a day in range may be selected. Defaults to `true`.
    func calendar(_ calendar: CalendarView, canSelectDate date: Date) -> Bool
    /// A day was deselected, by a tap or by ``CalendarView/deselectDate(_:)``.
    func calendar(_ calendar: CalendarView, didDeselectDate date: Date)
    /// A day was long-pressed. `events` is `nil` when the day has none.
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
