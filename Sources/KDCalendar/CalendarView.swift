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
    /// A range of days was selected, by the second tap in ``CalendarView/SelectionMode/range`` mode or
    /// by ``CalendarView/selectRange(_:)``. `selectedDates` holds every selectable day in it.
    func calendar(_ calendar: CalendarView, didSelectRange range: ClosedRange<Date>)
    /// A style for one day, or `nil` for the calendar's own ``CalendarView/style``. Use it to colour
    /// a holiday, grey out days that `canSelectDate` refuses, or change a single day's font.
    func calendar(_ calendar: CalendarView, styleForDate date: Date) -> CalendarView.Style?
}

extension CalendarViewDelegate {
    public func calendar(_ calendar: CalendarView, canSelectDate date: Date) -> Bool { true }
    public func calendar(_ calendar: CalendarView, didDeselectDate date: Date) {}
    public func calendar(_ calendar: CalendarView, didLongPressDate date: Date, withEvents events: [CalendarEvent]?) {}
    public func calendar(_ calendar: CalendarView, didSelectRange range: ClosedRange<Date>) {}
    public func calendar(_ calendar: CalendarView, styleForDate date: Date) -> CalendarView.Style? { nil }
}

/// A month calendar that scrolls horizontally or vertically, one month per page.
public class CalendarView: UIView {

    static let logger = Logger(subsystem: "com.karmadust.KDCalendar", category: "CalendarView")

    /// The reuse identifier of the day cells.
    public let cellReuseIdentifier = "CalendarDayCell"

    var headerView: CalendarHeaderView!
    var collectionView: UICollectionView!

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

    /// The selected days, in selection order.
    ///
    /// The selection is kept as days, not cells: when the range or the style rebuilds the grid,
    /// the days stay selected wherever their cells land.
    public var selectedDates: [Date] {
        selection.days
    }
    /// The cells of the selected days in the current grid, in selection order.
    public var selectedIndexPaths: [IndexPath] {
        selectedDates.compactMap { indexPathForDate($0) }
    }

    /// The month grid derived from the data source. Rebuilt whenever the range changes.
    var months: MonthGrid?
    /// The cell showing today, refreshed with the grid and when the day changes.
    var todayIndexPath: IndexPath?
    nonisolated(unsafe) private var observers: [NSObjectProtocol] = []
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

    /// How taps and ``selectDate(_:)`` combine into a selection.
    public enum SelectionMode: Sendable {
        /// One day at a time; selecting another replaces it.
        case single
        /// Any number of days, each toggled on its own.
        case multiple
        /// Two taps pick the ends of a range and every selectable day between them is selected.
        /// A third tap starts a new range; tapping a selected day clears the range.
        case range
    }

    /// How taps and ``selectDate(_:)`` combine into a selection. `.multiple` by default.
    ///
    /// Switching to `.single` keeps only the most recently selected day, and switching to
    /// `.range` clears the selection. The delegate receives `didDeselectDate` for each day dropped.
    public var selectionMode: SelectionMode {
        get { selection.mode }
        set {
            let change = selection.setMode(newValue)
            show(change)
            for date in change.deselected {
                delegate?.calendar(self, didDeselectDate: date)
            }
        }
    }

    /// Whether more than one day can be selected at a time. `false` is ``SelectionMode/single``,
    /// `true` is ``SelectionMode/multiple``.
    public var multipleSelectionEnable: Bool {
        get { selectionMode != .single }
        set { selectionMode = newValue ? .multiple : .single }
    }

    /// Whether tapping a selected day deselects it. Programmatic deselection always works.
    public var enableDeselection = true

    /// Whether weekend days use `Style.cellTextColorWeekend`.
    public var marksWeekends = true {
        didSet { reloadData() }
    }

    /// Receives scrolling and selection events.
    public weak var delegate: CalendarViewDelegate?
    /// Provides the range of days to show.
    public weak var dataSource: CalendarViewDataSource?

    /// Whether the user can scroll between months. Programmatic scrolling always works.
    public var isScrollEnabled: Bool {
        get { collectionView?.isScrollEnabled ?? true }
        set { collectionView?.isScrollEnabled = newValue }
    }

    /// The date formatters for the style and the calendar, rebuilt when either changes.
    private(set) var formatters = Formatters(style: .default)

    /// Builds the formatters again for the current style and restyles the header with them.
    func rebuildFormatters() {
        formatters = Formatters(style: style)
        headerView?.setStyle(style, formatters: formatters)
    }

