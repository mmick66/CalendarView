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

import OSLog
import UIKit

/// An event shown as a dot on every day it covers.
public struct CalendarEvent: Sendable {
    public let title: String
    public let startDate: Date
    public let endDate: Date

    public init(title: String, startDate: Date, endDate: Date) {
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
    }
}

/// Provides the range of dates a ``CalendarView`` displays.
///
/// Every month touched by the range is shown in full; days before `startDate()` or after
/// `endDate()` are styled as out of range and cannot be selected.
@MainActor
public protocol CalendarViewDataSource: AnyObject {
    /// The first selectable day. Defaults to today.
    func startDate() -> Date
    /// The last selectable day. Defaults to today.
    func endDate() -> Date
    /// A custom title for the header of the month containing `date`, or `nil` for the default
    /// localized month and year.
    func headerString(_ date: Date) -> String?
}

extension CalendarViewDataSource {
    public func startDate() -> Date { Date() }
    public func endDate() -> Date { Date() }
    public func headerString(_ date: Date) -> String? { nil }
}

/// Receives scrolling and selection events from a ``CalendarView``.
///
/// Dates are the start of the day in ``CalendarView/calendar``; the month passed to
/// `didScrollToMonth` is the first day of that month.
@MainActor
public protocol CalendarViewDelegate: AnyObject {
    /// The calendar settled on a new month, or displayed its first one.
    func calendar(_ calendar: CalendarView, didScrollToMonth date: Date)
    /// A day was selected, by a tap or by ``CalendarView/selectDate(_:)``.
    func calendar(_ calendar: CalendarView, didSelectDate date: Date, withEvents events: [CalendarEvent])
    /// Whether a day in range may be selected. Defaults to `true`.
    func calendar(_ calendar: CalendarView, canSelectDate date: Date) -> Bool
    /// A day was deselected, by a tap or by ``CalendarView/deselectDate(_:)``.
    func calendar(_ calendar: CalendarView, didDeselectDate date: Date)
    /// A day was long-pressed. `events` is `nil` when the day has none.
    func calendar(_ calendar: CalendarView, didLongPressDate date: Date, withEvents events: [CalendarEvent]?)
}

extension CalendarViewDelegate {
    public func calendar(_ calendar: CalendarView, canSelectDate date: Date) -> Bool { true }
    public func calendar(_ calendar: CalendarView, didDeselectDate date: Date) {}
    public func calendar(_ calendar: CalendarView, didLongPressDate date: Date, withEvents events: [CalendarEvent]?) {}
}

/// A month calendar that scrolls horizontally or vertically, one month per page.
public class CalendarView: UIView {

    static let logger = Logger(subsystem: "com.karmadust.KDCalendar", category: "CalendarView")

    public let cellReuseIdentifier = "CalendarDayCell"

    var headerView: CalendarHeaderView!
    var collectionView: UICollectionView!

    public var forceLtr: Bool = true {
        didSet {
            updateLayoutDirections()
        }
    }

    /// The look of the calendar. Assign a new value, or mutate in place, to restyle.
    public var style: Style = .default {
        didSet {
            updateStyle()
        }
    }

    /// The calendar used for every date computation. Shorthand for `style.calendar`.
    public var calendar: Calendar {
        return style.calendar
    }

    /// The days the data source currently spans, from `startDate()` to `endDate()`, at the
    /// start of each day.
    public var dateRange: ClosedRange<Date> {
        let start = startDay
        let end = endDay
        return start <= end ? start...end : start...start
    }

    /// The index paths of the selected days, in selection order.
    public internal(set) var selectedIndexPaths = [IndexPath]()
    /// The selected days, in selection order.
    public internal(set) var selectedDates = [Date]()

    /// The month grid derived from the data source. Rebuilt whenever the range changes.
    var months: MonthGrid?
    var eventsByIndexPath = [IndexPath: [CalendarEvent]]()

    /// Events to show as dots. An event marks every day it covers.
    public var events: [CalendarEvent] = [] {
        didSet {
            rebuildEventIndex()
            self.reloadData()
        }
    }

    var flowLayout: CalendarFlowLayout {
        return self.collectionView.collectionViewLayout as! CalendarFlowLayout
    }

    // MARK: - public

    /// The first day of the month currently displayed, or `nil` before the first layout.
    public internal(set) var displayDate: Date?
    /// The last month the delegate was told about, so it hears about each month once.
    var lastNotifiedMonth: Date?
    /// The month an animated scroll is heading for. An animation that is interrupted by
    /// another one reports its end at the wrong offset; the target tells them apart.
    var animationTargetMonth: Date?

