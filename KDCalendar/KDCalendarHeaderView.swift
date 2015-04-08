//
//  KDCalendarHeaderView.swift
//  KDCalendar
//
//  Created by Michael Michailidis on 07/04/2015.
//  Copyright (c) 2015 Karmadust. All rights reserved.
//

import UIKit

class KDCalendarHeaderView: UICollectionReusableView {
    
    var monthLabel : UILabel = UILabel()
    
    override init(frame: CGRect) {
        
        super.init(frame: frame)
        
        var frm = self.bounds
        frm.size.height /= 2.0
        monthLabel.frame = frm
        
        monthLabel.textAlignment = NSTextAlignment.Center
        
        self.addSubview(monthLabel)
        
        
        let formatter = NSDateFormatter()
        
        
        var labelFrame = CGRect(x: 0.0, y: self.bounds.size.height / 2.0, width: self.bounds.size.width / 7.0, height: self.bounds.size.height / 2.0)
        
        for symbol in formatter.weekdaySymbols as [NSString] {
            
            let weekdayLabel = UILabel(frame: labelFrame)
            
            weekdayLabel.text = symbol.substringToIndex(2).uppercaseString
            weekdayLabel.textColor = UIColor.whiteColor()
            weekdayLabel.textAlignment = NSTextAlignment.Center
            self.addSubview(weekdayLabel)
            
            labelFrame.origin.x += labelFrame.size.width
        }
        
    }

    required init(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
        
}
