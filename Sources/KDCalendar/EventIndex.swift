import Foundation

/// The events each cell of a ``MonthGrid`` shows.
///
/// An event marks every day it covers, in the grid's calendar. Pure date arithmetic, built once per
/// grid and list of events.
struct EventIndex {

    /// An event and the days of one month it covers.
    private struct Span {
        let event: CalendarEvent
        /// The items of those days in the month's section.
        let items: ClosedRange<Int>
    }

    /// The events that cover a day of each month, by section, in the order they were given.
    private var spansBySection: [[Span]] = []

    /// An index with no events.
    init() {}

    /// Finds the days each event covers, clamped to the grid's months.
    ///
    /// The calendar is asked for the event's first and last day only. The days between them are
    /// the cells between theirs, so a long event costs one step per month it covers, not per day.
    init(events: [CalendarEvent], grid: MonthGrid) {
        let calendar = grid.calendar
        let months = grid.months
        let gridStart = months[0].firstDate
        let gridEnd = grid.lastMonthEnd
        spansBySection = Array(repeating: [], count: months.count)
        for event in events {
            let eventEnd = max(event.startDate, event.endDate)
            guard event.startDate < gridEnd, eventEnd >= gridStart,
                let first = grid.indexPath(for: max(event.startDate, gridStart))
            else { continue }
            // After its first day the event marks each day that starts before it ends. An end at
            // the very start of a day, as the end of the grid is, leaves that day out: its last
            // day is then the one a second earlier. For an event that ends as its first day
            // starts, that is the day before or no day of the grid, and the first day stands.
            let end = min(eventEnd, gridEnd)
            let endsInsideADay = end < gridEnd && calendar.startOfDay(for: end) < end
            let lastMoment = endsInsideADay ? end : end.addingTimeInterval(-1)
            let last = grid.indexPath(for: lastMoment).map { max($0, first) } ?? first

            // The days between the two are the cells between theirs, month by month.
            for section in first.section...last.section {
                let month = months[section]
                let lower = section == first.section ? first.item : month.firstColumn
                let upper = section == last.section ? last.item : month.firstColumn + month.dayCount - 1
                guard lower <= upper else { continue }
                spansBySection[section].append(Span(event: event, items: lower...upper))
            }
        }
    }

    /// The events on the day a cell shows, in the order they were given; empty for any other cell.
    subscript(indexPath: IndexPath) -> [CalendarEvent] {
        guard spansBySection.indices.contains(indexPath.section) else { return [] }
        return spansBySection[indexPath.section].compactMap { $0.items.contains(indexPath.item) ? $0.event : nil }
    }

    /// The number of events on the day a cell shows.
    func count(at indexPath: IndexPath) -> Int {
        guard spansBySection.indices.contains(indexPath.section) else { return 0 }
        return spansBySection[indexPath.section].count { $0.items.contains(indexPath.item) }
    }

    /// Whether no day of the grid has an event.
    var isEmpty: Bool {
        spansBySection.allSatisfy(\.isEmpty)
    }
}
