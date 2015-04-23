//
//  KDCalendarDayCell.swift
//  KDCalendar
//
//  Created by Michael Michailidis on 02/04/2015.
//  Copyright (c) 2015 Karmadust. All rights reserved.
//

import UIKit

let cellColorDefault = UIColor(white: 0.0, alpha: 0.1)
let cellColorToday = UIColor(red: 254.0/255.0, green: 73.0/255.0, blue: 64.0/255.0, alpha: 0.3)

class KDCalendarDayCell: UICollectionViewCell {
    
    var isToday : Bool = false {
        
        didSet {
           
            if isToday == true {
                self.pBackgroundView.backgroundColor = cellColorToday
            }
            else {
                self.pBackgroundView.backgroundColor = cellColorDefault
            }
        }
    }
    
    override var selected : Bool {
        
        didSet {
            
            if selected == true {
                self.pBackgroundView.layer.borderWidth = 2.0
                
            }
            else {
                self.pBackgroundView.layer.borderWidth = 0.0
            }
            
        }
    }
    
     lazy var pBackgroundView : UIView = {
        
        var vFrame = CGRectInset(self.frame, 3.0, 3.0)
        
        let view = UIView(frame: vFrame)
        
        view.layer.cornerRadius = 4.0
        
        view.layer.borderColor = UIColor(red: 254.0/255.0, green: 73.0/255.0, blue: 64.0/255.0, alpha: 0.8).CGColor
        view.layer.borderWidth = 0.0
        
        view.center = CGPoint(x: self.bounds.size.width * 0.5, y: self.bounds.size.height * 0.5)
        
        view.backgroundColor = cellColorDefault
        
        
        return view
    }()
    
    lazy var textLabel : UILabel = {
       
        let lbl = UILabel()
        lbl.textAlignment = NSTextAlignment.Center
        lbl.textColor = UIColor.darkGrayColor()
        
        return lbl
        
    }()
    
    

    override init(frame: CGRect) {
        
        super.init(frame: frame)
        
        self.textLabel.frame = self.bounds
        self.addSubview(self.textLabel)
        
        self.addSubview(self.pBackgroundView)
        
        
        
    }

    required init(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
    
    
}
