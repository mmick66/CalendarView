/*
 * CalendarView+Style.swift
 * Created by Vitor Mesquita on 17/01/2018.
 * http://blog.karmadust.com/
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 *
 */

import UIKit

extension CalendarView {

    /// The look of a calendar: colours, fonts, cell shape, first weekday, locale and calendar.
    ///
    /// `Style` is a value. Assign one to ``CalendarView/style`` and the view restyles itself;
    /// mutating `calendarView.style.cellColorToday` in place works the same way.
    ///
    /// The default colours are dynamic system colours, so a calendar follows dark mode without
    /// any work. The default fonts scale with Dynamic Type; a custom font is used as given.
    ///
    /// ## Comparing styles
    ///
    /// Two styles are equal when every property is. ``KDCalendarView`` counts on it: an update of
    /// the SwiftUI view hands the calendar its style, which reloads the calendar, only when that
    /// style differs from the one the calendar has.
    ///
    /// Colours decide most comparisons, and `UIColor` compares a colour made with
    /// `UIColor { traits in ... }` by identity: two such colours are equal only when they are
    /// the same object, whatever their closures return. A style built in a SwiftUI `body` with a
    /// new `UIColor { traits in ... }` each time therefore never equals the one before it, and
    /// every update of the view reloads the calendar.
    ///
    /// Make a dynamic colour once and keep it, in a `static let` for instance, rather than where
    /// the style is built. The default style shares one such colour for this reason. System
    /// colours such as `UIColor.label` and colours with fixed components compare by value and
    /// need no such care.
    ///
    /// ```swift
    /// extension UIColor {
    ///     // Made once: every style that uses it compares equal.
    ///     static let dayBackground = UIColor { traits in
    ///         traits.userInterfaceStyle == .dark ? .darkGray : .lightGray
    ///     }
    /// }
    ///
    /// var style = CalendarView.Style()
    /// style.cellColorDefault = .dayBackground
    /// ```
    public struct Style: Sendable, Equatable {

        /// The out-of-the-box style.
        public static let `default` = Style()

        /// One shared dynamic colour, so two default styles compare equal: `UIColor` compares a
        /// colour made from a closure by identity.
        private static let defaultCellColor = UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(white: 1.0, alpha: 0.1) : UIColor(white: 0.0, alpha: 0.1)
        }

        /// The default style; renamed ``default``.
        @available(
            *, deprecated, renamed: "default",
            message: "Style is a value now; use Style.default and assign a modified copy to the view."
        )
        public static var Default: Style { .default }

        /// The shape of a day's background.
        public enum CellShape: Sendable, Equatable {
            /// A circle inscribed in the cell.
            case round
            /// The full cell rectangle with square corners.
            case square
            /// A rectangle with the given corner radius.
            case bevel(CGFloat)

            /// The frame of the background inside `rect`: the largest centred square for
            /// ``round``, `rect` itself otherwise.
            func backgroundFrame(in rect: CGRect) -> CGRect {
                guard case .round = self else { return rect }
                let side = min(rect.width, rect.height)
                return rect.insetBy(dx: (rect.width - side) / 2, dy: (rect.height - side) / 2)
            }

            /// The corner radius of a background with the given frame, from
            /// ``backgroundFrame(in:)``.
            func cornerRadius(for frame: CGRect) -> CGFloat {
                switch self {
                case .square:
                    return 0
                case .round:
                    return frame.width / 2
                case .bevel(let radius):
                    return radius
                }
            }
        }

        /// The day the week starts on in the grid and the header.
        public enum FirstWeekday: Sendable {
            case sunday
            case monday
            case saturday
            /// The first weekday of ``Style/resolvedCalendar``: the calendar's own, which follows
            /// its locale, or ``Style/locale``'s when the calendar has no locale.
            case automatic
        }

        /// How days outside the range would be shown; the view never read it.
        @available(
            *, deprecated,
            message: "Never used by the view; days outside the range are always styled with cellColorOutOfRange."
        )
        public enum CellOutOfRangeDisplayOptions: Sendable {
            case normal
            case hidden
            case grayed
        }

        /// The letter case of the weekday labels in the header.
        public enum WeekdayCasing: Sendable {
            /// Each word of a label starts with a capital, as in "Mon".
            case capitalized
            /// Each label in capitals.
            case uppercase
        }

        /// The shape of a day's background; renamed ``CellShape``.
        @available(*, deprecated, renamed: "CellShape")
        public typealias CellShapeOptions = CellShape

        /// The day the week starts on; renamed ``FirstWeekday``.
        @available(*, deprecated, renamed: "FirstWeekday")
        public typealias FirstWeekdayOptions = FirstWeekday

        /// The letter case of the weekday labels; renamed ``WeekdayCasing``.
        @available(*, deprecated, renamed: "WeekdayCasing")
        public typealias WeekDaysTransform = WeekdayCasing

        /// Creates the default style, the same as ``default``.
        public init() {
        }

        // MARK: Events

