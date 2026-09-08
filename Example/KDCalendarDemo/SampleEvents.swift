import Foundation
import KDCalendar

/// A handful of events around today, for screens that should show dots without calendar access.
enum SampleEvents {

    static func around(_ date: Date = Date(), calendar: Calendar = .current) -> [CalendarEvent] {
        func day(_ offset: Int, hour: Int = 9, length: Int = 1) -> CalendarEvent {
            let start = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: date))!
                .addingTimeInterval(TimeInterval(hour * 3600))
            let end = start.addingTimeInterval(TimeInterval(length * 3600))
            return CalendarEvent(title: "Sample \(offset)", startDate: start, endDate: end)
        }
        return [
            day(-3), day(-3, hour: 14), day(1), day(2, hour: 18), day(5),
            CalendarEvent(
                title: "Three-day sample",
                startDate: calendar.date(byAdding: .day, value: 8, to: calendar.startOfDay(for: date))!,
                endDate: calendar.date(byAdding: .day, value: 11, to: calendar.startOfDay(for: date))!),
            day(14), day(21, hour: 8),
        ]
    }
}
