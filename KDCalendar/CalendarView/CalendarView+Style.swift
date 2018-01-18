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
        
        //Event
        public static var cellEventColor = UIColor(red: 254.0/255.0, green: 73.0/255.0, blue: 64.0/255.0, alpha: 0.8)
        
        //Header
        public static var headerHeight: CGFloat = 80.0
        public static var headerTextColor = UIColor.gray
        public static var headerFontName: String = "Helvetica"
        
        //Common
        public static var cellShape = CellShapeOptions.bevel(4.0)
        
        //Default Style
        public static var cellColorDefault = UIColor(white: 0.0, alpha: 0.1)
        public static var cellTextColorDefault = UIColor.gray
        
        //Today Style
        public static var cellTextColorToday = UIColor.gray
        public static var cellColorToday = UIColor(red: 254.0/255.0, green: 73.0/255.0, blue: 64.0/255.0, alpha: 0.3)
        
        //Selected Style
        public static var cellSelectedBorderColor = UIColor(red: 254.0/255.0, green: 73.0/255.0, blue: 64.0/255.0, alpha: 0.8)
        public static var cellSelectedBorderWidth: CGFloat = 1
        public static var cellSelectedColor = UIColor.clear
        public static var cellSelectedTextColor = UIColor.black
        
        //Before Today Style
        public static var cellBeforeTodayTextColor = cellTextColorDefault
    }
}
