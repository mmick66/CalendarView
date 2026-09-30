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
    /// The selected days, in selection order. See the type's discussion for how an assigned value
    /// is shaped by the selection mode.
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
        // A new mode drops the days it cannot hold. Unless the binding brings a selection of its
        // own, the binding drops them too rather than being reapplied in the new mode's shape.
        var bindingFollowsView = false
        if view.selectionMode != self.selectionMode {
            let bindingIsShown = self.selection.map { view.calendar.startOfDay(for: $0) } == view.selectedDates
            view.selectionMode = self.selectionMode
            bindingFollowsView = bindingIsShown
        }
        view.enableDeselection = self.allowsDeselection
        if view.marksWeekends != self.marksWeekends { view.marksWeekends = self.marksWeekends }
        view.isScrollEnabled = self.isScrollEnabled
        if coordinator.range != self.range {
            coordinator.range = self.range
            view.reloadData()
        }
        if coordinator.events != self.events {
            coordinator.events = self.events
            view.events = self.events
        }
        if let displayDate = self.displayDate, coordinator.lastDisplayDate != displayDate {
            coordinator.lastDisplayDate = displayDate
            view.setDisplayDate(displayDate, animated: context.transaction.animation != nil)
        }

        // Bring the view's selection in line with the binding. Replaying the days as taps would
        // pair them into ranges or keep only the last, so they are applied as a whole.
        let calendar = view.calendar
        let wanted = self.selection.map { calendar.startOfDay(for: $0) }
        if bindingFollowsView {
            if wanted != view.selectedDates {
                coordinator.correctSelection(self.selection, to: view.selectedDates)
            }
        } else if wanted != view.selectedDates {
            view.setSelection(wanted)
            if view.selectedDates != wanted {
                coordinator.correctSelection(self.selection, to: view.selectedDates)
            }
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

        /// Replaces a binding value the view could not hold as given with what the view shows.
        /// State must not change during a view update, so this waits for the update to end, and
        /// gives up if a tap or the app changed the binding in the meantime.
        func correctSelection(_ requested: [Date], to shown: [Date]) {
            Task { @MainActor in
                guard self.parent.selection == requested else { return }
                self.parent.selection = shown
            }
        }

        public func startDate() -> Date { range.lowerBound }
        public func endDate() -> Date { range.upperBound }

        // A display date applied by updateUIView announces its month during the view update,
        // where the action must not change state, so the action waits for the update to end.
        public func calendar(_ calendar: CalendarView, didScrollToMonth date: Date) {
            guard isUpdating else {
                parent.onScrollToMonth?(date)
                return
            }
            Task { @MainActor in self.parent.onScrollToMonth?(date) }
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
