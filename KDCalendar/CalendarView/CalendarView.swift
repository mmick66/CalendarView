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
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(abbreviation: "UTC")!
        return cal
    }()
    
    var calendar : Calendar {
        return self.gregorian
    }
    
    var direction : UICollectionViewScrollDirection = .horizontal {
        didSet {
            flowLayout.scrollDirection = direction
            self.collectionView.reloadData()
        }
    }
    
    internal var startDateCache     = Date()
    internal var endDateCache       = Date()
    internal var startOfMonthCache  = Date()
    
    internal var todayIndexPath: IndexPath?
    public var displayDate: Date?
    
    internal(set) var selectedIndexPaths : [IndexPath] = [IndexPath]()
    internal(set) var selectedDates : [Date] = [Date]()
    
    var allowMultipleSelection : Bool = false {
        didSet {
            self.collectionView.allowsMultipleSelection = allowMultipleSelection
        }
    }
    
    internal var eventsByIndexPath : [IndexPath:[CalendarEvent]] = [IndexPath:[CalendarEvent]]()

    var events : [EKEvent]? {
        
        didSet {
            
            self.eventsByIndexPath = [IndexPath:[CalendarEvent]]()
            
            guard let events = events else { return }
            
            let secondsFromGMTDifference = TimeInterval(TimeZone.current.secondsFromGMT())
            
            for event in events {
                
                if !event.isOneDay { continue }
                
                let calendarEvent = CalendarEvent(
                    title:      event.title,
                    startDate:  event.startDate.addingTimeInterval(secondsFromGMTDifference),
                    endDate:    event.endDate.addingTimeInterval(secondsFromGMTDifference)
                )
                
                guard let indexPath = self.indexPathForDate(calendarEvent.startDate) else { continue }
                
                var eventsForIndexPath = eventsByIndexPath[indexPath] ?? []
                eventsForIndexPath.append(calendarEvent)
                eventsByIndexPath[indexPath] = eventsForIndexPath
                
            }
            
            DispatchQueue.main.async { self.collectionView.reloadData() }
        }
    }
    
    var headerView = CalendarHeaderView(frame:CGRect.zero)
    
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        self.createSubviews()
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
    
    override func awakeFromNib() {
        super.awakeFromNib()
        self.createSubviews()
    }
    
    // MARK: Create Subviews
    var collectionView: UICollectionView!
    private func createSubviews() {
        
        self.clipsToBounds = true
        
        let layout = CalendarFlowLayout()
        layout.scrollDirection = self.direction;
        layout.sectionInset = UIEdgeInsets.zero
        layout.minimumInteritemSpacing = 0
        layout.minimumLineSpacing = 0
        layout.itemSize = self.cellSize(in: self.bounds)
        
        self.collectionView                     = UICollectionView(frame: CGRect.zero, collectionViewLayout: layout)
        self.collectionView.dataSource          = self
        self.collectionView.delegate            = self
        self.collectionView.isPagingEnabled     = true
        self.collectionView.backgroundColor     = UIColor.clear
        
        self.collectionView.showsHorizontalScrollIndicator  = false
        self.collectionView.showsVerticalScrollIndicator    = false
        
        self.collectionView.allowsMultipleSelection         = self.allowMultipleSelection
        
        self.collectionView.register(CalendarDayCell.self, forCellWithReuseIdentifier: cellReuseIdentifier)
        
        self.addSubview(self.headerView)
        self.addSubview(self.collectionView)
    }
    
    var flowLayout: CalendarFlowLayout {
        return self.collectionView.collectionViewLayout as! CalendarFlowLayout
    }
    
    override func layoutSubviews() {
        
        super.layoutSubviews()
        
        self.headerView.frame = CGRect(
            x:0.0,
            y:0.0,
            width: self.frame.size.width,
            height: HEADER_DEFAULT_HEIGHT
        )
        
        self.collectionView.frame = CGRect(
            x:0.0,
            y:HEADER_DEFAULT_HEIGHT,
            width: self.frame.size.width,
            height: self.frame.size.height - HEADER_DEFAULT_HEIGHT
        )
        
        flowLayout.itemSize = self.cellSize(in: self.bounds)
        
        self.resetDisplayDate()
        
    }
    
    private func cellSize(in bounds: CGRect) -> CGSize {
        return CGSize(
            width:   frame.size.width / CGFloat(NUMBER_OF_DAYS_IN_WEEK),
            height: (frame.size.height - HEADER_DEFAULT_HEIGHT) / CGFloat(MAXIMUM_NUMBER_OF_ROWS)
        )
    }
    
    
    var monthInfo = [Int:(firstDay:Int, daysTotal:Int)]()
    
    
    // MARK: UICollectionViewDelegate
    
    internal var dateBeingSelectedByUser : Date?

    func selectDate(_ date : Date) {
        
        guard let indexPath = self.indexPathForDate(date) else { return }
        
        guard selectedIndexPaths.contains(indexPath) == false else { return }
        
        self.collectionView.selectItem(at: indexPath, animated: false, scrollPosition: UICollectionViewScrollPosition())
        
        selectedIndexPaths.append(indexPath)
        selectedDates.append(date)
        
    }
    
    func deselectDate(_ date : Date) {
        
        guard let indexPath = self.indexPathForDate(date) else { return }
        
        guard self.collectionView.indexPathsForSelectedItems?.contains(indexPath) == true else { return }
        
        self.collectionView.deselectItem(at: indexPath, animated: false)
        
        guard let index = selectedIndexPaths.index(of: indexPath) else { return }
        
        selectedIndexPaths.remove(at: index)
        selectedDates.remove(at: index)
        
    }
    
    
    func reloadData() {
        self.collectionView.reloadData()
    }
    
    
    func setDisplayDate(_ date : Date, animated: Bool) {
        
        guard (date > startDateCache) && (date < endDateCache) else { return }
        
        self.collectionView.setContentOffset(
            self.scrollViewOffset(in: self.collectionView, for: date),
            animated: animated
        )
        
        self.displayDateOnHeader(date)
        
    }
    
    internal func resetDisplayDate() {
        
        guard let displayDate = self.displayDate else { return }
        
        self.collectionView.setContentOffset(
            self.scrollViewOffset(in: self.collectionView, for: displayDate),
            animated: false
        )
    }
    
    func scrollViewOffset(in collectionView: UICollectionView, for date: Date) -> CGPoint {
        
        var point = CGPoint.zero
        
        guard let sections = self.indexPathForDate(date)?.section else { return point }
        
        switch self.direction {
        case .horizontal:   point.x = CGFloat(sections) * collectionView.frame.size.width
        case .vertical:     point.y = CGFloat(sections) * collectionView.frame.size.height
        }
        
        return point
    }

}

extension CalendarView {
    
    func indexPathForDate(_ date : Date) -> IndexPath? {
        
        let distanceFromStartComponent = self.gregorian.dateComponents([.month, .day], from: startOfMonthCache, to: date)
        
        guard
            let month = distanceFromStartComponent.month,
            let (firstDayIndex, _) = monthInfo[month] else { return nil }
        
        let item        = distanceFromStartComponent.day! + firstDayIndex
        let indexPath   = IndexPath(item: item, section: month)
        
        return indexPath
        
    }
    
    func dateFromIndexPath(_ indexPath: IndexPath) -> Date? {
        
        var components      = DateComponents()
        components.month    = indexPath.section
        components.day      = indexPath.item
        
        return self.calendar.date(byAdding: components, to: self.startDateCache)
        
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
