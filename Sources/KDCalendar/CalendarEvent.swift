import Foundation

/// An event shown as a dot on every day it covers.
public struct CalendarEvent: Sendable, Hashable {
    public let title: String
    public let startDate: Date
    public let endDate: Date

    public init(title: String, startDate: Date, endDate: Date) {
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
    }
}