    func accessibilityLabel(for date: Date, isToday: Bool, eventsCount: Int) -> String {
        var parts = [formatters.accessibility.string(from: date)]
        if isToday {
            parts.append(
                String(localized: "Today", bundle: .kdCalendar, comment: "VoiceOver suffix for the current day"))
        }
        if eventsCount > 0 {
            parts.append(
                String(
                    localized: "\(eventsCount) events", bundle: .kdCalendar,
                    comment: "VoiceOver suffix with the number of events on a day"))
        }
        return parts.joined(separator: ", ")
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

    override open func awakeFromNib() {
        super.awakeFromNib()
        MainActor.assumeIsolated {
            self.setup()
        }
    }

    // MARK: Create Subviews
    /// Builds the header and the grid once; safe to call again.
    private func setup() {
        guard collectionView == nil else { return }

        self.clipsToBounds = true

        /* Header View */
        self.headerView = CalendarHeaderView(frame: CGRect.zero)
        self.headerView.setStyle(style, formatters: formatters)
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

        // Keep the today marker honest across midnight and clock or time zone changes.
        for name in [Notification.Name.NSCalendarDayChanged, UIApplication.significantTimeChangeNotification] {
            observers.append(
                NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.reloadData() }
                })
        }
    }

    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
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

        var isRtl = false

        if !forceLtr {
            isRtl = self.effectiveUserInterfaceLayoutDirection == .rightToLeft
        }

        // The header mirrors with the calendar, whether the direction comes from the app or
        // from this view alone.
        self.headerView?.semanticContentAttribute = isRtl ? .forceRightToLeft : .forceLeftToRight
        self.headerView?.setNeedsLayout()

        if _isRtl != isRtl {
            _isRtl = isRtl

            self.collectionView?.transform =
                isRtl
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
        rebuildFormatters()
        let previousCalendar = months?.calendar
        self.invalidateMonths()
        if let previousCalendar {
            moveSelection(from: previousCalendar)
        }
        self.reloadData()
        self.setNeedsLayout()
    }

    /// Keeps the same days selected when the calendar moves to another time zone. A selected day
    /// is the start of that day in the old time zone, which can fall on the day before in the new one.
    func moveSelection(from previous: Calendar) {
        let current = calendar
        guard previous.timeZone != current.timeZone else { return }
        // Days run from midnight to midnight in every calendar, so Gregorian ones can carry the
        // day from one time zone to the other whatever the identifiers.
        var from = Calendar(identifier: .gregorian)
        from.timeZone = previous.timeZone
        var to = Calendar(identifier: .gregorian)
        to.timeZone = current.timeZone
        selection.move { date in
            let day = from.dateComponents([.era, .year, .month, .day], from: date)
            guard let moved = to.date(from: day) else { return date }
            return current.startOfDay(for: moved)
        }
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

    /// Reloads every day cell, keeping the selection. Asks the data source for its range again.
    ///
    /// Selected days stay selected wherever the new grid puts them. Days that are no longer in
    /// range are deselected, and the delegate receives `didDeselectDate` for each.
    public func reloadData() {
        guard let collectionView = self.collectionView else { return }
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

    /// Scrolls to the month containing `date`. Dates outside the data source's months are ignored.
    ///
    /// The delegate receives `didScrollToMonth` once the month is on screen: immediately when
    /// `animated` is `false`, when the animation ends otherwise.
    public func setDisplayDate(_ date: Date, animated: Bool = false) {
        guard let indexPath = self.indexPathForDate(date),
            let month = self.months?.firstDay(ofSection: indexPath.section)
        else {
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
        self.didSelect(indexPath)
    }

    /// Deselects the day containing `date` if it is selected. The delegate receives
    /// `didDeselectDate`. Does nothing for a day that is not selected.
    public func deselectDate(_ date: Date) {
        guard let indexPath = self.indexPathForDate(date) else { return }
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

    /// Selects every selectable day in `range`, replacing the current selection, and tells the
    /// delegate with `didSelectRange`. Works in every ``SelectionMode``; in `.range` mode the next
    /// tap starts a new range.
    public func selectRange(_ range: ClosedRange<Date>) {
        show(selection.replace(with: selectableDays(in: range)))
        guard let first = selectedDates.first, let last = selectedDates.last else { return }
        delegate?.calendar(self, didSelectRange: first...last)
    }

    /// Deselects every day without notifying the delegate.
    public func clearAllSelectedDates() {
        show(selection.replace(with: []))
    }

    /// Replaces the selection with `dates` as the selection mode holds them, without replaying
    /// taps and without notifying the delegate. See ``SelectionState/assign(_:selectable:)``.
    func setSelection(_ dates: [Date]) {
        // The delegate may read the selection while it is asked which days are selectable, so
        // the change is worked out on a copy.
        var next = selection
        let change = next.assign(dates.map { calendar.startOfDay(for: $0) }, selectable: selectableDays(in:))
        selection = next
        show(change)
    }

    /// The days from the first day of `range` to its last that can be selected, in order: those
    /// in the data source's range that the delegate allows.
    func selectableDays(in range: ClosedRange<Date>) -> [Date] {
        // Only days in range can be selected, so far-off ends cost nothing.
        let bounds = dateRange
        let last = min(calendar.startOfDay(for: range.upperBound), bounds.upperBound)
        var day = max(calendar.startOfDay(for: range.lowerBound), bounds.lowerBound)
        var days = [Date]()
        while day <= last {
            if let indexPath = indexPathForDate(day), let date = dateFromIndexPath(indexPath), shouldSelect(indexPath) {
                days.append(date)
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = calendar.startOfDay(for: next)
        }
        return days
    }

    /// Selects and deselects the cells of the days `change` added and removed.
    func show(_ change: SelectionState.Change) {
        guard let collectionView else { return }
        for indexPath in change.deselected.compactMap({ indexPathForDate($0) }) {
            collectionView.deselectItem(at: indexPath, animated: false)
        }
        for indexPath in change.selected.compactMap({ indexPathForDate($0) }) {
            collectionView.selectItem(at: indexPath, animated: false, scrollPosition: [])
        }
    }

    func goToMonth(offsetBy offset: Int) {

        guard let displayDate = self.displayDate else { return }

        guard let newDate = self.calendar.date(byAdding: .month, value: offset, to: displayDate) else { return }
        self.setDisplayDate(newDate, animated: true)
    }
}
