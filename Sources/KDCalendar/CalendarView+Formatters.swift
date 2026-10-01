import Foundation

extension CalendarView {

    /// The formatters for the month title, the weekday labels and VoiceOver, built once per style
    /// and calendar rather than per month or per cell.
    ///
    /// They all use the calendar the grid is laid out in, ``CalendarView/layoutCalendar``, so the
    /// text always names the days the grid shows.
    struct Formatters {
        /// The month and year shown in the header, such as "February 2024".
        let monthTitle: DateFormatter
        /// The full date read out by VoiceOver, such as "Monday, January 15, 2024".
        let accessibility: DateFormatter
        /// The short weekday names, Sunday first.
        let weekdaySymbols: [String]

        /// The formatters for the days of `calendar`, named in `locale`.
        init(calendar: Calendar, locale: Locale) {
            func formatter() -> DateFormatter {
                let formatter = DateFormatter()
                formatter.calendar = calendar
                formatter.timeZone = calendar.timeZone
                formatter.locale = locale
                return formatter
            }

            monthTitle = formatter()
            monthTitle.setLocalizedDateFormatFromTemplate("yMMMM")

            accessibility = formatter()
            accessibility.dateStyle = .full
            accessibility.timeStyle = .none

            weekdaySymbols = formatter().shortWeekdaySymbols ?? []
        }
    }
}
