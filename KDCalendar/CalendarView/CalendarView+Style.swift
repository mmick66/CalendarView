//
//  CalendarView+Style.swift
//  CalendarView
//
//  Created by Vitor Mesquita on 17/01/2018.
//  Copyright © 2018 Karmadust. All rights reserved.
//

import UIKit

extension CalendarView {
    
    public class Style {
        
        public static var Default: Style = Style()
        
        public enum CellShapeOptions {
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
        
        public enum FirstWeekdayOptions{
            case sunday
            case monday
        }
        
        public enum CellOutOfRangeDisplayOptions {
            case normal
            case hidden
            case grayed
        }
        
        public init()
        {
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
        
        //TimeZone Calendar Style
        public var timeZone: TimeZone {
            get { return calendar.timeZone }
            set { calendar.timeZone = newValue }
        }
        
        //Calendar Identifier Style
        public lazy var calendar: Calendar   = {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(abbreviation: "UTC")!
            return calendar
        }()
    }
}
