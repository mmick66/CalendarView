/*
 * CalendarView.swift
 * Created by Michael Michailidis on 02/04/2015.
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
import EventKit

let cellReuseIdentifier = "CalendarDayCell"

let NUMBER_OF_DAYS_IN_WEEK = 7
let MAXIMUM_NUMBER_OF_ROWS = 6

let HEADER_DEFAULT_HEIGHT : CGFloat = 80.0


let FIRST_DAY_INDEX = 0
let NUMBER_OF_DAYS_INDEX = 1
let DATE_SELECTED_INDEX = 2

struct EventLocation {
    let title: String
    let latitude: Double
    let longitude: Double
}

struct CalendarEvent {
    let title: String
    let startDate: Date
    let endDate:Date
}



protocol CalendarViewDataSource {
    func startDate() -> Date
    func endDate() -> Date
}

extension CalendarViewDataSource {
    
    func startDate() -> Date {
        return Date()
    }
    func endDate() -> Date {
        return Date()
    }
}

protocol CalendarViewDelegate {
    
    /* optional */ func calendar(_ calendar : CalendarView, canSelectDate date : Date) -> Bool
    func calendar(_ calendar : CalendarView, didScrollToMonth date : Date) -> Void
    func calendar(_ calendar : CalendarView, didSelectDate date : Date, withEvents events: [CalendarEvent]) -> Void
    /* optional */ func calendar(_ calendar : CalendarView, didDeselectDate date : Date) -> Void
}

extension CalendarViewDelegate {
    func calendar(_ calendar : CalendarView, canSelectDate date : Date) -> Bool { return true }
    func calendar(_ calendar : CalendarView, didDeselectDate date : Date) -> Void { return }
}


class CalendarView: UIView {
    
    var dataSource  : CalendarViewDataSource?
    var delegate    : CalendarViewDelegate?
    
    lazy var gregorian : Calendar = {
        
        var cal = Calendar(identifier: Calendar.Identifier.gregorian)
        
        cal.timeZone = TimeZone(abbreviation: "UTC")!
        
        return cal
    }()
    
    var calendar : Calendar {
        return self.gregorian
    }
    
    var direction : UICollectionViewScrollDirection = .horizontal {
        didSet {
            if let layout = self.calendarView.collectionViewLayout as? CalendarFlowLayout {
                layout.scrollDirection = direction
                self.calendarView.reloadData()
            }
        }
    }
    
    internal var startDateCache : Date = Date()
    internal var endDateCache : Date = Date()
    internal var startOfMonthCache : Date = Date()
    internal var todayIndexPath : IndexPath?
    var displayDate : Date?
    
    internal(set) var selectedIndexPaths : [IndexPath] = [IndexPath]()
    internal(set) var selectedDates : [Date] = [Date]()
    
    var allowMultipleSelection : Bool = false {
        didSet {
            self.calendarView.allowsMultipleSelection = allowMultipleSelection
        }
    
    }
    

    internal var eventsByIndexPath : [IndexPath:[CalendarEvent]] = [IndexPath:[CalendarEvent]]()

    var events : [EKEvent]? {
        
        didSet {
            
            self.eventsByIndexPath = [IndexPath:[CalendarEvent]]()
            
            guard let events = events else { return }
            
            let secondsFromGMTDifference = TimeInterval(TimeZone.current.secondsFromGMT())
            
            for event in events {
                
                if event.isOneDay == false {
                    return
                }
                let startDate = event.startDate.addingTimeInterval(secondsFromGMTDifference)
                let endDate = event.endDate.addingTimeInterval(secondsFromGMTDifference)
                
                // Get the distance of the event from the start
                let distanceFromStartComponent = self.gregorian.dateComponents([.month, .day], from:startOfMonthCache, to: startDate)
                
                guard let daysDistanceFromStart = distanceFromStartComponent.day,
                    let monthsDistanceFromStart = distanceFromStartComponent.month else { return }
                
                let calendarEvent = CalendarEvent(title: event.title, startDate: startDate, endDate: endDate)
                
                let indexPath = IndexPath(item: daysDistanceFromStart, section: monthsDistanceFromStart)
                
                if eventsByIndexPath[indexPath] != nil {
                    eventsByIndexPath[indexPath]!.append(calendarEvent)
                }
                else {
                    eventsByIndexPath[indexPath] = [calendarEvent]
                }
            }
            
            DispatchQueue.main.async { self.calendarView.reloadData() }
        }
    }
    
    lazy var headerView : CalendarHeaderView = {
       
        let hv = CalendarHeaderView(frame:CGRect.zero)
        
        return hv
        
    }()
    
    lazy var calendarView : UICollectionView = {
     
        let layout = CalendarFlowLayout()
        layout.scrollDirection = self.direction;
        layout.minimumInteritemSpacing = 0
        layout.minimumLineSpacing = 0
        
        let cv = UICollectionView(frame: CGRect.zero, collectionViewLayout: layout)
        cv.dataSource       = self
        cv.delegate         = self
        cv.isPagingEnabled  = true
        cv.backgroundColor  = UIColor.clear
        cv.showsHorizontalScrollIndicator = false
        cv.showsVerticalScrollIndicator = false
        cv.allowsMultipleSelection = true
        
        return cv
        
    }()
    