        /// The colour of the dot under a day that has events.
        public var cellEventColor = UIColor(red: 254.0 / 255.0, green: 73.0 / 255.0, blue: 64.0 / 255.0, alpha: 0.8)

        // MARK: Header

        /// The total height of the header, month title and weekday labels included.
        ///
        /// The header is taller than this when its fonts need more room, as the default fonts do
        /// at the larger Dynamic Type sizes. A header given no height at all is left without one.
        public var headerHeight: CGFloat = 80.0
        /// The space above the month title.
        public var headerTopMargin: CGFloat = 5.0
        /// The colour of the month title.
        public var headerTextColor = UIColor.secondaryLabel
        /// The background behind the month title.
        public var headerBackgroundColor = UIColor.systemBackground
        /// The font of the month title.
        ///
        /// Scales with Dynamic Type by default.
        public var headerFont = UIFontMetrics(forTextStyle: .title3).scaledFont(for: UIFont.systemFont(ofSize: 20))

        /// The space above the weekday labels.
        public var weekdaysTopMargin: CGFloat = 5.0
        /// The space below the weekday labels.
        public var weekdaysBottomMargin: CGFloat = 5.0
        /// The height of the weekday labels.
        ///
        /// The labels are taller than this when a line of ``weekdaysFont`` needs more room.
        public var weekdaysHeight: CGFloat = 35.0
        /// The colour of the weekday labels.
        public var weekdaysTextColor = UIColor.secondaryLabel
        /// The background behind the weekday labels.
        public var weekdaysBackgroundColor = UIColor.systemBackground
        /// The font of the weekday labels.
        ///
        /// Scales with Dynamic Type by default.
        public var weekdaysFont = UIFontMetrics(forTextStyle: .footnote).scaledFont(for: UIFont.systemFont(ofSize: 14))

        // MARK: Grid

        /// The shape of every day's background.
        public var cellShape = CellShape.bevel(4.0)

        /// The day the week starts on.
        ///
        /// Monday by default; use `.automatic` to follow the calendar's locale.
        public var firstWeekday = FirstWeekday.monday
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
        /// The font of the day numbers.
        ///
        /// Scales with Dynamic Type by default. A cell too small for the font shows its number
        /// smaller rather than clipped.
        public var cellFont = UIFontMetrics(forTextStyle: .body).scaledFont(for: UIFont.systemFont(ofSize: 17))

        // MARK: Days outside the range or the month

        /// The colour of the day number, not of the cell behind it, for days before the data
        /// source's start date or after its end date.
        ///
        /// A text colour despite its name, like ``cellTextColorDefault``; such a day keeps the
        /// background of an ordinary day, ``cellColorDefault``.
        public var cellColorOutOfRange = UIColor.tertiaryLabel
        /// The colour of the day number, not of the cell behind it, for the neighbouring months'
        /// days shown when ``showAdjacentDays`` is on.
        ///
        /// A text colour despite its name, like ``cellTextColorDefault``; such a day has no
        /// background.
        public var cellColorAdjacent = UIColor.quaternaryLabel

        // MARK: Today

        /// The text colour of today.
        public var cellTextColorToday = UIColor.secondaryLabel
        /// The background of today.
        public var cellColorToday = UIColor(red: 254.0 / 255.0, green: 73.0 / 255.0, blue: 64.0 / 255.0, alpha: 0.3)

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

        /// The locale for the month title, the weekday labels and what VoiceOver reads for a day.
        ///
        /// Defaults to the user's locale, following it when it changes. VoiceOver reads a day's
        /// date in this locale, and "Today" and the number of events in the same language when
        /// the library is localized in it; otherwise those words are in the app's language.
        public var locale = Locale.autoupdatingCurrent

        /// The calendar, and with it the time zone, every date is interpreted in.
        ///
        /// Defaults to the user's calendar, following it when it changes, so the grid and today's
        /// marker move with the device's time zone. Set a Gregorian calendar in UTC to get the 1.x
        /// behaviour.
        public var calendar: Calendar = Calendar.autoupdatingCurrent

        /// The letter case of the weekday labels.
        public var weekdayCasing = WeekdayCasing.capitalized

        /// The letter case of the weekday labels; renamed ``weekdayCasing``.
        @available(*, deprecated, renamed: "weekdayCasing")
        public var weekDayTransform: WeekdayCasing {
            get { weekdayCasing }
            set { weekdayCasing = newValue }
        }

        /// ``calendar``, given ``locale`` when it has no locale of its own so that weekends, week
        /// numbering and the automatic first weekday follow the locale.
        public var resolvedCalendar: Calendar {
            var calendar = calendar
            if calendar.locale == nil || calendar.locale?.identifier.isEmpty == true {
                calendar.locale = locale
            }
            return calendar
        }

        /// The first weekday as a `Calendar` weekday number, 1 for Sunday through 7 for Saturday.
        public var effectiveFirstWeekday: Int {
            switch firstWeekday {
            case .sunday: return 1
            case .monday: return 2
            case .saturday: return 7
            case .automatic: return resolvedCalendar.firstWeekday
            }
        }
    }
}
