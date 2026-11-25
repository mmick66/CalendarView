import Foundation

extension Calendar {

    /// This calendar with the settings it has now.
    ///
    /// An autoupdating calendar, such as `Calendar.autoupdatingCurrent`, would follow later changes
    /// to the user's settings. So would a calendar of the caller's own whose time zone is
    /// `TimeZone.autoupdatingCurrent` or whose locale is `Locale.autoupdatingCurrent`, and it would
    /// still compare equal to what it was before the change. A fixed calendar follows nothing, so
    /// two of them are equal only when they compute the same dates.
    var fixed: Calendar {
        var calendar = self
        if self == .autoupdatingCurrent {
            calendar = Calendar(identifier: identifier)
            calendar.locale = locale
            calendar.timeZone = timeZone
            calendar.firstWeekday = firstWeekday
            calendar.minimumDaysInFirstWeek = minimumDaysInFirstWeek
        }
        if calendar.timeZone == .autoupdatingCurrent {
            calendar.timeZone = TimeZone(identifier: calendar.timeZone.identifier) ?? .current
        }
        if calendar.locale == .autoupdatingCurrent {
            // `Locale.current` keeps the user's own settings, which an identifier does not carry.
            calendar.locale = .current
        }
        return calendar
    }
}