    /// Whether more than one day can be selected at a time.
    public var multipleSelectionEnable = true {
        didSet {
            guard !multipleSelectionEnable, selectedIndexPaths.count > 1 else { return }
            let keep = selectedIndexPaths.last!
            for indexPath in selectedIndexPaths where indexPath != keep {
                collectionView?.deselectItem(at: indexPath, animated: false)
            }
            selectedIndexPaths = [keep]
            selectedDates = [selectedDates.last!]
        }
    }

    /// Whether tapping a selected day deselects it. Programmatic deselection always works.
    public var enableDeselection = true

    /// Whether weekend days use `Style.cellTextColorWeekend`.
    public var marksWeekends = true {
        didSet { reloadData() }
    }

    public weak var delegate: CalendarViewDelegate?
    public weak var dataSource: CalendarViewDataSource?

    /// The scrolling axis. Each month is one page.
    public var direction: UICollectionView.ScrollDirection = .horizontal {
        didSet {
            flowLayout.scrollDirection = direction
            self.reloadData()
            resetDisplayDate()
        }
    }

    public override init(frame: CGRect) {
        super.init(frame: frame)
        self.setup()
    }

    required public init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }

    override open func awakeFromNib() {
        super.awakeFromNib()
        MainActor.assumeIsolated {
            self.setup()
        }
    }

    // MARK: Create Subviews
    private func setup() {

        self.clipsToBounds = true

        /* Header View */
        self.headerView = CalendarHeaderView(frame: CGRect.zero)
        self.headerView.style = style
        self.addSubview(self.headerView)

        /* Layout */
        let layout = CalendarFlowLayout()
        layout.scrollDirection = self.direction
        layout.sectionInset = UIEdgeInsets.zero
        layout.minimumInteritemSpacing = 0
        layout.minimumLineSpacing = 0

        /* Collection View */
        self.collectionView = UICollectionView(frame: CGRect.zero, collectionViewLayout: layout)
        self.collectionView.dataSource = self
        self.collectionView.delegate = self
        self.collectionView.isPagingEnabled = true
        self.collectionView.backgroundColor = UIColor.clear
        self.collectionView.showsHorizontalScrollIndicator = false
        self.collectionView.showsVerticalScrollIndicator = false
        // Single selection is enforced in didSelectItemAt so that taps on a selected day
        // behave the same in both modes: UIKit reports them as deselections.
        self.collectionView.allowsMultipleSelection = true
        self.collectionView.register(CalendarDayCell.self, forCellWithReuseIdentifier: cellReuseIdentifier)

        self.addSubview(self.collectionView)

        // Update semantic content attributes
        updateLayoutDirections()

        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(CalendarView.handleLongPress))
        self.collectionView.addGestureRecognizer(longPress)

    }

    @objc func handleLongPress(gesture: UILongPressGestureRecognizer) {

        guard gesture.state == UIGestureRecognizer.State.began else {
            return
        }

        let point = gesture.location(in: collectionView)

        guard
            let indexPath = collectionView.indexPathForItem(at: point),
            let date = self.dateFromIndexPath(indexPath) else {
            return
        }

        let events = self.eventsByIndexPath[indexPath] ?? []
        self.delegate?.calendar(self, didLongPressDate: date, withEvents: events.isEmpty ? nil : events)
    }

    private var lastLayoutSize = CGSize.zero

    override open func layoutSubviews() {

        super.layoutSubviews()

        self.headerView?.frame = CGRect(
            x: 0.0,
            y: 0.0,
            width: self.bounds.size.width,
            height: style.headerHeight
        )

        self.collectionView?.frame = CGRect(
            x: 0.0,
            y: style.headerHeight,
            width: self.bounds.size.width,
            height: max(0, self.bounds.size.height - style.headerHeight)
        )

        let size = self.cellSize(in: self.bounds)
        if size.width > 0 && size.height > 0 && flowLayout.itemSize != size {
            flowLayout.itemSize = size
        }

        // Keep the displayed month in place when the size changes; do not fight a scroll.
        if lastLayoutSize != self.bounds.size {
            lastLayoutSize = self.bounds.size
            self.resetDisplayDate()
        }

        if displayDate == nil, self.bounds.width > 0, currentMonths != nil {
            // First layout with content: settle on the first month and tell the delegate once.
            self.collectionView.layoutIfNeeded()
            self.updateAndNotifyScrolling()
        }
    }

    private func cellSize(in bounds: CGRect) -> CGSize {
        guard let collectionView = self.collectionView
        else {
            return .zero
        }

        return CGSize(
            width: collectionView.bounds.width / 7.0,  // number of days in week
            height: collectionView.bounds.height / 6.0  // maximum number of rows
        )
    }

    internal var _isRtl = false

    internal func updateLayoutDirections() {
        self.collectionView?.semanticContentAttribute = .forceLeftToRight
        self.headerView?.semanticContentAttribute = forceLtr ? .forceLeftToRight : .unspecified

        var isRtl = false

        if !forceLtr {
            isRtl = self.effectiveUserInterfaceLayoutDirection == .rightToLeft
        }

        if _isRtl != isRtl {
            _isRtl = isRtl

            self.collectionView?.transform = isRtl
                ? CGAffineTransform(scaleX: -1.0, y: 1.0)
                : CGAffineTransform.identity
            self.reloadData()
        }
    }

    internal func resetDisplayDate() {
        guard let displayDate = self.displayDate, let collectionView = self.collectionView else { return }

        collectionView.setContentOffset(
            self.scrollViewOffset(for: displayDate),
            animated: false
        )
    }

    internal func updateStyle() {
        self.headerView?.style = style
        self.invalidateMonths()
        self.reloadData()
        self.setNeedsLayout()
    }

    func scrollViewOffset(for date: Date) -> CGPoint {
        var point = CGPoint.zero

        guard let section = self.indexPathForDate(date)?.section else { return point }

        switch self.direction {
        case .horizontal: point.x = CGFloat(section) * self.collectionView.frame.size.width
        case .vertical: point.y = CGFloat(section) * self.collectionView.frame.size.height
        @unknown default:
            point.x = CGFloat(section) * self.collectionView.frame.size.width
        }

        return point
    }
}

