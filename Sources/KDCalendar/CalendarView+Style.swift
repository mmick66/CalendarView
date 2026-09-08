//
//  CalendarView+Style.swift
//  CalendarView
//
//  Created by Vitor Mesquita on 17/01/2018.
//  Copyright © 2018 Karmadust. All rights reserved.
//

import UIKit

extension CalendarView {

    /// The look of a calendar: colours, fonts, cell shape, first weekday, locale and calendar.
    ///
    /// `Style` is a value. Assign one to ``CalendarView/style`` and the view restyles itself;
    /// mutating `calendarView.style.cellColorToday` in place works the same way.
    ///
    /// The default colours are dynamic system colours, so a calendar follows dark mode without
    /// any work. The default fonts scale with Dynamic Type; a custom font is used as given.
    public struct Style: Sendable, Equatable {

        /// The out-of-the-box style.
        public static let `default` = Style()

        /// One shared dynamic colour, so two default styles compare equal.
        private static let defaultCellColor = UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(white: 1.0, alpha: 0.1) : UIColor(white: 0.0, alpha: 0.1)
        }

        @available(
            *, deprecated, renamed: "default",
            message: "Style is a value now; use Style.default and assign a modified copy to the view."
        )
        public static var Default: Style { .default }

        /// The shape of a day's background.
        public enum CellShapeOptions: Sendable, Equatable {
            /// A circle inscribed in the cell.
            case round
            /// The full cell rectangle with square corners.
            case square
            /// A rectangle with the given corner radius.
            case bevel(CGFloat)
            var isRound: Bool {
                switch self {
                case .round:
                    return true
                default:
                    return false
                }
            }
        }

        /// The day the week starts on in the grid and the header.
        public enum FirstWeekdayOptions: Sendable {
            case sunday
            case monday
            case saturday
            /// The first weekday of ``Style/calendar``, which follows its locale.
            case automatic
        }

        @available(
            *, deprecated,
            message: "Never used by the view; days outside the range are always styled with cellColorOutOfRange."
        )
        public enum CellOutOfRangeDisplayOptions: Sendable {
            case normal
            case hidden
            case grayed
        }

        /// How the weekday labels in the header are cased.
        public enum WeekDaysTransform: Sendable {
            case capitalized, uppercase
        }

        public init() {
        }

        // MARK: Events

        /// The colour of the dot under a day that has events.
        public var cellEventColor = UIColor(red: 254.0 / 255.0, green: 73.0 / 255.0, blue: 64.0 / 255.0, alpha: 0.8)

        // MARK: Header

        /// The total height of the header, month title and weekday labels included.
        public var headerHeight: CGFloat = 80.0
        /// The space above the month title.
        public var headerTopMargin: CGFloat = 5.0
        /// The colour of the month title.
        public var headerTextColor = UIColor.secondaryLabel
        /// The background behind the month title.
        public var headerBackgroundColor = UIColor.systemBackground
        /// The font of the month title. Scales with Dynamic Type by default.
        public var headerFont = UIFontMetrics(forTextStyle: .title3).scaledFont(for: UIFont.systemFont(ofSize: 20))

        /// The space above the weekday labels.
        public var weekdaysTopMargin: CGFloat = 5.0
        /// The space below the weekday labels.
        public var weekdaysBottomMargin: CGFloat = 5.0
        /// The height of the weekday labels.
        public var weekdaysHeight: CGFloat = 35.0
        /// The colour of the weekday labels.
        public var weekdaysTextColor = UIColor.secondaryLabel
        /// The background behind the weekday labels.
        public var weekdaysBackgroundColor = UIColor.systemBackground
        /// The font of the weekday labels. Scales with Dynamic Type by default.
        public var weekdaysFont = UIFontMetrics(forTextStyle: .footnote).scaledFont(for: UIFont.systemFont(ofSize: 14))

        // MARK: Grid

        /// The shape of every day's background.
        public var cellShape = CellShapeOptions.bevel(4.0)

        /// The day the week starts on. Monday by default; use `.automatic` to follow the calendar's locale.
        public var firstWeekday = FirstWeekdayOptions.monday
        /// Whether the empty cells before and after a month show the neighbouring months' days.
        public var showAdjacentDays = false

        // MARK: Days

        /// The background of an ordinary day.
        public var cellColorDefault = Style.defaultCellColor
        /// The text colour of an ordinary day.
        public var cellTextColorDefault = UIColor.secondaryLabel
        /// The border colour of an unselected day.
        public var cellBorderColor = UIColor.clear
        /// The border width of an unselected day.
        public var cellBorderWidth = CGFloat(0.0)
        /// The font of the day numbers. Scales with Dynamic Type by default.
        public var cellFont = UIFontMetrics(forTextStyle: .body).scaledFont(for: UIFont.systemFont(ofSize: 17))

        // MARK: Today

        /// The text colour of today.
        public var cellTextColorToday = UIColor.secondaryLabel
        /// The background of today.
        public var cellColorToday = UIColor(red: 254.0 / 255.0, green: 73.0 / 255.0, blue: 64.0 / 255.0, alpha: 0.3)
        /// The text colour of days before the data source's start date or after its end date.
        public var cellColorOutOfRange = UIColor.tertiaryLabel
        /// The text colour of the neighbouring months' days when ``showAdjacentDays`` is on.
        public var cellColorAdjacent = UIColor.quaternaryLabel

        // MARK: Selection

        /// The border colour of a selected day.
        public var cellSelectedBorderColor = UIColor(
            red: 254.0 / 255.0, green: 73.0 / 255.0, blue: 64.0 / 255.0, alpha: 0.8)
        /// The border width of a selected day.
        public var cellSelectedBorderWidth = CGFloat(2.0)
        /// The background of a selected day.
        public var cellSelectedColor = UIColor.clear
        /// The text colour of a selected day.
        public var cellSelectedTextColor = UIColor.label

        // MARK: Weekends

        /// The text colour of weekend days when ``CalendarView/marksWeekends`` is on.
        public var cellTextColorWeekend = UIColor(
            red: 254.0 / 255.0, green: 73.0 / 255.0, blue: 64.0 / 255.0, alpha: 0.8)

        // MARK: Locale and calendar

        /// The locale for the month title and weekday labels.
        public var locale = Locale.current

        /// The calendar, and with it the time zone, every date is interpreted in. Defaults to
        /// the user's current calendar. Set a Gregorian calendar in UTC to get the 1.x behaviour.
        public var calendar: Calendar = Calendar.current

        /// How the weekday labels are cased.
        public var weekDayTransform = WeekDaysTransform.capitalized

        /// The first weekday as a `Calendar` weekday number, 1 for Sunday through 7 for Saturday.
        public var effectiveFirstWeekday: Int {
            switch firstWeekday {
            case .sunday: return 1
            case .monday: return 2
            case .saturday: return 7
            case .automatic: return calendar.firstWeekday
            }
        }
    }
}
