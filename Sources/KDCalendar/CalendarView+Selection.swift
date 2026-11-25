import UIKit

extension CalendarView {

    /// How taps and ``selectDate(_:)`` combine into a selection.
    public enum SelectionMode: Sendable {
        /// One day at a time; selecting another replaces it.
        case single
        /// Any number of days, each toggled on its own.
        case multiple
        /// Two taps pick the ends of a range and every selectable day between them is selected.
        /// A third tap starts a new range; tapping a selected day clears the range.
        case range
    }

    /// How taps and ``selectDate(_:)`` combine into a selection. `.multiple` by default.
    ///
    /// Switching to `.single` keeps only the most recently selected day, and switching to
    /// `.range` clears the selection. The delegate receives `didDeselectDate` for each day dropped.
    public var selectionMode: SelectionMode {
        get { selection.mode }
        set { updateSelection(notify: true) { $0.setMode(newValue) } }
    }

    /// Whether more than one day can be selected at a time.
    ///
    /// `false` is ``SelectionMode/single`` and `true` is either of the other modes. Setting `true`
    /// leaves ``SelectionMode/multiple`` and ``SelectionMode/range`` as they are and turns `.single`
    /// into `.multiple`; setting `false` switches to `.single`.
    public var multipleSelectionEnable: Bool {
        get { selectionMode != .single }
        set {
            guard newValue != multipleSelectionEnable else { return }
            selectionMode = newValue ? .multiple : .single
        }
    }

    /// The selected days, in selection order.
    ///
    /// The selection is kept as days, not cells: when the range or the style rebuilds the grid,
    /// the days stay selected wherever their cells land.
    public var selectedDates: [Date] {
        selection.days
    }
    /// The cells of the selected days in the current grid, in selection order.
    ///
    /// Each read looks up every selected day in the grid, so keep the result rather than reading
    /// it once per cell.
    public var selectedIndexPaths: [IndexPath] {
        selectedDates.compactMap { indexPathForDate($0) }
    }

    /// Selects the day containing `date`, subject to the same rules as a tap: the day must be in
    /// range and the delegate's `canSelectDate` must allow it.
    ///
    /// In single-selection mode the previous selection is cleared first. The delegate receives
    /// `didSelectDate`.
    public func selectDate(_ date: Date) {
        let day = layoutCalendar.startOfDay(for: date)
        guard isSelectable(day) else { return }
        selectDay(day)
    }

    /// Deselects the day containing `date` if it is selected.
    ///
    /// The delegate receives `didDeselectDate`. Does nothing for a day that is not selected.
    public func deselectDate(_ date: Date) {
        deselectDay(layoutCalendar.startOfDay(for: date))
    }

    /// Selects every selectable day in `range`, replacing the current selection, and tells the
    /// delegate with `didSelectRange`.
    ///
    /// Works in every ``SelectionMode``; in `.range` mode the next tap starts a new range. The
    /// delegate first receives `didDeselectDate` for each selected day outside the new range.
    public func selectRange(_ range: ClosedRange<Date>) {
        updateSelection(notify: true) { selection in
            var change = selection.replace(with: selectableDays(in: range))
            if let first = selection.days.first, let last = selection.days.last {
                change.completedRange = first...last
            }
            return change
        }
    }

    /// Deselects every day without notifying the delegate.
    public func clearAllSelectedDates() {
        updateSelection(notify: false) { $0.replace(with: []) }
    }

    /// Replaces the selection with `dates` as the selection mode holds them, without replaying taps
    /// and without notifying the delegate.
    ///
    /// See ``SelectionState/assign(_:selectable:)``.
    func setSelection(_ dates: [Date]) {
        updateSelection(notify: false) { selection in
            selection.assign(dates.map { layoutCalendar.startOfDay(for: $0) }, selectable: selectableDays(in:))
        }
    }

    /// Applies one selection change: works it out, commits it, shows it in the grid and, when
    /// `notify` is `true`, tells the delegate.
    ///
    /// The delegate hears first of each day the change dropped, then of the day `tapped` selected,
    /// then of the range the change completed. By then the view shows the whole change. The days
    /// on screen are asked again whether they may be selected at the next layout: see
    /// ``setNeedsSelectabilityRefresh()``.
    ///
    /// - Parameters:
    ///   - notify: Whether the delegate hears of the change.
    ///   - tapped: The day whose tap made the change, at the start of the day, reported with
    ///     `didSelectDate` and its events.
    ///   - body: Changes the selection it is given and returns the change, or `nil` when nothing
    ///     changed. The delegate may read the selection while it is asked which days are
    ///     selectable, so `body` works on a copy that is committed when it returns.
    func updateSelection(
        notify: Bool,
        tapped: Date? = nil,
        _ body: (inout SelectionState) -> SelectionState.Change?
    ) {
        var next = selection
        guard let change = body(&next) else { return }
        selection = next
        show(change)

        if notify {
            for dropped in change.deselected {
                delegate?.calendar(self, didDeselectDate: dropped)
            }
            if let tapped {
                // The cell is looked up only for the events it shows.
                let events = indexPathForDate(tapped).map { snapshot.eventIndex[$0] } ?? []
                delegate?.calendar(self, didSelectDate: tapped, withEvents: events)
            }
            if let range = change.completedRange {
                delegate?.calendar(self, didSelectRange: range)
            }
        }
        if !change.selected.isEmpty || !change.deselected.isEmpty {
            setNeedsSelectabilityRefresh()
        }
    }

