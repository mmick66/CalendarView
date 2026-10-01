import Foundation

extension Calendar {

    /// This calendar with the settings it has now. An autoupdating calendar, such as
    /// `Calendar.autoupdatingCurrent`, would follow later changes to the user's settings.
    var fixed: Calendar {
        guard self == .autoupdatingCurrent else { return self }
        var calendar = Calendar(identifier: identifier)
        calendar.locale = locale
        calendar.timeZone = timeZone
        calendar.firstWeekday = firstWeekday
        calendar.minimumDaysInFirstWeek = minimumDaysInFirstWeek
        return calendar
    }
}
