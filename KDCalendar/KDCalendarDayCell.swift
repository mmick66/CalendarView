//
//  KDCalendarDayCell.swift
//  KDCalendar
//
//  Created by Michael Michailidis on 02/04/2015.
//  Copyright (c) 2015 Karmadust. All rights reserved.
//

import UIKit

class KDCalendarDayCell: UICollectionViewCell {
    
    
    
     lazy var pBackgroundView : UIView = {
        
        var vFrame = CGRectInset(self.frame, 3.0, 3.0)
        
        let view = UIView(frame: vFrame)
        
        view.layer.cornerRadius = 4.0
        
        view.center = CGPoint(x: self.bounds.size.width * 0.5, y: self.bounds.size.height * 0.5)
        
        self.addSubview(view)
        
        return view
    }()
    
    lazy var textLabel : UILabel = {
       
        let lbl = UILabel()
        lbl.textAlignment = NSTextAlignment.Center
        lbl.textColor = UIColor.darkGrayColor()
        
        return lbl
        
    }()
    
    func setColor(color : UIColor) -> Void {
        self.pBackgroundView.backgroundColor = color
    }

    override init(frame: CGRect) {
        
        super.init(frame: frame)
        
        self.textLabel.frame = self.bounds
        self.addSubview(self.textLabel)
        
    }

    required init(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
    
    
}
