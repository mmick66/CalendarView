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
#if KDCALENDAR_EVENT_MANAGER_ENABLED
import EventKit
#endif

struct EventLocation {
    let title: String
    let latitude: Double
    let longitude: Double
}

public struct CalendarEvent {
    public let title: String
    public let startDate: Date
    public let endDate:Date
    
    public init(title: String, startDate: Date, endDate: Date) {
        self.title = title;
        self.startDate = startDate;
        self.endDate = endDate;
    }
}

public protocol CalendarViewDataSource {
    func startDate() -> Date
    func endDate() -> Date
    /* optional */
    func headerString(_ date: Date) -> String?
}

extension CalendarViewDataSource {
    
    func startDate() -> Date {
        return Date()
    }
    func endDate() -> Date {
        return Date()
    }
    
    func headerString(_ date: Date) -> String? {
        return nil
    }
}

public protocol CalendarViewDelegate {
    
    func calendar(_ calendar : CalendarView, didScrollToMonth date : Date) -> Void
    func calendar(_ calendar : CalendarView, didSelectDate date : Date, withEvents events: [CalendarEvent]) -> Void
    /* optional */
    func calendar(_ calendar : CalendarView, canSelectDate date : Date) -> Bool
    func calendar(_ calendar : CalendarView, didDeselectDate date : Date) -> Void
    func calendar(_ calendar : CalendarView, didLongPressDate date : Date, withEvents events: [CalendarEvent]?) -> Void
}

extension CalendarViewDelegate {
    func calendar(_ calendar : CalendarView, canSelectDate date : Date) -> Bool { return true }
    func calendar(_ calendar : CalendarView, didDeselectDate date : Date) -> Void { return }
    func calendar(_ calendar : CalendarView, didLongPressDate date : Date, withEvents events: [CalendarEvent]?) -> Void { return }
}

public class CalendarView: UIView {
    
    public let cellReuseIdentifier = "CalendarDayCell"
    
    var headerView: CalendarHeaderView!
    var collectionView: UICollectionView!
    
    public var forceLtr: Bool = true {
        didSet {
            updateLayoutDirections()
        }
    }
    
    public var style: Style = Style.Default {
        didSet {
            updateStyle()
        }
    }
    
    public var calendar : Calendar {
        return style.calendar
    }
    
    public internal(set) var selectedIndexPaths = [IndexPath]()
    public internal(set) var selectedDates = [Date]()

    internal var _startDateCache: Date?
    internal var _endDateCache: Date?
    internal var _firstDayCache: Date?
    internal var _lastDayCache: Date?
    
    internal var todayIndexPath : IndexPath?
    internal var startIndexPath : IndexPath!
    internal var endIndexPath   : IndexPath!

    internal var _cachedMonthInfoForSection = [Int:(firstDay: Int, daysTotal: Int)]()
    internal var eventsByIndexPath = [IndexPath: [CalendarEvent]]()
    
    public var events: [CalendarEvent] = [] {
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
    
    var flowLayout: CalendarFlowLayout {
        return self.collectionView.collectionViewLayout as! CalendarFlowLayout
    }
    
    // MARK: - public
    
    public internal(set) var displayDate: Date?
    public var multipleSelectionEnable = true
    public var enableDeslection = true
    public var marksWeekends = true
    
    public var delegate: CalendarViewDelegate?
    public var dataSource: CalendarViewDataSource?
    
    #if swift(>=4.2)
    public var direction : UICollectionView.ScrollDirection = .horizontal {
        didSet {
            flowLayout.scrollDirection = direction
            self.collectionView.reloadData()
        }
    }
    #else
    public var direction : UICollectionView.ScrollDirection = .horizontal {
        didSet {
            flowLayout.scrollDirection = direction
            self.collectionView.reloadData()
        }
    }
    #endif
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        self.setup()
    }
    
    required public init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
    
    override open func awakeFromNib() {
        super.awakeFromNib()
        self.setup()
    }
    
