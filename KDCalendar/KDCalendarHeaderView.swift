//
//  KDCalendarHeaderView.swift
//  KDCalendar
//
//  Created by Michael Michailidis on 07/04/2015.
//  Copyright (c) 2015 Karmadust. All rights reserved.
//

import UIKit

class KDCalendarHeaderView: UIView {
    
    var monthLabel : UILabel {
        let lbl = UILabel()
        lbl.textAlignment = NSTextAlignment.Center
        lbl.textColor = UIColor.grayColor()
        self.addSubview(lbl)
        return lbl
    }
    var dayLabelContainerView : UIView {
        
        let v = UIView()
        
        let formatter : NSDateFormatter = NSDateFormatter()
        
        for index in 1...7 {
            
            let day : NSString = formatter.weekdaySymbols[index % 7] as NSString
            
            let weekdayLabel = UILabel()
            
            weekdayLabel.text = day.substringToIndex(2).uppercaseString
            weekdayLabel.textColor = UIColor.grayColor()
            weekdayLabel.textAlignment = NSTextAlignment.Center
            
            v.addSubview(weekdayLabel)
        }
        
        self.addSubview(v)
        
        return v
        
    }
    
    
    override init(frame: CGRect) {
        super.init(frame: frame)
    }

    required init(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
    
    
    override func layoutSubviews() {
        
        super.layoutSubviews()
        
        var frm = self.bounds
        frm.size.height /= 2.0
        self.monthLabel.frame = frm
        
        var labelFrame = CGRect(x: 0.0, y: self.bounds.size.height / 2.0, width: self.bounds.size.width / 7.0, height: self.bounds.size.height / 2.0)
        
        for lbl in self.dayLabelContainerView.subviews as [UIView] {
            
            lbl.frame = labelFrame
            labelFrame.origin.x += labelFrame.size.width
        }
        
        
        
    }
    
}
