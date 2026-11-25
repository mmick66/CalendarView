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
/// @State private var month = Date()
///
/// KDCalendarView(range: start...end, selection: $selection)
///     .calendarStyle(style)
///     .events(events)
///     .displayedMonth($month)
/// ```
///
/// The selection binding is two-way: taps update it, and assigning to it selects or deselects
/// days in the view. An assigned value is applied as a whole, not as a series of taps, in the
/// shape of the selection mode: `.multiple` keeps every day, `.single` keeps the last one, and
/// `.range` selects every day from the earliest to the latest (a lone day is the first end of a
/// range that the next tap completes). Days out of range or refused by ``canSelect(_:)`` are
/// dropped. When the view cannot show the value as given, the binding is set to the days it shows.
///
/// The month on screen has a two-way binding too, ``displayedMonth(_:)``, next to the one-way
/// ``displayDate(_:)``.
public struct KDCalendarView: UIViewRepresentable {

    /// The first and last selectable days.
    ///
    /// The two ends are moments, and the calendar reads the day of each in the calendar of its
    /// style every time it reloads. After a move to another time zone the same moments can fall on
    /// other days: midnight on 15 June in Athens is the evening of 14 June in New York, where the
    /// range then ends a day earlier and a selection on the 15th is dropped. To keep the same days
    /// there, hand the view a new range once the time zone has changed, with its ends built in
    /// the style's calendar, from date components for instance.
    public var range: ClosedRange<Date> {
        get { configuration.range }
        set { configuration.range = newValue }
    }
    /// The selected days, in selection order.
    ///
    /// See the type's discussion for how an assigned value is shaped by the selection mode.
    @Binding public var selection: [Date]

    /// What the modifiers set on the calendar view.
    var configuration: Configuration
    /// The binding of ``displayedMonth(_:)``.
    var displayedMonth: Binding<Date>?
    var canSelect: ((Date) -> Bool)?
    var styleForDate: ((Date) -> CalendarView.Style?)?
    var onScrollToMonth: ((Date) -> Void)?
    var onLongPress: ((Date, [CalendarEvent]) -> Void)?

    /// Creates a calendar showing every month between the two ends of `range`.
    public init(range: ClosedRange<Date>, selection: Binding<[Date]>) {
        self.configuration = Configuration(range: range)
        self._selection = selection
    }

    /// Everything a SwiftUI update can set on the calendar view, apart from the two bindings.
    ///
    /// The coordinator keeps the one the view shows. `updateUIView` compares the new one with it
    /// and sets only the fields that differ, so a body that runs again with the same values
    /// touches nothing. The defaults are those of a new ``CalendarView``, which is why
    /// `makeUIView` sets only what the modifiers changed.
    struct Configuration: Equatable {
        var range: ClosedRange<Date>
        var style = CalendarView.Style.default
        var direction = UICollectionView.ScrollDirection.horizontal
        var selectionMode = CalendarView.SelectionMode.multiple
        var allowsDeselection = true
        var marksWeekends = true
        var isScrollEnabled = true
        var mirrorsInRightToLeftLayouts = false
        /// The layout direction of the SwiftUI environment, which `updateUIView` fills in.
        var layoutDirection = LayoutDirection.leftToRight
        var events: [CalendarEvent] = []
        /// The date of ``KDCalendarView/displayDate(_:)``, which `updateUIView` clears when
        /// ``KDCalendarView/displayedMonth(_:)`` decides the month.
        var displayDate: Date?

        /// The semantic content attribute of the hosted view: the environment's direction when
        /// the calendar mirrors, and the view's own default when it does not.
        var semanticContentAttribute: UISemanticContentAttribute {
            guard mirrorsInRightToLeftLayouts else { return .unspecified }
            return layoutDirection == .rightToLeft ? .forceRightToLeft : .forceLeftToRight
        }
    }

    // MARK: - Modifiers

    /// The look of the calendar.
    public func calendarStyle(_ style: CalendarView.Style) -> Self { with(\.configuration.style, style) }

    /// The scrolling axis.
    public func direction(_ direction: UICollectionView.ScrollDirection) -> Self {
        with(\.configuration.direction, direction)
    }