    // MARK: Create Subviews
    private func setup() {
        
        self.clipsToBounds = true
        self.translatesAutoresizingMaskIntoConstraints = false
        
        /* Header View */
        self.headerView = CalendarHeaderView(frame:CGRect.zero)
        self.headerView.style = style
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
        
        // Update semantic content attributes
        updateLayoutDirections()
        
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(CalendarView.handleLongPress))
        self.collectionView.addGestureRecognizer(longPress)
        
    }
    
    @objc func handleLongPress(gesture: UILongPressGestureRecognizer) {
        
        #if swift(>=4.2)
        guard gesture.state == UIGestureRecognizer.State.began else {
            return
        }
        #else
        guard gesture.state == UIGestureRecognizer.State.began else {
            return
        }
        #endif
        
        let point = gesture.location(in: collectionView)
        
        guard
            let indexPath = collectionView.indexPathForItem(at: point),
            let date = self.dateFromIndexPath(indexPath) else {
            return
        }
        
        guard
            let indexPathEvents = collectionView.indexPathForItem(at: point),
            let events = self.eventsByIndexPath[indexPathEvents], events.count > 0 else {
                self.delegate?.calendar(self, didLongPressDate: date, withEvents: nil)
                return
        }
        
        self.delegate?.calendar(self, didLongPressDate: date, withEvents: events)
    }
    
    override open func layoutSubviews() {
        
        super.layoutSubviews()
        
        self.headerView?.frame = CGRect(
            x: 0.0,
            y: 0.0,
            width: self.frame.size.width,
            height: style.headerHeight
        )
        
        self.collectionView?.frame = CGRect(
            x: 0.0,
            y: style.headerHeight,
            width: self.frame.size.width,
            height: self.frame.size.height - style.headerHeight
        )
        
        flowLayout.itemSize = self.cellSize(in: self.bounds)
        
        self.resetDisplayDate()
    }
    
    private func cellSize(in bounds: CGRect) -> CGSize {
        guard let collectionView = self.collectionView
            else {
                return CGSize(
                    width: self.bounds.width / 7.0,
                    height: self.bounds.width / 7.0
                )
            }
        
        return CGSize(
            width:   collectionView.bounds.width / 7.0,                                    // number of days in week
            height: (collectionView.bounds.height) / 6.0 // maximum number of rows
        )
    }
    
    internal var _isRtl = false
    
    internal func updateLayoutDirections() {
        if #available(iOS 9.0, *) {
            self.collectionView?.semanticContentAttribute = .forceLeftToRight
            self.headerView?.semanticContentAttribute = forceLtr ? .forceLeftToRight : .unspecified
        }
        
        var isRtl = false
        
        if !forceLtr
        {
            isRtl = UIApplication.shared.userInterfaceLayoutDirection == .rightToLeft
            
            if #available(iOS 10.0, *) {
                isRtl = self.effectiveUserInterfaceLayoutDirection == .rightToLeft
            }
            else if #available(iOS 9.0, *) {
                isRtl = UIView.userInterfaceLayoutDirection(for: self.semanticContentAttribute) == .rightToLeft
            }
        }
        
        if _isRtl != isRtl
        {
            _isRtl = isRtl
            
            self.collectionView?.transform = isRtl
                ? CGAffineTransform(scaleX: -1.0, y: 1.0)
                : CGAffineTransform.identity
            self.collectionView?.reloadData()
        }
    }
    
    internal func resetDisplayDate() {
        guard let displayDate = self.displayDate else { return }
        
        self.collectionView.setContentOffset(
            self.scrollViewOffset(for: displayDate),
            animated: false
        )
    }
    
    internal func updateStyle() {
        self.headerView?.style = style
    }
    
    func scrollViewOffset(for date: Date) -> CGPoint {
        var point = CGPoint.zero
        
        guard let sections = self.indexPathForDate(date)?.section else { return point }
        
        switch self.direction {
        case .horizontal:   point.x = CGFloat(sections) * self.collectionView.frame.size.width
        case .vertical:     point.y = CGFloat(sections) * self.collectionView.frame.size.height
        @unknown default:
            fatalError()
        }
        
        return point
    }
}

// MARK: Convertion

extension CalendarView {

    func indexPathForDate(_ date : Date) -> IndexPath? {
        
        let distanceFromStartDate = self.calendar.dateComponents([.month, .day], from: self.firstDayCache, to: date)
        
        guard
            let day   = distanceFromStartDate.day,
            let month = distanceFromStartDate.month,
            let (firstDayIndex, _) = getCachedSectionInfo(month) else { return nil }
        
        return IndexPath(item: day + firstDayIndex, section: month)
    }
    
