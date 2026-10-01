import Foundation

/// Everything a ``CalendarView`` shows that derives from its inputs.
///
/// The month grid, the cell of today and the events on each cell, all in one calendar. Pure: one
/// initialiser builds it from the inputs and the current time, so the view only applies it.
struct CalendarSnapshot {

    /// What the grid and the event index are built from.
    struct Inputs: Equatable {
        /// The data source's first day, at the start of the day.
        let startDay: Date
        /// The data source's last day, at the start of the day.
        let endDay: Date
        /// The calendar every date is computed in, fixed so that a later time zone change shows
        /// as different inputs.
        let calendar: Calendar
        /// The weekday of the first column, 1 for Sunday.
        let firstWeekday: Int
        let events: [CalendarEvent]

        /// The inputs of a view showing `start` to `end` in `style` with `events`.
        ///
        /// Only the days count: another time on the same days makes the same inputs.
        init(start: Date, end: Date, style: CalendarView.Style, events: [CalendarEvent]) {
            calendar = style.resolvedCalendar.fixed
            startDay = calendar.startOfDay(for: start)
            endDay = calendar.startOfDay(for: end)
            firstWeekday = style.effectiveFirstWeekday
            self.events = events
        }
    }

    let inputs: Inputs
    /// The months, or `nil` when the range is invalid: the end before the start.
    let grid: MonthGrid?
    /// The cell showing today, or `nil` when today is outside the months.
    let today: IndexPath?
    /// The events on each cell.
    let eventIndex: EventIndex

    /// The calendar the snapshot was built with.
    var calendar: Calendar { inputs.calendar }

    /// Builds the snapshot for `inputs` at `now`.
    ///
    /// The grid and the event index of `previous` are kept when it was built from the same
    /// inputs; today is always found again.
    init(_ inputs: Inputs, now: Date, reusing previous: CalendarSnapshot? = nil) {
        self.inputs = inputs
        if let previous, previous.inputs == inputs {
            grid = previous.grid
            eventIndex = previous.eventIndex
        } else {
            grid = MonthGrid(
                start: inputs.startDay, end: inputs.endDay, calendar: inputs.calendar,
                firstWeekday: inputs.firstWeekday)
            eventIndex = grid.map { EventIndex(events: inputs.events, grid: $0) } ?? EventIndex()
        }
        today = grid?.indexPath(for: now)
    }
}
