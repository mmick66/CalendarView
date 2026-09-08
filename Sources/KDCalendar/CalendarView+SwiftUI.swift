//
//  CalendarView+SwiftUI.swift
//  KDCalendar
//
//  A SwiftUI wrapper around CalendarView.
//

#if canImport(SwiftUI)
import SwiftUI

/// A SwiftUI view that shows a ``CalendarView``.
///
/// ```swift
/// @State private var selection: [Date] = []
///
/// KDCalendarView(range: start...end, selection: $selection)
///     .calendarStyle(style)
///     .events(events)
///     .onScrollToMonth { month in title = month.formatted(.dateTime.month().year()) }
/// ```
///
/// The selection binding is two-way: taps update it, and assigning to it selects or deselects
/// days in the view.
public struct KDCalendarView: UIViewRepresentable {

    /// The first and last selectable days.
    public var range: ClosedRange<Date>
    /// The selected days, in selection order.
    @Binding public var selection: [Date]

    var style = CalendarView.Style.default
    var direction = UICollectionView.ScrollDirection.horizontal
    var selectionMode = CalendarView.SelectionMode.multiple
    var allowsDeselection = true
    var marksWeekends = true
    var isScrollEnabled = true
    var events: [CalendarEvent] = []
    var displayDate: Date?
    var canSelect: ((Date) -> Bool)?
    var styleForDate: ((Date) -> CalendarView.Style?)?
    var onScrollToMonth: ((Date) -> Void)?
    var onLongPress: ((Date, [CalendarEvent]) -> Void)?

    /// Creates a calendar showing every month between the two ends of `range`.
    public init(range: ClosedRange<Date>, selection: Binding<[Date]>) {
        self.range = range
        self._selection = selection
    }

    // MARK: Modifiers

    /// The look of the calendar.
    public func calendarStyle(_ style: CalendarView.Style) -> Self {
        var copy = self
        copy.style = style
        return copy
    }

    /// The scrolling axis.
    public func direction(_ direction: UICollectionView.ScrollDirection) -> Self {
        var copy = self
        copy.direction = direction
        return copy
    }

    /// Whether more than one day can be selected. Shorthand for `.single` or `.multiple`.
    public func allowsMultipleSelection(_ allows: Bool) -> Self {
        selectionMode(allows ? .multiple : .single)
    }

    /// How taps combine into a selection: one day, any number of days, or a range.
    public func selectionMode(_ mode: CalendarView.SelectionMode) -> Self {
        var copy = self
        copy.selectionMode = mode
        return copy
    }

    /// Whether tapping a selected day deselects it.
    public func allowsDeselection(_ allows: Bool) -> Self {
        var copy = self
        copy.allowsDeselection = allows
        return copy
    }

    /// Whether weekend days use the weekend text colour.
    public func marksWeekends(_ marks: Bool) -> Self {
        var copy = self
        copy.marksWeekends = marks
        return copy
    }

    /// Whether the user can scroll between months.
    public func scrollEnabled(_ enabled: Bool) -> Self {
        var copy = self
        copy.isScrollEnabled = enabled
        return copy
    }

    /// Events to show as dots.
    public func events(_ events: [CalendarEvent]) -> Self {
        var copy = self
        copy.events = events
        return copy
    }

    /// Scrolls to the month containing `date` whenever the value changes.
    public func displayDate(_ date: Date?) -> Self {
        var copy = self
        copy.displayDate = date
        return copy
    }

    /// Decides whether a day in range may be selected.
    public func canSelect(_ predicate: @escaping (Date) -> Bool) -> Self {
        var copy = self
        copy.canSelect = predicate
        return copy
    }

    /// A style for one day, or `nil` for the calendar's style.
    public func styleForDate(_ style: @escaping (Date) -> CalendarView.Style?) -> Self {
        var copy = self
        copy.styleForDate = style
        return copy
    }

