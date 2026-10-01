import Foundation

/// An event shown as a dot on every day it covers.
public struct CalendarEvent: Sendable, Hashable {
    /// The event's name.
    public let title: String
    /// When the event begins; its day is the first one marked.
    public let startDate: Date
    /// When the event ends; its day is the last one marked.
    public let endDate: Date

    /// Creates an event from its title and the interval it covers.
    public init(title: String, startDate: Date, endDate: Date) {
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
    }
}
