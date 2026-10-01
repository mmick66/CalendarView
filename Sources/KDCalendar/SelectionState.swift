import Foundation

/// The selected days of a ``CalendarView`` and the rules of its ``CalendarView/SelectionMode``.
///
/// Days are start-of-day dates in the view's calendar. The state knows nothing of cells, so it
/// survives any rebuild of the grid. Every change returns the days it added and removed; the view
/// shows them in the grid and tells its delegate.
struct SelectionState: Equatable, Sendable {

    /// The days one change added and removed, each in selection order.
    struct Change: Equatable, Sendable {
        var selected: [Date] = []
        var deselected: [Date] = []
        /// The range a tap completed in `.range` mode, from its earliest day to its latest.
        var completedRange: ClosedRange<Date>?
    }

    /// The selectable days from the first day of a range to its last, in order.
    typealias SelectableDays = (ClosedRange<Date>) -> [Date]

    /// How taps combine into a selection.
    private(set) var mode: CalendarView.SelectionMode = .multiple
    /// The selected days, in selection order.
    private(set) var days: [Date] = []
    /// The first end of a range still waiting for its second tap in `.range` mode.
    private(set) var rangeStart: Date?

    /// A tap on `day`, a selectable day. `.single` replaces the selection with it and
    /// `.multiple` adds it. `.range` starts a new range at it, or, when a range is waiting for
    /// its second end, adds every selectable day between the two ends.
    ///
    /// Returns `nil` when `day` is already selected: the tap changes nothing.
    mutating func tap(_ day: Date, selectable: SelectableDays) -> Change? {
        guard !days.contains(day) else { return nil }
        switch mode {
        case .single:
            return replace(with: [day])
        case .multiple:
            return replace(with: days + [day])
        case .range:
            guard let start = rangeStart else { return replace(with: [day], rangeStart: day) }
            let selected = Set(days)
            let filled = days + selectable(min(start, day)...max(start, day)).filter { !selected.contains($0) }
            var change = replace(with: filled)
            if let lower = filled.min(), let upper = filled.max() {
                change.completedRange = lower...upper
            }
            return change
        }
    }

    /// Deselects `day`.
    ///
    /// In `.range` mode that clears the whole range. Nothing changes when `day` is not selected.
    mutating func deselect(_ day: Date) -> Change {
        guard days.contains(day) else { return Change() }
        return replace(with: mode == .range ? [] : days.filter { $0 != day })
    }

    /// Switches to `newMode`, dropping the days it cannot hold: `.single` keeps the most recent
    /// day, `.range` starts clean and `.multiple` keeps every day.
    mutating func setMode(_ newMode: CalendarView.SelectionMode) -> Change {
        guard newMode != mode else { return Change() }
        mode = newMode
        switch newMode {
        case .single: return replace(with: Array(days.suffix(1)))
        case .multiple: return replace(with: days)
        case .range: return replace(with: [])
        }
    }

    /// Replaces the selection with `requested` as the mode holds it, with no tap involved.
    /// `.multiple` keeps every selectable day once, in order; `.single` keeps the last one;
    /// `.range` selects every selectable day from the earliest to the latest, and takes a lone
    /// day as the first end of a new range.
    mutating func assign(_ requested: [Date], selectable: SelectableDays) -> Change {
        var seen = Set<Date>()
        let wanted = requested.filter { seen.insert($0).inserted }
        let isRange = mode == .range && wanted.count > 1
        var kept: [Date]
        if isRange, let lower = wanted.min(), let upper = wanted.max() {
            kept = selectable(lower...upper)
        } else {
            kept = wanted.filter { selectable($0...$0) == [$0] }
        }
        if mode == .single {
            kept = Array(kept.suffix(1))
        }
        return replace(with: kept, rangeStart: mode == .range && !isRange ? kept.first : nil)
    }

    /// Keeps the days `isKept` accepts, in order.
    ///
    /// A range start goes with its day.
    mutating func retain(where isKept: (Date) -> Bool) -> Change {
        let kept = days.filter(isKept)
        return replace(with: kept, rangeStart: rangeStart.flatMap { kept.contains($0) ? $0 : nil })
    }

    /// Moves every day, and the range start, with `transform`.
    mutating func move(_ transform: (Date) -> Date) {
        days = days.map(transform)
        rangeStart = rangeStart.map(transform)
    }

    /// Replaces the selection with `newDays`.
    ///
    /// Any range they make is complete unless `rangeStart` says it waits for its second end.
    mutating func replace(with newDays: [Date], rangeStart: Date? = nil) -> Change {
        let old = days
        let oldSet = Set(old)
        let newSet = Set(newDays)
        days = newDays
        self.rangeStart = rangeStart
        return Change(
            selected: newDays.filter { !oldSet.contains($0) },
            deselected: old.filter { !newSet.contains($0) }
        )
    }
}
