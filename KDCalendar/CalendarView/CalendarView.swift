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
    
    struct Style {
        
        enum CellShapeOptions {
            case Round
            case Square
            case Bevel(CGFloat)
            var isRound: Bool {
                switch self {
                case .Round:
                    return true
                default:
                    return false
                }
            }
        }
        
        static var CellColorDefault         = UIColor(white: 0.0, alpha: 0.1)
        static var CellTextColorDefault     = UIColor.gray
        static var CellTextColorToday       = UIColor.gray
        static var CellColorToday           = UIColor(red: 254.0/255.0, green: 73.0/255.0, blue: 64.0/255.0, alpha: 0.3)
        static var CellBorderColor          = UIColor(red: 254.0/255.0, green: 73.0/255.0, blue: 64.0/255.0, alpha: 0.8)
        static var CellBorderWidth: CGFloat = 2.0
        static var CellShape                = CellShapeOptions.Bevel(4.0)
        
        static var CellEventColor           = UIColor(red: 254.0/255.0, green: 73.0/255.0, blue: 64.0/255.0, alpha: 0.8)
        
        static var HeaderFontName: String   = "Helvetica"
        static var HeaderTextColor          = UIColor.gray
        
        static var HeaderHeight: CGFloat    = 80.0
    }
    
    var dataSource  : CalendarViewDataSource?
    var delegate    : CalendarViewDelegate?
    
    lazy var calendar : Calendar = {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = TimeZone(abbreviation: "UTC")!
        return gregorian
    }()
    
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
    
    internal(set) var selectedIndexPaths    = [IndexPath]()
    internal(set) var selectedDates         = [Date]()

    
    internal var eventsByIndexPath = [IndexPath:[CalendarEvent]]()

    var events: [CalendarEvent] = [] {
        
        didSet {
            
            self.eventsByIndexPath.removeAll()
            
            for event in events {
                
                guard let indexPath = self.indexPathForDate(event.startDate) else { continue }
                
                var eventsForIndexPath = eventsByIndexPath[indexPath] ?? []
                eventsForIndexPath.append(event)
                eventsByIndexPath[indexPath] = eventsForIndexPath
                
            }
            
            DispatchQueue.main.async { self.collectionView.reloadData() }
        }
    }
    
    
    
    
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        self.setup()
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
    
    override func awakeFromNib() {
        super.awakeFromNib()
        self.setup()
    }
    
    
    // MARK: Create Subviews
    var headerView: CalendarHeaderView!
    var collectionView: UICollectionView!
    private func setup() {
        
        self.clipsToBounds = true
        
        /* Header View */
        self.headerView = CalendarHeaderView(frame:CGRect.zero)
        self.addSubview(self.headerView)
        
        /* Layout */
        let layout = CalendarFlowLayout()
        layout.scrollDirection = self.direction;
        layout.sectionInset = UIEdgeInsets.zero
        layout.minimumInteritemSpacing = 0
        layout.minimumLineSpacing = 0
        layout.itemSize = self.cellSize(in: self.bounds)
        
        /* Collection View */
        self.collectionView                     = UICollectionView(frame: CGRect.zero, collectionViewLayout: layout)
        self.collectionView.dataSource          = self
        self.collectionView.delegate            = self
        self.collectionView.isPagingEnabled     = true
        self.collectionView.backgroundColor     = UIColor.clear
        self.collectionView.showsHorizontalScrollIndicator  = false
        self.collectionView.showsVerticalScrollIndicator    = false
        self.collectionView.allowsMultipleSelection         = false
        self.collectionView.register(CalendarDayCell.self, forCellWithReuseIdentifier: cellReuseIdentifier)
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
            height: CalendarView.Style.HeaderHeight
        )
        
        self.collectionView.frame = CGRect(
            x: 0.0,
            y: CalendarView.Style.HeaderHeight,
            width: self.frame.size.width,
            height: self.frame.size.height - CalendarView.Style.HeaderHeight
        )
        
        flowLayout.itemSize = self.cellSize(in: self.bounds)
        
        self.resetDisplayDate()
        
    }
    
    private func cellSize(in bounds: CGRect) -> CGSize {
        return CGSize(
            width:   frame.size.width / 7.0,                                    // number of days in week
            height: (frame.size.height - CalendarView.Style.HeaderHeight) / 6.0 // maximum number of rows
        )
    }
    
    
    internal var monthInfoForSection = [Int:(firstDay:Int, daysTotal:Int)]()

    func reloadData() {
        self.collectionView.reloadData()
    }
    
    
    func setDisplayDate(_ date : Date, animated: Bool = false) {
        
        guard (date > startDateCache) && (date < endDateCache) else { return }
        
        self.collectionView.setContentOffset(
            self.scrollViewOffset(for: date),
            animated: animated
        )
        
        self.displayDateOnHeader(date)
        
    }
    
    internal func resetDisplayDate() {
        
        guard let displayDate = self.displayDate else { return }
        
        self.collectionView.setContentOffset(
            self.scrollViewOffset(for: displayDate),
            animated: false
        )
    }
    
    func scrollViewOffset(for date: Date) -> CGPoint {
        
        var point = CGPoint.zero
        
        guard let sections = self.indexPathForDate(date)?.section else { return point }
        
        switch self.direction {
        case .horizontal:   point.x = CGFloat(sections) * self.collectionView.frame.size.width
        case .vertical:     point.y = CGFloat(sections) * self.collectionView.frame.size.height
        }
        
        return point
    }

}

// MARK: Selection of Dates
extension CalendarView {
    
    func selectDate(_ date : Date) {
        
        guard let indexPath = self.indexPathForDate(date) else { return }
        
        self.collectionView.selectItem(at: indexPath, animated: false, scrollPosition: UICollectionViewScrollPosition())
        
        self.collectionView(collectionView, didSelectItemAt: indexPath)
        
        
    }
    
    func deselectDate(_ date : Date) {
        
        guard let indexPath = self.indexPathForDate(date) else { return }
        
        self.collectionView.deselectItem(at: indexPath, animated: false)
        
        self.collectionView(collectionView, didSelectItemAt: indexPath)
        
    }
    
}

// MARK: Convertion
extension CalendarView {
    
    func indexPathForDate(_ date : Date) -> IndexPath? {
        
        let distanceFromStartDate = self.calendar.dateComponents([.month, .day], from: self.startOfMonthCache, to: date)
        
        guard
            let day   = distanceFromStartDate.day,
            let month = distanceFromStartDate.month,
            let (firstDayIndex, _) = monthInfoForSection[month] else { return nil }
        
        return IndexPath(
            item: day + firstDayIndex,
            section: month
        )
        
    }
    
    func dateFromIndexPath(_ indexPath: IndexPath) -> Date? {
        
        let month = indexPath.section
        
        guard let monthInfo = monthInfoForSection[month] else { return nil }
        
        var components      = DateComponents()
        components.month    = month
        components.day      = indexPath.item - monthInfo.firstDay
        
        return self.calendar.date(byAdding: components, to: self.startOfMonthCache)
        
    }
    
}

extension CalendarView {

    func goToMonthWithOffet(_ offset: Int) {
        
        guard let displayDate = self.displayDate else { return }
        
        var dateComponents = DateComponents()
        dateComponents.month = offset;
        
        guard let newDate = self.calendar.date(byAdding: dateComponents, to: displayDate) else { return }
        
        self.setDisplayDate(newDate, animated: true)
    }
    
    func goToNextMonth() {
        goToMonthWithOffet(1)
    }
    
    func goToPreviousMonth() {
        goToMonthWithOffet(-1)
    }
    
}


