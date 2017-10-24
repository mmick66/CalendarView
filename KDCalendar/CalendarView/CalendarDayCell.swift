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
let borderColor = UIColor(red: 254.0/255.0, green: 73.0/255.0, blue: 64.0/255.0, alpha: 0.8)

class CalendarDayCell: UICollectionViewCell {
    
    @objc var eventsCount = 0 {
        didSet {
            
            self.dotsView.isHidden = eventsCount == 0
            self.setNeedsLayout()
            
        }
    }
    
    
   
    
    @objc var isToday : Bool = false {
        
        didSet {
           
            if isToday == true {
                self.pBackgroundView.backgroundColor = cellColorToday
            }
            else {
                self.pBackgroundView.backgroundColor = cellColorDefault
            }
        }
    }
    
    override var isSelected : Bool {
        
        didSet {
            
            if isSelected == true {
                self.pBackgroundView.layer.borderWidth = 2.0
                
            }
            else {
                self.pBackgroundView.layer.borderWidth = 0.0
            }
            
        }
    }
    
     @objc lazy var pBackgroundView : UIView = {
        
        var vFrame = self.frame.insetBy(dx: 3.0, dy: 3.0)
        
        let view = UIView(frame: vFrame)
        
        view.layer.cornerRadius = 4.0
        
        view.layer.borderColor = borderColor.cgColor
        view.layer.borderWidth = 0.0
        
        view.center = CGPoint(x: self.bounds.size.width * 0.5, y: self.bounds.size.height * 0.5)
        
        view.backgroundColor = cellColorDefault
        
        
        return view
    }()
    
    @objc lazy var textLabel : UILabel = {
       
        let lbl = UILabel()
        lbl.textAlignment = NSTextAlignment.center
        lbl.textColor = UIColor.darkGray
        
        return lbl
        
    }()
    
    
    @objc lazy var dotsView : UIView = {
        
        let dv = UIView()
        dv.backgroundColor = borderColor
        return dv
        
    }()

    override init(frame: CGRect) {
        
        super.init(frame: frame)
        
        self.addSubview(self.pBackgroundView)
        self.textLabel.frame = self.bounds
        self.addSubview(self.textLabel)
        self.addSubview(self.dotsView)
        
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        let dotFactor : CGFloat = 0.07
        let size = self.bounds.height*dotFactor
        self.dotsView.frame = CGRect(x: 0, y: 0, width: size, height: size)
        self.dotsView.center = CGPoint(x: self.textLabel.center.x, y: self.bounds.height - 3*size)
        self.dotsView.layer.cornerRadius = size * 0.5
//        let validSize = self.bounds.height >= self.bounds.width
//        assert(validSize, "The cell mustbe taller than the width")
        
        
    }
    
    
    
    
}
