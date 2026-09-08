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
    public struct Style: Sendable {

        /// The out-of-the-box style.
        public static let `default` = Style()

        @available(*, deprecated, renamed: "default", message: "Style is a value now; use Style.default and assign a modified copy to the view.")
        public static var Default: Style { .default }

        public enum CellShapeOptions: Sendable, Equatable {
            case round
            case square
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

        public enum CellOutOfRangeDisplayOptions: Sendable {
            case normal
            case hidden
            case grayed
        }

        public enum WeekDaysTransform: Sendable {
            case capitalized, uppercase
        }

        public init() {
        }

        //Event
        public var cellEventColor            = UIColor(red: 254.0/255.0, green: 73.0/255.0, blue: 64.0/255.0, alpha: 0.8)

        //Header
        public var headerHeight: CGFloat     = 80.0
        public var headerTopMargin: CGFloat  = 5.0
        public var headerTextColor           = UIColor.gray
        public var headerBackgroundColor     = UIColor.white
        public var headerFont                = UIFont.systemFont(ofSize: 20) // Used for the month

        public var weekdaysTopMargin: CGFloat     = 5.0
        public var weekdaysBottomMargin: CGFloat  = 5.0
        public var weekdaysHeight: CGFloat        = 35.0
        public var weekdaysTextColor              = UIColor.gray
        public var weekdaysBackgroundColor        = UIColor.white
        public var weekdaysFont                   = UIFont.systemFont(ofSize: 14) // Used for days of the week

        //Common
        public var cellShape                 = CellShapeOptions.bevel(4.0)

        public var firstWeekday              = FirstWeekdayOptions.monday
        public var showAdjacentDays          = false

        //Default Style
        public var cellColorDefault          = UIColor(white: 0.0, alpha: 0.1)
        public var cellTextColorDefault      = UIColor.gray
        public var cellBorderColor           = UIColor.clear
        public var cellBorderWidth           = CGFloat(0.0)
        public var cellFont                  = UIFont.systemFont(ofSize: 17)

        //Today Style
        public var cellTextColorToday        = UIColor.gray
        public var cellColorToday            = UIColor(red: 254.0/255.0, green: 73.0/255.0, blue: 64.0/255.0, alpha: 0.3)
        public var cellColorOutOfRange       = UIColor(white: 0.0, alpha: 0.5)
        public var cellColorAdjacent         = UIColor.clear

        //Selected Style
        public var cellSelectedBorderColor   = UIColor(red: 254.0/255.0, green: 73.0/255.0, blue: 64.0/255.0, alpha: 0.8)
        public var cellSelectedBorderWidth   = CGFloat(2.0)
        public var cellSelectedColor         = UIColor.clear
        public var cellSelectedTextColor     = UIColor.black

        //Weekend Style
        public var cellTextColorWeekend      = UIColor(red:1.00, green:0.84, blue:0.65, alpha:1.00)

        //Locale Style
        public var locale                    = Locale.current

        /// The calendar, and with it the time zone, every date is interpreted in. Defaults to
        /// the user's current calendar. Set a Gregorian calendar in UTC to get the 1.x behaviour.
        public var calendar: Calendar = Calendar.current

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
