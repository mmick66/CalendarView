//
//  CalendarView+Style.swift
//  CalendarView
//
//  Created by Vitor Mesquita on 17/01/2018.
//  Copyright © 2018 Karmadust. All rights reserved.
//

import UIKit

extension CalendarView {
    
    public struct Style {
        
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
        
        //Event
        public static var cellEventColor = UIColor(red: 254.0/255.0, green: 73.0/255.0, blue: 64.0/255.0, alpha: 0.8)
        
        //Header
        public static var headerHeight: CGFloat = 80.0
        public static var headerTextColor = UIColor.gray
        public static var headerFontName: String = "Helvetica"
        public static var headerFontSize: CGFloat = 20.0

        //Common
        public static var cellShape                 = CellShapeOptions.bevel(4.0)
        
        public static var firstWeekday              = FirstWeekdayOptions.monday
        
        //Default Style
        public static var cellColorDefault          = UIColor(white: 0.0, alpha: 0.1)
        public static var cellTextColorDefault      = UIColor.gray
        public static var cellBorderColor           = UIColor.clear
        public static var cellBorderWidth           = CGFloat(0.0)
        
        //Today Style
        public static var cellTextColorToday        = UIColor.gray
        public static var cellColorToday            = UIColor(red: 254.0/255.0, green: 73.0/255.0, blue: 64.0/255.0, alpha: 0.3)
        
        //Selected Style
        public static var cellSelectedBorderColor   = UIColor(red: 254.0/255.0, green: 73.0/255.0, blue: 64.0/255.0, alpha: 0.8)
        public static var cellSelectedBorderWidth   = CGFloat(2.0)
        public static var cellSelectedColor         = UIColor.clear
        public static var cellSelectedTextColor     = UIColor.black
        
        //Weekend Style
        public static var cellTextColorWeekend      = UIColor(red:1.00, green:0.84, blue:0.65, alpha:1.00)
        
        
    }
}
