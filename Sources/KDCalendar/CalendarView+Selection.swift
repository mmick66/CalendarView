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
        set {
            let change = selection.setMode(newValue)
            show(change)
            for date in change.deselected {
                delegate?.calendar(self, didDeselectDate: date)
            }
        }
    }

    /// Whether more than one day can be selected at a time. `false` is ``SelectionMode/single``,
    /// `true` is ``SelectionMode/multiple``.
    public var multipleSelectionEnable: Bool {
        get { selectionMode != .single }
        set { selectionMode = newValue ? .multiple : .single }
    }

    /// The selected days, in selection order.
    ///
    /// The selection is kept as days, not cells: when the range or the style rebuilds the grid,
    /// the days stay selected wherever their cells land.
    public var selectedDates: [Date] {
        selection.days
    }
    /// The cells of the selected days in the current grid, in selection order.
    public var selectedIndexPaths: [IndexPath] {
        selectedDates.compactMap { indexPathForDate($0) }
    }

    /// Selects the day containing `date`, subject to the same rules as a tap: the day must be
    /// in range and the delegate's `canSelectDate` must allow it. In single-selection mode the
    /// previous selection is cleared first. The delegate receives `didSelectDate`.
    public func selectDate(_ date: Date) {
        guard let indexPath = self.indexPathForDate(date), self.shouldSelect(indexPath) else { return }
        self.didSelect(indexPath)
    }

    /// Deselects the day containing `date` if it is selected. The delegate receives
    /// `didDeselectDate`. Does nothing for a day that is not selected.
    public func deselectDate(_ date: Date) {
        guard let indexPath = self.indexPathForDate(date) else { return }
        self.didDeselect(indexPath)
    }

    /// Selects every selectable day in `range`, replacing the current selection, and tells the
    /// delegate with `didSelectRange`. Works in every ``SelectionMode``; in `.range` mode the next
    /// tap starts a new range.
    public func selectRange(_ range: ClosedRange<Date>) {
        show(selection.replace(with: selectableDays(in: range)))
        guard let first = selectedDates.first, let last = selectedDates.last else { return }
        delegate?.calendar(self, didSelectRange: first...last)
    }

    /// Deselects every day without notifying the delegate.
    public func clearAllSelectedDates() {
        show(selection.replace(with: []))
    }

    /// Replaces the selection with `dates` as the selection mode holds them, without replaying
    /// taps and without notifying the delegate. See ``SelectionState/assign(_:selectable:)``.
    func setSelection(_ dates: [Date]) {
        // The delegate may read the selection while it is asked which days are selectable, so
        // the change is worked out on a copy.
        var next = selection
        let change = next.assign(dates.map { calendar.startOfDay(for: $0) }, selectable: selectableDays(in:))
        selection = next
        show(change)
    }

    /// The days from the first day of `range` to its last that can be selected, in order: those
    /// in the data source's range that the delegate allows.
    func selectableDays(in range: ClosedRange<Date>) -> [Date] {
        // Only days in range can be selected, so far-off ends cost nothing.
        let bounds = dateRange
        let last = min(calendar.startOfDay(for: range.upperBound), bounds.upperBound)
        var day = max(calendar.startOfDay(for: range.lowerBound), bounds.lowerBound)
        var days = [Date]()
        while day <= last {
            if let indexPath = indexPathForDate(day), let date = dateFromIndexPath(indexPath), shouldSelect(indexPath) {
                days.append(date)
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = calendar.startOfDay(for: next)
        }
        return days
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

    /// Keeps the same days selected when the calendar moves to another time zone. A selected day
    /// is the start of that day in the old time zone, which can fall on the day before in the new one.
    func moveSelection(from previous: Calendar) {
        let current = calendar
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
        guard let date = self.dateFromIndexPath(indexPath), !isOutOfRange(indexPath) else { return false }
        return delegate?.calendar(self, canSelectDate: date) ?? true
    }

    /// Selects the day at `indexPath` as a tap does, shows the change and notifies the delegate:
    /// first of the days the tap dropped, then of the tapped day, then of a range it completed.
    func didSelect(_ indexPath: IndexPath) {
        guard let date = self.dateFromIndexPath(indexPath) else { return }
        // The delegate may read the selection while it is asked which days are selectable, so
        // the change is worked out on a copy.
        var next = selection
        guard let change = next.tap(date, selectable: selectableDays(in:)) else { return }
        selection = next
        show(change)

        for dropped in change.deselected {
            delegate?.calendar(self, didDeselectDate: dropped)
        }
        delegate?.calendar(self, didSelectDate: date, withEvents: snapshot.eventIndex[indexPath])
        if let range = change.completedRange {
            delegate?.calendar(self, didSelectRange: range)
        }
    }

    /// Deselects the day at `indexPath`, shows the change and notifies the delegate. In range
    /// mode a deselection clears the whole range.
    func didDeselect(_ indexPath: IndexPath) {
        guard let date = self.dateFromIndexPath(indexPath) else { return }
        let change = selection.deselect(date)
        show(change)
        for dropped in change.deselected {
            delegate?.calendar(self, didDeselectDate: dropped)
        }
    }

    public func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        return shouldSelect(indexPath)
    }

    public func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        didSelect(indexPath)
    }

    public func collectionView(_ collectionView: UICollectionView, shouldDeselectItemAt indexPath: IndexPath) -> Bool {
        return enableDeselection
    }

    public func collectionView(_ collectionView: UICollectionView, didDeselectItemAt indexPath: IndexPath) {
        didDeselect(indexPath)
    }

    public func collectionView(_ collectionView: UICollectionView, shouldHighlightItemAt indexPath: IndexPath) -> Bool {
        return self.dateFromIndexPath(indexPath) != nil && !isOutOfRange(indexPath)
    }
}
