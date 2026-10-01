/*
 * CalendarView+SwiftUI.swift
 * Created by Michael Michailidis on 08/09/2026.
 * http://blog.karmadust.com/
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 *
 */

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
/// days in the view. An assigned value is applied as a whole, not as a series of taps, in the
/// shape of the selection mode: `.multiple` keeps every day, `.single` keeps the last one, and
/// `.range` selects every day from the earliest to the latest (a lone day is the first end of a
/// range that the next tap completes). Days out of range or refused by ``canSelect(_:)`` are
/// dropped. When the view cannot show the value as given, the binding is set to the days it shows.
public struct KDCalendarView: UIViewRepresentable {

    /// The first and last selectable days.
    public var range: ClosedRange<Date>
    /// The selected days, in selection order.
    ///
    /// See the type's discussion for how an assigned value is shaped by the selection mode.
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

    // MARK: - Modifiers

    /// The look of the calendar.
    public func calendarStyle(_ style: CalendarView.Style) -> Self { with(\.style, style) }

    /// The scrolling axis.
    public func direction(_ direction: UICollectionView.ScrollDirection) -> Self { with(\.direction, direction) }

    /// Whether more than one day can be selected.
    ///
    /// Shorthand for `.single` or `.multiple`.
    public func allowsMultipleSelection(_ allows: Bool) -> Self {
        selectionMode(allows ? .multiple : .single)
    }

    /// How taps combine into a selection: one day, any number of days, or a range.
    public func selectionMode(_ mode: CalendarView.SelectionMode) -> Self { with(\.selectionMode, mode) }

    /// Whether tapping a selected day deselects it.
    public func allowsDeselection(_ allows: Bool) -> Self { with(\.allowsDeselection, allows) }

    /// Whether weekend days use the weekend text colour.
    public func marksWeekends(_ marks: Bool) -> Self { with(\.marksWeekends, marks) }

    /// Whether the user can scroll between months.
    public func scrollEnabled(_ enabled: Bool) -> Self { with(\.isScrollEnabled, enabled) }

    /// Events to show as dots.
    public func events(_ events: [CalendarEvent]) -> Self { with(\.events, events) }

    /// Scrolls to the month containing `date` whenever the value changes.
    public func displayDate(_ date: Date?) -> Self { with(\.displayDate, date) }

    /// Decides whether a day in range may be selected.
    public func canSelect(_ predicate: @escaping (_ date: Date) -> Bool) -> Self { with(\.canSelect, predicate) }

    /// A style for one day, or `nil` for the calendar's style.
    public func styleForDate(_ style: @escaping (_ date: Date) -> CalendarView.Style?) -> Self {
        with(\.styleForDate, style)
    }

    /// Called with the first day of each month the calendar settles on.
    public func onScrollToMonth(_ action: @escaping (_ month: Date) -> Void) -> Self { with(\.onScrollToMonth, action) }

    /// Called when a day is long-pressed, with the events on that day.
    public func onLongPress(_ action: @escaping (_ date: Date, _ events: [CalendarEvent]) -> Void) -> Self {
        with(\.onLongPress, action)
    }

    /// A copy with one property set to `value`, the body of every modifier.
    private func with<Value>(_ keyPath: WritableKeyPath<Self, Value>, _ value: Value) -> Self {
        var copy = self
        copy[keyPath: keyPath] = value
        return copy
    }

    // MARK: - UIViewRepresentable

    /// Creates the coordinator that serves as the calendar's data source and delegate.
    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    /// Creates the calendar view and connects it to the coordinator.
    public func makeUIView(context: Context) -> CalendarView {
        let view = CalendarView(frame: .zero)
        view.dataSource = context.coordinator
        view.delegate = context.coordinator
        return view
    }

    /// Applies the modifiers and the selection binding to the calendar view.
    public func updateUIView(_ view: CalendarView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        coordinator.isUpdating = true
        defer { coordinator.isUpdating = false }

        let bindingFollowsView = applyConfiguration(to: view)
        applyContent(to: view, coordinator: coordinator, animated: context.transaction.animation != nil)
        syncSelection(of: view, coordinator: coordinator, bindingFollowsView: bindingFollowsView)
    }