    func dateFromIndexPath(_ indexPath: IndexPath) -> Date? {
        
        let month = indexPath.section
        
        guard let monthInfo = getCachedSectionInfo(month) else { return nil }
        
        var components      = DateComponents()
        components.month    = month
        components.day      = indexPath.item - monthInfo.firstDay
        
        return self.calendar.date(byAdding: components, to: self.firstDayCache)
    }
}

extension CalendarView {

    func goToMonthWithOffet(_ offset: Int) {
        
        guard let displayDate = self.displayDate else { return }
        
        var dateComponents = DateComponents()
        dateComponents.month = offset
    
        guard let newDate = self.calendar.date(byAdding: dateComponents, to: displayDate) else { return }
        self.setDisplayDate(newDate, animated: true)
    }
}

// MARK: - Public methods
extension CalendarView {
    
    /*
     method: - reloadData
     function: - reload all components in collection view
     */
    public func reloadData() {
        self.collectionView.reloadData()
    }
    
    /*
     method: - setDisplayDate
     params:
     - date: Date to extract month and year to scroll at correct section;
     - animated: to handle animation if want;
     function: - scroll calendar at date (month/year) passed as parameter.
     */
    public func setDisplayDate(_ date : Date, animated: Bool = false) {
		if #available(iOS 10.0, *) {
			guard
				let startDate = calendar.dateInterval(of: .month, for: startDateCache)?.start,
				let endDate = calendar.dateInterval(of: .month, for: endDateCache)?.end,
				(startDate..<endDate).contains(date)
			else {
				return
			}
		}
		else {
			guard (startDateCache..<endDateCache).contains(date) else { return }
		}
		
        self.collectionView?.reloadData()
        self.collectionView?.setContentOffset(self.scrollViewOffset(for: date), animated: animated)
        self.displayDateOnHeader(date)
    }
    
    /*
     method: - selectDate
     params:
     - date: Date to select;
     function: - mark date as selected and add it to the array of selected dates
     */
    public func selectDate(_ date : Date) {
        guard let indexPath = self.indexPathForDate(date) else { return }
        
        #if swift(>=4.2)
        self.collectionView.selectItem(at: indexPath, animated: false, scrollPosition: UICollectionView.ScrollPosition())
        #else
            self.collectionView.selectItem(at: indexPath, animated: false, scrollPosition: UICollectionView.ScrollPosition())
        #endif
        self.collectionView(collectionView, didSelectItemAt: indexPath)
    }
    
    /*
     method: - deselectDate
     params:
     - date: Date to deselect;
     function: - unmark date as selected and remove it from the array of selected dates
     */
    public func deselectDate(_ date : Date) {
        guard let indexPath = self.indexPathForDate(date) else { return }
        self.collectionView.deselectItem(at: indexPath, animated: false)
        self.collectionView(collectionView, didSelectItemAt: indexPath)
    }
    
    /*
     method: - goToNextMonth
     function: - scroll the calendar by one month in the future
     */
    public func goToNextMonth() {
        goToMonthWithOffet(1)
    }
    
    /*
     method: - goToPreviousMonth
     function: - scroll the calendar by one month in the past
     */
    public func goToPreviousMonth() {
        goToMonthWithOffet(-1)
    }

    #if KDCALENDAR_EVENT_MANAGER_ENABLED
    
    public func loadEvents(onComplete: ((Error?) -> Void)? = nil) {
        
        EventsManager.load(from: self.startDateCache, to: self.endDateCache) { // (events:[CalendarEvent]?) in
            
            if let events = $0 {
                self.events = events
                onComplete?(nil)
            } else {
                onComplete?(EventsManagerError.Authorization)
            }
            
        }
    }
    
    @discardableResult public func addEvent(_ title: String, date startDate: Date, duration hours: NSInteger = 1) -> Bool {
        
        var components = DateComponents()
        components.hour = hours
        
        guard let endDate = self.calendar.date(byAdding: components, to: startDate) else {
            return false
        }
        
        let event = CalendarEvent(title: title, startDate: startDate, endDate: endDate)
        
        guard EventsManager.add(event: event) else {
            return false
        }
        
        self.events.append(event)
        
        self.collectionView.reloadData()
        
        return true
        
    }

    #endif
}
