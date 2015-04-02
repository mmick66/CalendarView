//
//  KDCalendarDayCell.swift
//  KDCalendar
//
//  Created by Michael Michailidis on 02/04/2015.
//  Copyright (c) 2015 Karmadust. All rights reserved.
//

import UIKit

class KDCalendarDayCell: UICollectionViewCell {
    
    var textLabel : UILabel {
       
        let lbl = UILabel()
        lbl.textAlignment = NSTextAlignment.Center
        return lbl
        
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
