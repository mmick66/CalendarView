import Foundation

/// The events each cell of a ``MonthGrid`` shows. An event marks every day it covers, in the
/// grid's calendar. Pure date arithmetic, built once per grid and list of events.
struct EventIndex {

    private var eventsByIndexPath: [IndexPath: [CalendarEvent]] = [:]

    /// An index with no events.
    init() {}

    /// Buckets every event into the days it covers, clamped to the grid's months so an
    /// open-ended event costs one loop over the grid, not over the centuries.
    init(events: [CalendarEvent], grid: MonthGrid) {
        let calendar = grid.calendar
        guard let first = grid.months.first, let lastMonth = grid.months.last,
            let gridEnd = calendar.date(byAdding: .day, value: lastMonth.daysTotal, to: lastMonth.firstDate)
        else { return }
        let gridStart = first.firstDate
        for event in events {
            let eventEnd = max(event.startDate, event.endDate)
            guard event.startDate < gridEnd, eventEnd >= gridStart else { continue }
            var day = calendar.startOfDay(for: max(event.startDate, gridStart))
            let last = min(eventEnd, gridEnd)
            repeat {
                if let indexPath = grid.indexPath(for: day) {
                    eventsByIndexPath[indexPath, default: []].append(event)
                }
                // Where a DST change skips midnight, adding a day lands after it, so return to the start.
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = calendar.startOfDay(for: next)
            } while day < last
        }
    }

    /// The events on the day a cell shows, in the order they were given; empty for any other cell.
    subscript(indexPath: IndexPath) -> [CalendarEvent] {
        eventsByIndexPath[indexPath] ?? []
    }

    /// The number of events on the day a cell shows.
    func count(at indexPath: IndexPath) -> Int {
        self[indexPath].count
    }

    /// Whether no day of the grid has an event.
    var isEmpty: Bool {
        eventsByIndexPath.isEmpty
    }
}