    /// Called with the first day of each month the calendar settles on.
    public func onScrollToMonth(_ action: @escaping (Date) -> Void) -> Self {
        var copy = self
        copy.onScrollToMonth = action
        return copy
    }

    /// Called when a day is long-pressed, with the events on that day.
    public func onLongPress(_ action: @escaping (Date, [CalendarEvent]) -> Void) -> Self {
        var copy = self
        copy.onLongPress = action
        return copy
    }

    // MARK: UIViewRepresentable

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    public func makeUIView(context: Context) -> CalendarView {
        let view = CalendarView(frame: .zero)
        view.dataSource = context.coordinator
        view.delegate = context.coordinator
        return view
    }

    public func updateUIView(_ view: CalendarView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        coordinator.isUpdating = true
        defer { coordinator.isUpdating = false }

        if view.style != self.style { view.style = self.style }
        if view.direction != self.direction { view.direction = self.direction }
        if view.selectionMode != self.selectionMode { view.selectionMode = self.selectionMode }
        view.enableDeselection = self.allowsDeselection
        if view.marksWeekends != self.marksWeekends { view.marksWeekends = self.marksWeekends }
        view.isScrollEnabled = self.isScrollEnabled
        if coordinator.range != self.range {
            coordinator.range = self.range
            view.reloadData()
        }
        if !coordinator.sameEvents(as: self.events) {
            coordinator.events = self.events
            view.events = self.events
        }
        if let displayDate = self.displayDate, coordinator.lastDisplayDate != displayDate {
            coordinator.lastDisplayDate = displayDate
            view.setDisplayDate(displayDate, animated: context.transaction.animation != nil)
        }

        // Bring the view's selection in line with the binding.
        let calendar = view.calendar
        let wanted = self.selection.map { calendar.startOfDay(for: $0) }
        for date in view.selectedDates where !wanted.contains(date) {
            view.deselectDate(date)
        }
        for date in wanted where !view.selectedDates.contains(date) {
            view.selectDate(date)
        }
    }

    /// Bridges the calendar's data source and delegate to the SwiftUI view.
    @MainActor
    public final class Coordinator: CalendarViewDataSource, CalendarViewDelegate {
        var parent: KDCalendarView
        var range: ClosedRange<Date>
        var events: [CalendarEvent] = []
        var lastDisplayDate: Date?
        var isUpdating = false

        init(_ parent: KDCalendarView) {
            self.parent = parent
            self.range = parent.range
        }

        func sameEvents(as other: [CalendarEvent]) -> Bool {
            events.count == other.count
                && zip(events, other).allSatisfy {
                    $0.title == $1.title && $0.startDate == $1.startDate && $0.endDate == $1.endDate
                }
        }

        public func startDate() -> Date { range.lowerBound }
        public func endDate() -> Date { range.upperBound }

        public func calendar(_ calendar: CalendarView, didScrollToMonth date: Date) {
            parent.onScrollToMonth?(date)
        }

        public func calendar(_ calendar: CalendarView, canSelectDate date: Date) -> Bool {
            parent.canSelect?(date) ?? true
        }

        public func calendar(_ calendar: CalendarView, styleForDate date: Date) -> CalendarView.Style? {
            parent.styleForDate?(date)
        }

        public func calendar(_ calendar: CalendarView, didSelectRange range: ClosedRange<Date>) {
            guard !isUpdating else { return }
            parent.selection = calendar.selectedDates
        }

        public func calendar(_ calendar: CalendarView, didSelectDate date: Date, withEvents events: [CalendarEvent]) {
            guard !isUpdating else { return }
            parent.selection = calendar.selectedDates
        }

        public func calendar(_ calendar: CalendarView, didDeselectDate date: Date) {
            guard !isUpdating else { return }
            parent.selection = calendar.selectedDates
        }

        public func calendar(_ calendar: CalendarView, didLongPressDate date: Date, withEvents events: [CalendarEvent]?)
        {
            parent.onLongPress?(date, events ?? [])
        }
    }
}
#endif
