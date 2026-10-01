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

    /// Whether the grid always runs left to right.
    ///
    /// When `false` the grid mirrors in right-to-left layouts.
    public var forceLtr: Bool = true {
        didSet {
            updateLayoutDirections()
        }
    }

    /// The look of the calendar.
    ///
    /// Assign a new value, or mutate in place, to restyle.
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

    /// The calendar the grid is laid out in: ``calendar`` as it was at the last reload, fixed.
    ///
    /// The view computes every date in it, so the dates always match the cells, even when the
    /// device moves to another time zone before the next reload.
    var layoutCalendar: Calendar {
        snapshot.calendar
    }

    /// The days the data source currently spans, from `startDate()` to `endDate()`, at the
    /// start of each day.
    ///
    /// The first read after the data source or the calendar changes asks the data source for its
    /// range and builds the month grid; later reads use that grid.
    public var dateRange: ClosedRange<Date> {
        let start = startDay
        let end = endDay
        return start <= end ? start...end : start...start
    }

    /// The selected days and the range being picked.
    ///
    /// Cells are derived from it on demand.
    var selection = SelectionState()

    /// The grid, today and the events on each cell.
    ///
    /// Derived from the data source, the style and ``events``. ``reloadData()`` brings it up to
    /// date; until the first reload it shows the current month alone, as a view without a data
    /// source does.
    private(set) var snapshot = CalendarSnapshot(
        CalendarSnapshot.Inputs(start: Date(), end: Date(), style: .default, events: []), now: Date())
    /// The notification observers, removed when the view goes away.
    private var observers = Set<AnyCancellable>()

    /// Events to show as dots.
    ///
    /// An event marks every day it covers.
    public var events: [CalendarEvent] = [] {
        didSet {
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
    /// The month an animated scroll is heading for.
    ///
    /// An animation that is interrupted by another one reports its end at the wrong offset; the
    /// target tells them apart.
    var animationTargetMonth: Date?

    /// Whether tapping a selected day deselects it.
    ///
    /// Programmatic deselection always works.
    public var enableDeselection = true

    /// Whether weekend days use `Style.cellTextColorWeekend`.
    public var marksWeekends = true {
        didSet { reloadData() }
    }

    /// Receives scrolling and selection events.
    public weak var delegate: CalendarViewDelegate?
    /// Provides the range of days to show.
    ///
    /// Assigning one reloads the calendar from it.
    public weak var dataSource: CalendarViewDataSource? {
        didSet {
            reloadData()
        }
    }

    /// The date formatters for the style's locale and ``layoutCalendar``, rebuilt when either
    /// changes.
    private(set) var formatters = Formatters(
        calendar: Style.default.resolvedCalendar.fixed, locale: Style.default.locale)

    /// Builds the formatters again for the current style and ``layoutCalendar`` and restyles the
    /// header with them.
    func rebuildFormatters() {
        formatters = Formatters(calendar: layoutCalendar, locale: style.locale)
        headerView.setStyle(style, formatters: formatters)
    }

    /// The scrolling axis.
    ///
    /// Each month is one page.
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

    /// Creates a calendar from an archive, with a fresh header and grid.
    required public init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        // A view decoded from an archive brings its old header and grid along; replace them.
        for subview in subviews where subview is CalendarHeaderView || subview is UICollectionView {
            subview.removeFromSuperview()
        }
        self.setup()
    }

    // MARK: Create Subviews
    /// Configures the header and the grid and adds them.
    ///
    /// Each initialiser calls it once.
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

        let events = snapshot.eventIndex[indexPath]
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

        // Keep the displayed month in place when the size changes; do not fight a scroll.
        if lastLayoutSize != self.bounds.size {
            lastLayoutSize = self.bounds.size
            self.resetDisplayDate()
        }

        if displayDate == nil, self.bounds.width > 0, snapshot.grid != nil {
            // First layout with content: settle on the first month and tell the delegate once.
            self.collectionView.layoutIfNeeded()
            self.updateAndNotifyScrolling()
        }
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
        self.reloadData()
        // The reload rebuilt the formatters if the calendar changed; the locale and the look need
        // them too.
        rebuildFormatters()
        self.setNeedsLayout()
    }

}

// MARK: - Grid

extension CalendarView {

    /// Reloads every day cell, keeping the selection.
    ///
    /// Asks the data source for its range again. Selected days stay selected wherever the new grid
    /// puts them. Days that are no longer in range are deselected, and the delegate receives
    /// `didDeselectDate` for each.
    public func reloadData() {
        refreshSnapshot()
        collectionView.reloadData()
        updateSelection(notify: true) { selection in
            var change = selection.retain { date in
                indexPathForDate(date).map { !isOutOfRange($0) } ?? false
            }
            // The reload cleared the cells' selection, so every kept day is shown again.
            change.selected = selection.days
            return change
        }
    }

    /// Asks the data source for its range and builds the snapshot again.
    ///
    /// The snapshot is built from the range, the style and the events, reusing the grid and the
    /// event index when none of them changed: the current day alone without a data source, zero
    /// months when the range is invalid. Called once per reload, not once per cell.
    ///
    /// This is the one place that notices a new ``layoutCalendar``, from the style or from the
    /// device's time zone: it rebuilds the formatters and moves the selection to the new days.
    func refreshSnapshot() {
        let start = dataSource?.startDate() ?? Date()
        let end = dataSource?.endDate() ?? start
        let inputs = CalendarSnapshot.Inputs(start: start, end: end, style: style, events: events)
        let previous = snapshot
        snapshot = CalendarSnapshot(inputs, now: Date(), reusing: previous)
        if snapshot.calendar != previous.calendar {
            rebuildFormatters()
            moveSelection(from: previous.calendar, to: snapshot.calendar)
        }
        if snapshot.grid == nil, previous.inputs != inputs {
            CalendarView.logger.error(
                "The data source's start date (\(start)) is after its end date (\(end)); showing no months.")
        }
    }

    var startDay: Date {
        snapshot.grid?.startDay ?? layoutCalendar.startOfDay(for: Date())
    }

    var endDay: Date {
        snapshot.grid?.endDay ?? layoutCalendar.startOfDay(for: Date())
    }

    /// The cell showing the day that contains `date`, or `nil` outside the displayed months.
    public func indexPathForDate(_ date: Date) -> IndexPath? {
        snapshot.grid?.indexPath(for: date)
    }

    /// The day a cell shows, at the start of the day, or `nil` for an empty cell.
    public func dateFromIndexPath(_ indexPath: IndexPath) -> Date? {
        snapshot.grid?.date(at: indexPath)
    }

    /// The column of the first day and the number of days for the month in `section`.
    public func getCachedSectionInfo(_ section: Int) -> (firstDay: Int, daysTotal: Int)? {
        guard let grid = snapshot.grid, grid.months.indices.contains(section) else { return nil }
        let month = grid.months[section]
        return (firstDay: month.firstColumn, daysTotal: month.dayCount)
    }

    func isOutOfRange(_ indexPath: IndexPath) -> Bool {
        snapshot.grid?.isOutOfRange(indexPath) ?? true
    }
}