    /// Sets how the view looks and behaves, and returns whether the binding should take the view's
    /// selection instead of being applied to it.
    ///
    /// A new mode drops the days it cannot hold. Unless the binding brings a selection of its own,
    /// the binding drops them too rather than being reapplied in the new mode's shape.
    private func applyConfiguration(to view: CalendarView) -> Bool {
        if view.style != style { view.style = style }
        if view.direction != direction { view.direction = direction }
        var bindingFollowsView = false
        if view.selectionMode != selectionMode {
            bindingFollowsView = selection.map { view.layoutCalendar.startOfDay(for: $0) } == view.selectedDates
            view.selectionMode = selectionMode
        }
        view.enableDeselection = allowsDeselection
        if view.marksWeekends != marksWeekends { view.marksWeekends = marksWeekends }
        view.isScrollEnabled = isScrollEnabled
        return bindingFollowsView
    }

    /// Hands the view a new range, new events or a new display date, each only when it changed.
    private func applyContent(to view: CalendarView, coordinator: Coordinator, animated: Bool) {
        if coordinator.range != range {
            coordinator.range = range
            view.reloadData()
        }
        if coordinator.events != events {
            coordinator.events = events
            view.events = events
        }
        if let displayDate, coordinator.lastDisplayDate != displayDate {
            coordinator.lastDisplayDate = displayDate
            view.setDisplayDate(displayDate, animated: animated)
        }
    }

    /// Brings the view's selection in line with the binding, or the binding in line with the view
    /// when `bindingFollowsView`.
    ///
    /// Replaying the days as taps would pair them into ranges or keep only the last, so they are
    /// applied as a whole. What the view cannot show as given goes back to the binding.
    private func syncSelection(of view: CalendarView, coordinator: Coordinator, bindingFollowsView: Bool) {
        let wanted = selection.map { view.layoutCalendar.startOfDay(for: $0) }
        guard wanted != view.selectedDates else { return }
        if !bindingFollowsView { view.setSelection(wanted) }
        if view.selectedDates != wanted {
            coordinator.correctSelection(selection, to: view.selectedDates)
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
            range = parent.range
        }

        /// Runs `action` now, or once the view update ends if one is under way: state must not
        /// change during a view update.
        func afterUpdate(_ action: @escaping @MainActor () -> Void) {
            guard isUpdating else { return action() }
            Task { @MainActor in action() }
        }

        /// Replaces a binding value the view could not hold as given with what the view shows,
        /// after the update, unless a tap or the app changed the binding in the meantime.
        func correctSelection(_ requested: [Date], to shown: [Date]) {
            afterUpdate {
                guard self.parent.selection == requested else { return }
                self.parent.selection = shown
            }
        }

        /// Hands the view's selection to the binding after a tap.
        ///
        /// Selections that updateUIView makes are the binding's own and are not echoed back.
        private func selectionChanged(in calendar: CalendarView) {
            guard !isUpdating else { return }
            parent.selection = calendar.selectedDates
        }

        /// The lower bound of the view's range.
        public func startDate() -> Date { range.lowerBound }
        /// The upper bound of the view's range.
        public func endDate() -> Date { range.upperBound }

        // A display date applied by updateUIView announces its month during the view update.
        /// Calls the ``KDCalendarView/onScrollToMonth(_:)`` action.
        public func calendar(_ calendar: CalendarView, didScrollToMonth date: Date) {
            afterUpdate { self.parent.onScrollToMonth?(date) }
        }

        /// Asks the ``KDCalendarView/canSelect(_:)`` predicate; `true` without one.
        public func calendar(_ calendar: CalendarView, canSelectDate date: Date) -> Bool {
            parent.canSelect?(date) ?? true
        }

        /// Asks the ``KDCalendarView/styleForDate(_:)`` closure; `nil` without one.
        public func calendar(_ calendar: CalendarView, styleForDate date: Date) -> CalendarView.Style? {
            parent.styleForDate?(date)
        }

        /// Hands the view's selection to the binding.
        public func calendar(_ calendar: CalendarView, didSelectRange range: ClosedRange<Date>) {
            selectionChanged(in: calendar)
        }

        /// Hands the view's selection to the binding.
        public func calendar(_ calendar: CalendarView, didSelectDate date: Date, withEvents events: [CalendarEvent]) {
            selectionChanged(in: calendar)
        }

        /// Hands the view's selection to the binding.
        public func calendar(_ calendar: CalendarView, didDeselectDate date: Date) {
            selectionChanged(in: calendar)
        }

        /// Calls the ``KDCalendarView/onLongPress(_:)`` action, with no events for a day that has none.
        public func calendar(_ calendar: CalendarView, didLongPressDate date: Date, withEvents events: [CalendarEvent]?)
        {
            parent.onLongPress?(date, events ?? [])
        }
    }
}
#endif
