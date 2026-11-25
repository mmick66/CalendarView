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
        /// The short weekday names, Sunday first, in the form that stands alone as a column
        /// heading rather than inside a date: "Mo" in German, not "Mo.".
        let weekdaySymbols: [String]
        /// The shortest weekday names, Sunday first, such as "M", for columns too narrow for
        /// ``weekdaySymbols``.
        let narrowWeekdaySymbols: [String]
        /// The full weekday names, Sunday first, such as "Monday", which VoiceOver reads for a
        /// column heading.
        let weekdayNames: [String]
        /// Where the words VoiceOver adds to a date are looked up: the library's strings in the
        /// language of the locale, so the whole label is spoken in one language, or the library's
        /// bundle, which answers in the app's language, when the library has no such strings.
        let stringsBundle: Bundle
        /// The locale whose plural rules pick the form of a count read from ``stringsBundle``: the
        /// style's locale for its own strings, and otherwise the language the bundle answers in,
        /// which is the app's and not always the device's.
        let stringsLocale: Locale

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
            if Self.yearsRestartWithEachEra(in: calendar) {
                // The template is filled in for the locale's own calendar, Gregorian as a rule,
                // whose format has no era. Asked for this calendar, the locale gives the format
                // that names the year: "January Reiwa 6", not "January 6".
                var components = Locale.Components(locale: locale)
                components.calendar = calendar.identifier
                let ownFormat = DateFormatter.dateFormat(
                    fromTemplate: "yMMMM", options: 0, locale: Locale(components: components))
                if let ownFormat {
                    monthTitle.dateFormat = ownFormat
                }
            }

            accessibility = formatter()
            accessibility.dateStyle = .full
            accessibility.timeStyle = .none

            let symbols = formatter()
            weekdaySymbols = symbols.shortStandaloneWeekdaySymbols ?? []
            narrowWeekdaySymbols = symbols.veryShortStandaloneWeekdaySymbols ?? []
            weekdayNames = symbols.standaloneWeekdaySymbols ?? []

            if let strings = Bundle.kdCalendarStrings(for: locale) {
                stringsBundle = strings
                stringsLocale = locale
            } else {
                stringsBundle = .kdCalendar
                stringsLocale = Bundle.kdCalendarLocale
            }
        }

        /// Whether `calendar` counts its years from the start of each era, so that a year's number
        /// alone does not say which year it is.
        ///
        /// The Japanese calendar does, with an era per emperor, and so do the Chinese calendar and
        /// its relatives, with an era per sixty years. Calendars with one era, or with the two
        /// either side of an epoch as in the Gregorian calendar, name a year by its number.
        static func yearsRestartWithEachEra(in calendar: Calendar) -> Bool {
            (calendar.maximumRange(of: .era)?.count ?? 0) > 2
        }
    }
}
