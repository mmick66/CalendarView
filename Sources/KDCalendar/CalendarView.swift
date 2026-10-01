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

import Combine
import OSLog
import UIKit

/// A month calendar that scrolls horizontally or vertically, one month per page.
public class CalendarView: UIView {

    static let logger = Logger(subsystem: "com.karmadust.KDCalendar", category: "CalendarView")

    /// The reuse identifier of the day cells.
    public let cellReuseIdentifier = "CalendarDayCell"

    let headerView = CalendarHeaderView(frame: .zero)
    let collectionView = UICollectionView(frame: .zero, collectionViewLayout: CalendarFlowLayout())

    /// Whether the grid always runs left to right. When `false` the grid mirrors in
    /// right-to-left layouts.
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

    /// The calendar used for every date computation: ``Style/resolvedCalendar``, that is
    /// `style.calendar`, given `style.locale` when it has no locale of its own.
    public var calendar: Calendar {
        style.resolvedCalendar
    }

    /// The days the data source currently spans, from `startDate()` to `endDate()`, at the
    /// start of each day.
    public var dateRange: ClosedRange<Date> {
        let start = startDay
        let end = endDay
        return start <= end ? start...end : start...start
    }

    /// The selected days and the range being picked. Cells are derived from it on demand.
    var selection = SelectionState()

    /// The month grid derived from the data source. Rebuilt whenever the range changes.
    var months: MonthGrid?
    /// The cell showing today, refreshed with the grid and when the day changes.
    var todayIndexPath: IndexPath?
    /// The notification observers, removed when the view goes away.
    private var observers = Set<AnyCancellable>()
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

    /// Whether tapping a selected day deselects it. Programmatic deselection always works.
    public var enableDeselection = true

    /// Whether weekend days use `Style.cellTextColorWeekend`.
    public var marksWeekends = true {
        didSet { reloadData() }
    }

    /// Receives scrolling and selection events.
    public weak var delegate: CalendarViewDelegate?
    /// Provides the range of days to show. Assigning one reloads the calendar from it.
    public weak var dataSource: CalendarViewDataSource? {
        didSet {
            invalidateMonths()
            reloadData()
        }
    }

    /// The date formatters for the style and the calendar, rebuilt when either changes.
    private(set) var formatters = Formatters(style: .default)

    /// Builds the formatters again for the current style and restyles the header with them.
    func rebuildFormatters() {
        formatters = Formatters(style: style)
        headerView.setStyle(style, formatters: formatters)
    }

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
        // A view decoded from an archive brings its old header and grid along; replace them.
        for subview in subviews where subview is CalendarHeaderView || subview is UICollectionView {
            subview.removeFromSuperview()
        }
        self.setup()
    }

    // MARK: Create Subviews
    /// Configures the header and the grid and adds them. Each initialiser calls it once.
    private func setup() {
        self.clipsToBounds = true

        self.headerView.setStyle(style, formatters: formatters)
        self.addSubview(self.headerView)

        flowLayout.scrollDirection = self.direction

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

        // Keep the today marker honest across midnight and clock or time zone changes. The main
        // queue delivers a notification posted on the main thread at once, before the next layout.
        for name in [Notification.Name.NSCalendarDayChanged, UIApplication.significantTimeChangeNotification] {
            let observer = NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) {
                [weak self] _ in
                MainActor.assumeIsolated { self?.reloadData() }
            }
            observers.insert(AnyCancellable { NotificationCenter.default.removeObserver(observer) })
        }
    }

    @objc func handleLongPress(gesture: UILongPressGestureRecognizer) {

        guard gesture.state == UIGestureRecognizer.State.began else {
            return
        }

        let point = gesture.location(in: collectionView)

        guard
            let indexPath = collectionView.indexPathForItem(at: point),
            let date = self.dateFromIndexPath(indexPath)
        else {
            return
        }

        let events = self.eventsByIndexPath[indexPath] ?? []
        self.delegate?.calendar(self, didLongPressDate: date, withEvents: events.isEmpty ? nil : events)
    }

    private var lastLayoutSize = CGSize.zero

    override open func layoutSubviews() {

        super.layoutSubviews()

        self.headerView.frame = CGRect(
            x: 0.0,
            y: 0.0,
            width: self.bounds.size.width,
            height: style.headerHeight
        )

        self.collectionView.frame = CGRect(
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
        return CGSize(
            width: collectionView.bounds.width / 7.0,  // number of days in week
            height: collectionView.bounds.height / 6.0  // maximum number of rows
        )
    }

    internal func updateLayoutDirections() {
        let isRtl = !forceLtr && self.effectiveUserInterfaceLayoutDirection == .rightToLeft
        let attribute: UISemanticContentAttribute = isRtl ? .forceRightToLeft : .forceLeftToRight

        // The header mirrors with the calendar, whether the direction comes from the app or
        // from this view alone.
        self.headerView.semanticContentAttribute = attribute
        self.headerView.setNeedsLayout()

        // The layout mirrors its frames when the collection view runs right to left.
        guard collectionView.semanticContentAttribute != attribute else { return }
        collectionView.semanticContentAttribute = attribute
        flowLayout.invalidateLayout()
        resetDisplayDate()
    }

    internal func updateStyle() {
        rebuildFormatters()
        let previousCalendar = months?.calendar
        self.invalidateMonths()
        if let previousCalendar {
            moveSelection(from: previousCalendar)
        }
        self.reloadData()
        self.setNeedsLayout()
    }

}