    /// Asks again whether each day on screen may be selected, and tells VoiceOver of the days
    /// whose answer changed.
    ///
    /// A day cell is a dimmed button to VoiceOver when the delegate's `canSelectDate` refuses its
    /// day, an answer taken when the cell was laid out. The answer often depends on the selection:
    /// a delegate that allows three days refuses every other day once three are selected, and
    /// allows them again when one is deselected. So every selection change asks for a refresh
    /// with ``setNeedsSelectabilityRefresh()``, and ``KDCalendarView`` does on each update, since
    /// its ``KDCalendarView/canSelect(_:)`` closure may have captured new state. Answers that
    /// change for any other reason need ``reloadData()``.
    ///
    /// Only the cells the collection view has laid out are asked, and no day out of range.
    func refreshSelectability() {
        for case let cell as CalendarDayCell in collectionView.visibleCells {
            guard let day = cell.configuration.date, !cell.configuration.isOutOfRange else { continue }
            let isSelectable = isSelectable(day)
            if cell.configuration.isSelectable != isSelectable {
                cell.configuration.isSelectable = isSelectable
            }
        }
    }

    /// The days from the first day of `range` to its last that can be selected, in order: those
    /// in the data source's range that the delegate allows.
    ///
    /// Only the days in the data source's range are walked, so far-off ends cost nothing.
    func selectableDays(in range: ClosedRange<Date>) -> [Date] {
        snapshot.grid?.days(in: range).filter(isSelectable) ?? []
    }

    /// Whether `day`, the start of a day, may be selected: it must be in the data source's range
    /// and allowed by the delegate, which is asked once.
    func isSelectable(_ day: Date) -> Bool {
        guard let grid = snapshot.grid, grid.isInRange(day) else { return false }
        return delegate?.calendar(self, canSelectDate: day) ?? true
    }

    /// Selects `day`, the start of a day, as a tap does, shows the change and notifies the
    /// delegate: first of the days the tap dropped, then of the tapped day, then of a range it
    /// completed.
    private func selectDay(_ day: Date) {
        updateSelection(notify: true, tapped: day) { $0.tap(day, selectable: selectableDays(in:)) }
    }

    /// Deselects `day`, shows the change and notifies the delegate.
    ///
    /// In range mode a deselection clears the whole range. Nothing happens when `day` is not selected.
    private func deselectDay(_ day: Date) {
        updateSelection(notify: true) { $0.deselect(day) }
    }

    /// Selects and deselects the cells of the days `change` added and removed.
    func show(_ change: SelectionState.Change) {
        for indexPath in change.deselected.compactMap({ indexPathForDate($0) }) {
            collectionView.deselectItem(at: indexPath, animated: false)
        }
        for indexPath in change.selected.compactMap({ indexPathForDate($0) }) {
            collectionView.selectItem(at: indexPath, animated: false, scrollPosition: [])
        }
    }

    /// Keeps the same days selected when the calendar moves from `previous` to `current`.
    ///
    /// A selected day is the start of that day in the old time zone, which can fall on the day
    /// before in the new one.
    func moveSelection(from previous: Calendar, to current: Calendar) {
        guard previous.timeZone != current.timeZone else { return }
        // Days run from midnight to midnight in every calendar, so Gregorian ones can carry the
        // day from one time zone to the other whatever the identifiers.
        var from = Calendar(identifier: .gregorian)
        from.timeZone = previous.timeZone
        var to = Calendar(identifier: .gregorian)
        to.timeZone = current.timeZone
        selection.move { date in
            let day = from.dateComponents([.era, .year, .month, .day], from: date)
            guard let moved = to.date(from: day) else { return date }
            return current.startOfDay(for: moved)
        }
    }
}

extension CalendarView: UICollectionViewDelegateFlowLayout {

    /// Whether the day at `indexPath` may be selected: it must be a day, in range, and allowed
    /// by the delegate.
    func shouldSelect(_ indexPath: IndexPath) -> Bool {
        guard let day = dateFromIndexPath(indexPath) else { return false }
        return isSelectable(day)
    }

    /// Allows a tap on a day in range that the delegate's `canSelectDate` accepts.
    public func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        shouldSelect(indexPath)
    }

    /// Selects the tapped day and notifies the delegate.
    public func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let day = dateFromIndexPath(indexPath) else { return }
        selectDay(day)
    }

    /// Allows a tap to deselect a day when ``enableDeselection`` is `true`.
    public func collectionView(_ collectionView: UICollectionView, shouldDeselectItemAt indexPath: IndexPath) -> Bool {
        enableDeselection
    }

    /// Deselects the tapped day and notifies the delegate.
    public func collectionView(_ collectionView: UICollectionView, didDeselectItemAt indexPath: IndexPath) {
        guard let day = dateFromIndexPath(indexPath) else { return }
        deselectDay(day)
    }

    /// Highlights only the days in range.
    public func collectionView(_ collectionView: UICollectionView, shouldHighlightItemAt indexPath: IndexPath) -> Bool {
        // A cell without a day of its month is out of range too.
        !isOutOfRange(indexPath)
    }
}