    /// Whether more than one day can be selected.
    ///
    /// Shorthand for `.single` or `.multiple`.
    public func allowsMultipleSelection(_ allows: Bool) -> Self {
        selectionMode(allows ? .multiple : .single)
    }

    /// How taps combine into a selection: one day, any number of days, or a range.
    public func selectionMode(_ mode: CalendarView.SelectionMode) -> Self {
        with(\.configuration.selectionMode, mode)
    }

    /// Whether tapping a selected day deselects it.
    public func allowsDeselection(_ allows: Bool) -> Self { with(\.configuration.allowsDeselection, allows) }

    /// Whether weekend days use the weekend text colour.
    public func marksWeekends(_ marks: Bool) -> Self { with(\.configuration.marksWeekends, marks) }

    /// Whether the user can scroll between months.
    public func scrollEnabled(_ enabled: Bool) -> Self { with(\.configuration.isScrollEnabled, enabled) }

    /// Whether the grid mirrors when the layout runs right to left.
    ///
    /// A mirroring calendar follows the layout direction of the SwiftUI environment: in a
    /// right-to-left layout the first weekday sits on the right and the months run from right to
    /// left. Without this modifier, or with `false`, the grid always runs left to right.
    public func mirrorsInRightToLeftLayouts(_ mirrors: Bool = true) -> Self {
        with(\.configuration.mirrorsInRightToLeftLayouts, mirrors)
    }

    /// Events to show as dots.
    public func events(_ events: [CalendarEvent]) -> Self { with(\.configuration.events, events) }

    /// Scrolls to the month containing `date` whenever the value moves to another month.
    ///
    /// The calendar scrolls when `date` falls in another month than the value of the last update
    /// did, so a value such as `Date()`, a new moment each time the body runs, scrolls once and
    /// then leaves the user's swipes alone. `nil` asks for nothing, and a date that follows `nil`
    /// scrolls.
    ///
    /// This form only sees the value change: it cannot bring back a month that the user swiped
    /// away from while the value stayed the same. ``displayedMonth(_:)`` can, and takes this
    /// modifier's place when both are used.
    public func displayDate(_ date: Date?) -> Self { with(\.configuration.displayDate, date) }

    /// Binds the month on screen to `month`, both ways.
    ///
    /// Assigning the binding scrolls the calendar to the month of the value, and the calendar sets
    /// the binding to the first day of each month it settles on.
    ///
    /// ```swift
    /// @State private var month = Date()
    ///
    /// KDCalendarView(range: range, selection: $selection)
    ///     .displayedMonth($month)
    ///     .toolbar { Button("Today") { withAnimation { month = Date() } } }
    /// ```
    ///
    /// Any moment of a month stands for that month, in the calendar of the style, and the calendar
    /// leaves the value alone while it shows that month. A month outside the calendar's range
    /// cannot be shown, so the binding is set back to the month on screen. An assignment made in a
    /// transaction with an animation scrolls animated.
    public func displayedMonth(_ month: Binding<Date>) -> Self { with(\.displayedMonth, month) }

