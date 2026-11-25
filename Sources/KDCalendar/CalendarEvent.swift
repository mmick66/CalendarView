import Foundation

/// An event shown as a dot on every day it covers.
///
/// It covers the day it begins on and every later day that starts before it ends, in the calendar
/// of the view that shows it.
public struct CalendarEvent: Sendable, Hashable {
    /// The event's name.
    public let title: String
    /// When the event begins; its day is the first one marked.
    public let startDate: Date
    /// When the event ends; the last day marked is the last one that starts before it.
    ///
    /// An event that ends exactly as a day starts, at midnight, does not mark that day: one from
    /// 22:00 to midnight stays on the day it began. The day the event begins on is always marked,
    /// so an event with no length at midnight still marks its day, and so does one whose end is
    /// before its start.
    public let endDate: Date

    /// Creates an event from its title and the interval it covers.
    public init(title: String, startDate: Date, endDate: Date) {
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
    }
}