// MARK: - Public methods
extension CalendarView {

    /// Reloads every day cell, keeping the selection.
    public func reloadData() {
        guard let collectionView = self.collectionView else { return }
        collectionView.reloadData()
        for indexPath in selectedIndexPaths {
            collectionView.selectItem(at: indexPath, animated: false, scrollPosition: [])
        }
    }

    /// Scrolls to the month containing `date`. Dates outside the data source's months are ignored.
    ///
    /// The delegate receives `didScrollToMonth` once the month is on screen: immediately when
    /// `animated` is `false`, when the animation ends otherwise.
    public func setDisplayDate(_ date: Date, animated: Bool = false) {
        guard let indexPath = self.indexPathForDate(date), let month = self.months?.firstDay(ofSection: indexPath.section) else {
            return
        }

        self.displayDateOnHeader(month)

        guard let collectionView = self.collectionView else { return }
        collectionView.layoutIfNeeded()
        animationTargetMonth = animated ? month : nil
        collectionView.setContentOffset(self.scrollViewOffset(for: month), animated: animated)
        if !animated {
            self.notifyScrolled(to: month)
        }
    }

    /// Selects the day containing `date`, subject to the same rules as a tap: the day must be
    /// in range and the delegate's `canSelectDate` must allow it. In single-selection mode the
    /// previous selection is cleared first. The delegate receives `didSelectDate`.
    public func selectDate(_ date: Date) {
        guard let indexPath = self.indexPathForDate(date), self.shouldSelect(indexPath) else { return }
        self.collectionView.selectItem(at: indexPath, animated: false, scrollPosition: [])
        self.didSelect(indexPath)
    }

    /// Deselects the day containing `date` if it is selected. The delegate receives
    /// `didDeselectDate`. Does nothing for a day that is not selected.
    public func deselectDate(_ date: Date) {
        guard let indexPath = self.indexPathForDate(date), selectedIndexPaths.contains(indexPath) else { return }
        self.collectionView.deselectItem(at: indexPath, animated: false)
        self.didDeselect(indexPath)
    }

    /// Scrolls one month forward, animated.
    public func goToNextMonth() {
        goToMonth(offsetBy: 1)
    }

    /// Scrolls one month back, animated.
    public func goToPreviousMonth() {
        goToMonth(offsetBy: -1)
    }

    /// Deselects every day without notifying the delegate.
    public func clearAllSelectedDates() {
        for indexPath in selectedIndexPaths {
            self.collectionView?.deselectItem(at: indexPath, animated: false)
        }
        selectedIndexPaths.removeAll()
        selectedDates.removeAll()
    }

    func goToMonth(offsetBy offset: Int) {

        guard let displayDate = self.displayDate else { return }

        guard let newDate = self.calendar.date(byAdding: .month, value: offset, to: displayDate) else { return }
        self.setDisplayDate(newDate, animated: true)
    }
}