    var flowLayout: CalendarFlowLayout {
        return self.calendarView.collectionViewLayout as! CalendarFlowLayout
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        let heigh = self.frame.size.height - HEADER_DEFAULT_HEIGHT
        let width = self.frame.size.width
        
        self.headerView.frame   = CGRect(x:0.0, y:0.0, width: width, height:HEADER_DEFAULT_HEIGHT)
        self.calendarView.frame = CGRect(x:0.0, y:HEADER_DEFAULT_HEIGHT, width: width, height: heigh)
        
        flowLayout.itemSize = CGSize(
            width:  round(width / CGFloat(NUMBER_OF_DAYS_IN_WEEK)),
            height: round(heigh / CGFloat(MAXIMUM_NUMBER_OF_ROWS))
        )
        
        flowLayout.invalidateLayout()
        
        self.reloadData()
        
    }
    
    override init(frame: CGRect) {
        super.init(frame :frame)
        self.createSubviews()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
    
    override func awakeFromNib() {
        super.awakeFromNib()
        self.createSubviews()
    }
    
    // MARK: Setup 
    
    fileprivate func createSubviews() {
        
        self.clipsToBounds = true
        
        // Register Class
        self.calendarView.register(CalendarDayCell.self, forCellWithReuseIdentifier: cellReuseIdentifier)
        self.calendarView.allowsMultipleSelection = allowMultipleSelection
        
        self.addSubview(self.headerView)
        self.addSubview(self.calendarView)
    }
    
    
    var monthInfo : [Int:[Int]] = [Int:[Int]]()
    
    @discardableResult
    func calculateDateBasedOnScrollViewPosition() -> Date? {
        
        let cvbounds = self.calendarView.bounds
        
        var page : Int = 0
        
        switch self.direction {
            
        case .horizontal:
            page = Int(floor(self.calendarView.contentOffset.x / cvbounds.size.width))
            break
            
        case .vertical:
            page = Int(floor(self.calendarView.contentOffset.y / cvbounds.size.height))
            break
        }
        page = page > 0 ? page : 0
        
        var monthsOffsetComponents = DateComponents()
        monthsOffsetComponents.month = page
        
        guard let yearDate = self.gregorian.date(byAdding: monthsOffsetComponents, to: self.startOfMonthCache) else { return nil }
        
        let month = self.gregorian.component(.month, from: yearDate) // get month
        
        let monthName = DateFormatter().monthSymbols[(month-1) % 12] // 0 indexed array
        
        let year = self.gregorian.component(.year, from: yearDate)
        
        
        self.headerView.monthLabel.text = monthName + " " + String(year)
        
        self.displayDate = yearDate
        
        return yearDate;
        
    }
    
    
    // MARK: UICollectionViewDelegate
    
    internal var dateBeingSelectedByUser : Date?

    func selectDate(_ date : Date) {
        
        guard let indexPath = self.indexPathForDate(date) else {
            return
        }
        
        guard self.calendarView.indexPathsForSelectedItems?.contains(indexPath) == false else {
            return
        }
        
        self.calendarView.selectItem(at: indexPath, animated: false, scrollPosition: UICollectionViewScrollPosition())
        
        selectedIndexPaths.append(indexPath)
        selectedDates.append(date)
        
    }
    
    func deselectDate(_ date : Date) {
        
        guard let indexPath = self.indexPathForDate(date) else { return }
        
        guard self.calendarView.indexPathsForSelectedItems?.contains(indexPath) == true else { return }
        
        self.calendarView.deselectItem(at: indexPath, animated: false)
        
        guard let index = selectedIndexPaths.index(of: indexPath) else { return }
        
        selectedIndexPaths.remove(at: index)
        selectedDates.remove(at: index)
        
    }
    
    func indexPathForDate(_ date : Date) -> IndexPath? {
        
        let distanceFromStartComponent = self.gregorian.dateComponents([.month, .day], from:startOfMonthCache, to:date)
        
        guard
            let month = distanceFromStartComponent.month,
            let currentMonthInfo = monthInfo[month] else { return nil }
        
        let item        = distanceFromStartComponent.day! + currentMonthInfo[FIRST_DAY_INDEX]
        let indexPath   = IndexPath(item: item, section: month)
        
        return indexPath
        
    }
    
    func reloadData() {
        self.calendarView.reloadData()
    }
    
    
    func setDisplayDate(_ date : Date, animated: Bool) {
        
        if let dispDate = self.displayDate {
            
            // skip is we are trying to set the same date
            if  date.compare(dispDate) == ComparisonResult.orderedSame { return }
            
            // check if the date is within range
            guard date.isBetween(startDateCache, and: endDateCache) else { return }
            
            guard date.compare(startDateCache) != .orderedAscending && date.compare(endDateCache) != .orderedDescending else { return }
            
            let difference = (self.gregorian as NSCalendar).components([NSCalendar.Unit.month], from: startOfMonthCache, to: date, options: NSCalendar.Options())
            
            let distance : CGFloat = CGFloat(difference.month!) * self.calendarView.frame.size.width
            
            self.calendarView.setContentOffset(CGPoint(x: distance, y: 0.0), animated: animated)
            
            self.calculateDateBasedOnScrollViewPosition()
        }
        
    }

}


extension CalendarView {

    func goToMonthWithOffet(_ offset: Int){
        
        guard let displayDate = self.displayDate else { return }
        
        var dateComponents = DateComponents()
        dateComponents.month = offset;
        
        if let newDate = self.calendar.date(byAdding: dateComponents, to: displayDate) {
            self.setDisplayDate(newDate, animated: true)
        }
    }
    
    func goToNextMonth(){
        goToMonthWithOffet(1)
    }
    func goToPreviousMonth(){
        goToMonthWithOffet(-1)
    }
    

}