// MARK: - Grid

extension CalendarView {

    /// Reloads every day cell, keeping the selection. Asks the data source for its range again.
    ///
    /// Selected days stay selected wherever the new grid puts them. Days that are no longer in
    /// range are deselected, and the delegate receives `didDeselectDate` for each.
    public func reloadData() {
        refreshMonths()
        let change = selection.retain { date in
            indexPathForDate(date).map { !isOutOfRange($0) } ?? false
        }
        collectionView.reloadData()
        for indexPath in selectedIndexPaths {
            collectionView.selectItem(at: indexPath, animated: false, scrollPosition: [])
        }
        for date in change.deselected {
            delegate?.calendar(self, didDeselectDate: date)
        }
    }

    /// Asks the data source for its range and rebuilds the month grid when the range moved to
    /// other days or the calendar changed, and the formatters when the calendar changed. The
    /// current month alone without a data source; zero months when the range is invalid. Called
    /// once per reload, not once per cell.
    @discardableResult
    func refreshMonths() -> MonthGrid? {
        let start = dataSource?.startDate() ?? Date()
        let end = dataSource?.endDate() ?? start
        // The grid keeps a fixed copy: an autoupdating calendar always equals itself, so
        // comparing it would miss the time zone changes the grid has to follow.
        let calendar = self.calendar.fixed
        if formatters.calendar != calendar {
            rebuildFormatters()
        }
        if let months = months,
            calendar.isDate(months.startDay, inSameDayAs: start),
            calendar.isDate(months.endDay, inSameDayAs: end),
            months.calendar == calendar
        {
            todayIndexPath = months.indexPath(for: Date())
            return months
        }
        let previousCalendar = months?.calendar
        months = MonthGrid(start: start, end: end, calendar: calendar, firstWeekday: style.effectiveFirstWeekday)
        if let previousCalendar {
            moveSelection(from: previousCalendar)
        }
        if months == nil {
            CalendarView.logger.error(
                "The data source's start date (\(start)) is after its end date (\(end)); showing no months.")
        }
        todayIndexPath = months?.indexPath(for: Date())
        rebuildEventIndex()
        return months
    }

    /// The month grid, built on first use. Reloads refresh it from the data source.
    var currentMonths: MonthGrid? {
        months ?? refreshMonths()
    }

    func invalidateMonths() {
        months = nil
    }

    var startDay: Date {
        currentMonths?.startDay ?? calendar.startOfDay(for: Date())
    }

    var endDay: Date {
        currentMonths?.endDay ?? calendar.startOfDay(for: Date())
    }

    /// Buckets every event into the days it covers, clamped to the displayed months so an
    /// open-ended event costs one loop over the grid, not over the centuries.
    func rebuildEventIndex() {
        eventsByIndexPath.removeAll()
        guard let months = months, let first = months.months.first, let lastMonth = months.months.last,
            let gridEnd = calendar.date(byAdding: .day, value: lastMonth.dayCount, to: lastMonth.firstDate)
        else { return }
        let gridStart = first.firstDate
        for event in events {
            let eventEnd = max(event.startDate, event.endDate)
            guard event.startDate < gridEnd, eventEnd >= gridStart else { continue }
            var day = calendar.startOfDay(for: max(event.startDate, gridStart))
            let last = min(eventEnd, gridEnd)
            repeat {
                if let indexPath = months.indexPath(for: day) {
                    eventsByIndexPath[indexPath, default: []].append(event)
                }
                // Where a DST change skips midnight, adding a day lands after it, so return to the start.
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = calendar.startOfDay(for: next)
            } while day < last
        }
    }

    /// The cell showing the day that contains `date`, or `nil` outside the displayed months.
    public func indexPathForDate(_ date: Date) -> IndexPath? {
        currentMonths?.indexPath(for: date)
    }

    /// The day a cell shows, at the start of the day, or `nil` for an empty cell.
    public func dateFromIndexPath(_ indexPath: IndexPath) -> Date? {
        currentMonths?.date(at: indexPath)
    }

    /// The column of the first day and the number of days for the month in `section`.
    public func getCachedSectionInfo(_ section: Int) -> (firstDay: Int, daysTotal: Int)? {
        guard let months = currentMonths, months.months.indices.contains(section) else { return nil }
        let month = months.months[section]
        return (firstDay: month.firstColumn, daysTotal: month.dayCount)
    }

    func isOutOfRange(_ indexPath: IndexPath) -> Bool {
        currentMonths?.isOutOfRange(indexPath) ?? true
    }
}