    /// Decides whether a day in range may be selected.
    ///
    /// The predicate is asked when a day is tapped or assigned through the selection binding, and
    /// also whenever a day is drawn, to tell VoiceOver which days are dimmed: for each day of a
    /// month as it comes on screen, and again for the days on screen at the layout that follows a
    /// change of the selection or an update of this view. Keep it quick and free of side effects.
    ///
    /// An update of this view brings the days on screen in line with a predicate that captured
    /// new state. State that changes without the body running again, such as an object the
    /// predicate reads that the body does not, is not noticed: taps follow it at once, but
    /// VoiceOver keeps the old answer until the days are drawn again.
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
        connect(view, to: context.coordinator, layoutDirection: context.environment.layoutDirection)
        return view
    }

    /// Makes `coordinator` the data source and the delegate of `view`, a new calendar view, and
    /// gives the view the modifiers' values, with one reload for the data source and all of them.
    ///
    /// The first update then finds the view showing its configuration, and has only the display
    /// date and the two bindings left to apply.
    ///
    /// - Parameters:
    ///   - view: A calendar view as `CalendarView(frame:)` makes it.
    ///   - coordinator: The coordinator of this view, which still holds the default configuration.
    ///   - layoutDirection: The layout direction of the SwiftUI environment.
    func connect(_ view: CalendarView, to coordinator: Coordinator, layoutDirection: LayoutDirection) {
        var new = configuration
        new.layoutDirection = layoutDirection
        // The first update scrolls to the display date, as every later one does.
        new.displayDate = nil
        let defaults = coordinator.configuration
        // Before the view is touched: it asks the coordinator for the range when it reloads.
        coordinator.configuration = new
        // As in an update, nothing the view reports while it is set up may change state.
        coordinator.isUpdating = true
        defer { coordinator.isUpdating = false }
        view.delegate = coordinator
        view.performBatchUpdate {
            view.dataSource = coordinator
            apply(new, replacing: defaults, to: view)
        }
        // The view tells no delegate when it moves its dates to another calendar, since the days
        // stay the same, but the bindings hold those dates as instants.
        view.calendarDidChange = { [weak coordinator, weak view] in
            guard let view else { return }
            coordinator?.calendarChanged(in: view)
        }
        // Nor when a scroll comes to rest on the month it last announced, which the month binding
        // may have left in the meantime: see `CalendarView.scrollDidSettle`.
        view.scrollDidSettle = { [weak coordinator, weak view] _ in
            guard let view else { return }
            coordinator?.showDisplayedMonth(in: view)
        }
    }

    /// Applies the modifiers and the two bindings to the calendar view.
    ///
    /// Of the modifiers, only the values that changed since the last update are set, and the view
    /// reloads once for all of them. The bindings are compared with what the view shows.
    public func updateUIView(_ view: CalendarView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        coordinator.isUpdating = true
        defer { coordinator.isUpdating = false }

        var new = configuration
        new.layoutDirection = context.environment.layoutDirection
        if displayedMonth != nil { new.displayDate = nil }
        let old = coordinator.configuration
        let animated = context.transaction.animation != nil

        // A new mode drops the days it cannot hold. Unless the binding brings a selection of its
        // own, the binding drops them too rather than being reapplied in the new mode's shape.
        let bindingFollowsView =
            old.selectionMode != new.selectionMode
            && selection.map { view.layoutCalendar.startOfDay(for: $0) } == view.selectedDates

        if new != old {
            // Before the view is touched: it asks the coordinator for the range when it reloads.
            coordinator.configuration = new
            // One reload for everything that changed, not one for each value.
            view.performBatchUpdate {
                apply(new, replacing: old, to: view)
            }
            // After the reload, so that the month is found in the new range and compared in the
            // new style's calendar. Months, not instants: `displayDate(Date())` is a new instant on
            // every body run, and scrolling to each one would undo every swipe.
            if let date = new.displayDate, !view.layoutCalendar.isDate(date, inSameMonthAs: old.displayDate) {
                view.setDisplayDate(date, animated: animated)
            }
        }
        syncSelection(of: view, coordinator: coordinator, bindingFollowsView: bindingFollowsView)
        syncDisplayedMonth(of: view, coordinator: coordinator, animated: animated)
        coordinator.noteBindings()
        // The predicate is a new closure on every update and may have captured new state. It is
        // not part of the configuration, so nothing above has reloaded the days on screen for it.
        if canSelect != nil {
            view.setNeedsSelectabilityRefresh()
        }
    }

    /// Sets on `view` each field of `new` that differs from `old`, the configuration the view shows.
    ///
    /// With the display date, which `updateUIView` applies once the view has reloaded, this is
    /// all that a change of modifiers does to the view. It runs inside
    /// ``CalendarView/performBatchUpdate(_:)``, so the values that reload the view only ask for
    /// the one reload that follows.
    private func apply(_ new: Configuration, replacing old: Configuration, to view: CalendarView) {
        if old.style != new.style { view.style = new.style }
        if old.direction != new.direction { view.direction = new.direction }
        if old.selectionMode != new.selectionMode { view.selectionMode = new.selectionMode }
        if old.allowsDeselection != new.allowsDeselection { view.enableDeselection = new.allowsDeselection }
        if old.marksWeekends != new.marksWeekends { view.marksWeekends = new.marksWeekends }
        if old.isScrollEnabled != new.isScrollEnabled { view.isScrollEnabled = new.isScrollEnabled }
        // The view works its direction out again when either of the two changes.
        if old.mirrorsInRightToLeftLayouts != new.mirrorsInRightToLeftLayouts {
            view.forceLtr = !new.mirrorsInRightToLeftLayouts
        }
        if old.semanticContentAttribute != new.semanticContentAttribute {
            view.semanticContentAttribute = new.semanticContentAttribute
        }
        if old.range != new.range { view.reloadData() }
        if old.events != new.events { view.events = new.events }
    }

    /// Brings the view's selection in line with the binding, or the binding in line with the view
    /// when `bindingFollowsView`.
    ///
    /// Replaying the days as taps would pair them into ranges or keep only the last, so they are
    /// applied as a whole. What the view cannot show as given goes back to the binding.
    private func syncSelection(of view: CalendarView, coordinator: Coordinator, bindingFollowsView: Bool) {
        // The days as they were in the calendar the view has left are not a request: read in the
        // new calendar they can be other days. The coordinator sets the binding after the update.
        guard selection != coordinator.outdatedSelection else { return }
        coordinator.outdatedSelection = nil
        let wanted = selection.map { view.layoutCalendar.startOfDay(for: $0) }
        guard wanted != view.selectedDates else { return }
        if !bindingFollowsView { view.setSelection(wanted) }
        if view.selectedDates != wanted {
            coordinator.correctSelection(selection, in: view)
        }
    }

    /// Scrolls the view to the month of the ``displayedMonth(_:)`` binding, unless it shows that
    /// month already.
    ///
    /// The view's own month is the reference, not the binding's last value, so the month the user
    /// swiped away from can be assigned again. A month the view cannot show goes back to the
    /// binding as the month on screen.
    private func syncDisplayedMonth(of view: CalendarView, coordinator: Coordinator, animated: Bool) {
        // As for the selection: the month as it was in the calendar the view has left is not a
        // request, and the coordinator sets the binding after the update.
        guard let wanted = displayedMonth?.wrappedValue, wanted != coordinator.outdatedMonth else { return }
        coordinator.outdatedMonth = nil
        guard !view.layoutCalendar.isDate(wanted, inSameMonthAs: view.displayDate) else { return }
        view.setDisplayDate(wanted, animated: animated)
        coordinator.showDisplayedMonth(in: view)
    }

    /// Bridges the calendar's data source and delegate to the SwiftUI view.
    @MainActor
    public final class Coordinator: CalendarViewDataSource, CalendarViewDelegate {
        var parent: KDCalendarView
        /// The configuration the view shows: the one `makeUIView` or the last update applied.
        var configuration: Configuration
        var isUpdating = false
        /// The value of the selection binding as the wrapper last read it in an update or set it
        /// itself.
        ///
        /// A binding that holds anything else has been assigned by the app since.
        private var knownSelection: [Date]?
        /// The value of the ``KDCalendarView/displayedMonth(_:)`` binding as the wrapper last read
        /// it in an update or set it itself.
        private var knownMonth: Date?
        /// The value of the selection binding that the view moved to another calendar during a
        /// view update, until the binding holds the moved days.
        var outdatedSelection: [Date]?
        /// The value of the ``KDCalendarView/displayedMonth(_:)`` binding that the view moved to
        /// another calendar during a view update, until the binding holds the moved month.
        var outdatedMonth: Date?

        init(_ parent: KDCalendarView) {
            self.parent = parent
            configuration = Configuration(range: parent.range)
        }

        /// Runs `action` now, or once the view update ends if one is under way: state must not
        /// change during a view update.
        func afterUpdate(_ action: @escaping @MainActor () -> Void) {
            guard isUpdating else { return action() }
            Task { @MainActor in action() }
        }

        /// Replaces a binding value the view could not hold as given with what the view shows,
        /// after the update, unless a tap or the app changed the binding in the meantime.
        ///
        /// What the view shows is read when the binding is set, not when the correction is asked
        /// for: the view may move its days to another calendar between the two.
        func correctSelection(_ requested: [Date], in calendar: CalendarView) {
            afterUpdate { [weak calendar] in
                guard let calendar, self.parent.selection == requested else { return }
                self.parent.selection = calendar.selectedDates
                self.knownSelection = self.parent.selection
            }
        }

        /// Remembers the values the bindings hold once an update has read them, to tell them
        /// from values the app assigns later.
        func noteBindings() {
            knownSelection = parent.selection
            knownMonth = parent.displayedMonth?.wrappedValue
        }

        /// Sets the ``KDCalendarView/displayedMonth(_:)`` binding to the month `calendar` shows,
        /// unless its value is in that month already.
        ///
        /// During a view update the binding is set once the update has ended, and then only if
        /// the app did not assign it in the meantime. The month is read when the binding is set:
        /// the view may move it to another calendar before the update ends.
        func showDisplayedMonth(in calendar: CalendarView) {
            guard let requested = parent.displayedMonth?.wrappedValue,
                displayedMonth(of: calendar, replacing: requested) != nil
            else { return }
            afterUpdate { [weak calendar] in
                guard let calendar, let binding = self.parent.displayedMonth, binding.wrappedValue == requested,
                    let month = self.displayedMonth(of: calendar, replacing: requested)
                else { return }
                binding.wrappedValue = month
                self.knownMonth = binding.wrappedValue
            }
        }

        /// The month `calendar` shows, when it is another month than that of `requested`, the
        /// value of the binding; `nil` when the binding needs no new value.
        private func displayedMonth(of calendar: CalendarView, replacing requested: Date) -> Date? {
            guard let month = calendar.displayDate,
                !calendar.layoutCalendar.isDate(requested, inSameMonthAs: month)
            else { return nil }
            return month
        }

        /// Sets the bindings to the days and the month `calendar` shows, once it has moved them
        /// to another calendar: after a change of time zone, the midnights of the new one.
        ///
        /// A binding follows only while it holds the value the wrapper last read or set, which is
        /// what the view showed before the move. Any other value is one the app has assigned and
        /// the view has yet to show; the next update applies it. During a view update the bindings
        /// are set once the update has ended, and until they are, that update and any other leave
        /// the old values alone rather than read them in the new calendar, where midnight in
        /// Athens is the evening before in New York.
        func calendarChanged(in calendar: CalendarView) {
            let selection = parent.selection
            if selection == knownSelection, selection != calendar.selectedDates {
                if isUpdating { outdatedSelection = selection }
                correctSelection(selection, in: calendar)
            }
            if let month = parent.displayedMonth?.wrappedValue, month == knownMonth,
                let displayDate = calendar.displayDate,
                !calendar.layoutCalendar.isDate(month, inSameMonthAs: displayDate)
            {
                if isUpdating { outdatedMonth = month }
                showDisplayedMonth(in: calendar)
            }
        }

        /// Hands the view's selection to the binding after a tap.
        ///
        /// Selections that updateUIView makes are the binding's own and are not echoed back.
        private func selectionChanged(in calendar: CalendarView) {
            guard !isUpdating else { return }
            parent.selection = calendar.selectedDates
            knownSelection = parent.selection
        }

        /// The lower bound of the view's range.
        public func startDate() -> Date { configuration.range.lowerBound }
        /// The upper bound of the view's range.
        public func endDate() -> Date { configuration.range.upperBound }

        // A month applied by updateUIView is announced during the view update.
        /// Sets the ``KDCalendarView/displayedMonth(_:)`` binding, then calls the
        /// ``KDCalendarView/onScrollToMonth(_:)`` action.
        public func calendar(_ calendar: CalendarView, didScrollToMonth date: Date) {
            showDisplayedMonth(in: calendar)
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

extension Calendar {
    /// Whether `date` falls in the month of `other`; `false` when there is no other date.
    fileprivate func isDate(_ date: Date, inSameMonthAs other: Date?) -> Bool {
        guard let other else { return false }
        return isDate(date, equalTo: other, toGranularity: .month)
    }
}
#endif
