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
            guard style != oldValue else { return }
            reloadData()
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
    /// Read from the grid that ``reloadData()`` last built; reading it never asks the data source.
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
            guard events != oldValue else { return }
            reloadData()
        }
    }

    var flowLayout: CalendarFlowLayout {
        collectionView.collectionViewLayout as! CalendarFlowLayout
    }

    /// The first day of the month currently displayed, or `nil` before the first layout.
    ///
    /// The displayed month is state, as the selection is: ``reloadData()`` keeps the calendar on it
    /// wherever the new grid puts it, and moves to the nearest month of the grid when the data
    /// source's range no longer has it. While the range is invalid and the calendar shows no
    /// months, this stays the month last displayed, which comes back with a valid range.
    public internal(set) var displayDate: Date?
    /// The last month the delegate was told about, so it hears about each month once.
    var lastNotifiedMonth: Date?
    /// The month an animated scroll is heading for.
    ///
    /// An animation that is interrupted by another one reports its end at the wrong offset; the
    /// target tells them apart.
    var animationTargetMonth: Date?
    /// Whether the view is moving the content offset itself, without animation, in
    /// `moveOffset(to:animated:)`.
    var isMovingOffset = false
    /// Whether the user is scrolling: from the start of a drag until the grid comes to rest, or
    /// until the view moves the grid itself.
    ///
    /// While it lasts the month is not settled, whatever ``displayDate`` says: a drag that caught
    /// an animated scroll leaves it on the month the animation was heading for.
    var isUserScrolling = false
    /// Called each time a scroll comes to rest on a month, with that month, also when it is the
    /// month the delegate last heard of and `didScrollToMonth` is therefore not sent.
    ///
    /// A scroll can return to that month after ``displayDate`` has been elsewhere: an animated
    /// scroll that the user catches and drags back. Whoever keeps a copy of ``displayDate``, as
    /// ``KDCalendarView`` does in its ``KDCalendarView/displayedMonth(_:)`` binding, brings the
    /// copy up to date here.
    var scrollDidSettle: (@MainActor (_ month: Date) -> Void)?

    /// Whether tapping a selected day deselects it.
    ///
    /// Programmatic deselection always works.
    public var enableDeselection = true

    /// Whether weekend days use `Style.cellTextColorWeekend`.
    public var marksWeekends = true {
        didSet {
            guard marksWeekends != oldValue else { return }
            reloadData()
        }
    }

    /// Receives scrolling and selection events.
    public weak var delegate: CalendarViewDelegate?
    /// Provides the range of days to show.
    ///
    /// Assigning one reloads the calendar from it.
    public weak var dataSource: CalendarViewDataSource? {
        didSet {
            // Not skipped for the same object: its answers may have changed, and a data source
            // that was deallocated reads as `nil` here although the grid still shows its range.
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
            guard direction != oldValue else { return }
            reloadData()
        }
    }

    /// The current time.
    ///
    /// Tests replace it to move the clock.
    var now: () -> Date = { Date() }

    /// Calls `action` back on the main actor at `date`, until the returned token is cancelled or
    /// released.
    ///
    /// A wall-clock timer by default; tests replace it to make the day change by hand.
    var scheduleWakeUp: @MainActor (_ date: Date, _ action: @escaping @MainActor () -> Void) -> AnyCancellable =
        CalendarView.timerWakeUp

    /// Called when a reload has moved the selected days or the displayed month to another calendar.
    ///
    /// They are the same days and the same month at other instants, such as the midnights of
    /// another time zone, so the delegate is not told: nothing was selected, deselected or
    /// scrolled. Whoever keeps a copy of ``selectedDates`` or ``displayDate``, as
    /// ``KDCalendarView`` does in its bindings, brings the copy up to date here. The view shows
    /// the whole reload by then, and the delegate has not yet heard of the days the reload dropped.
    var calendarDidChange: (@MainActor () -> Void)?

    /// The reload waiting for the next start of day in ``layoutCalendar``, and when that is.
    private var dayChange: (date: Date, wakeUp: AnyCancellable)?

    /// Whether the next layout asks the days on screen again whether they may be selected.
    private var needsSelectabilityRefresh = false

    /// How many ``performBatchUpdate(_:)`` calls are running, one inside the other.
    private var batchDepth = 0
    /// Whether a reload is waiting for the outermost ``performBatchUpdate(_:)`` to return.
    private var needsReload = false

    public override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    /// Creates a calendar from an archive, with a fresh header and grid.
    required public init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        // A view decoded from an archive brings its old header and grid along; replace them.
        for subview in subviews where subview is CalendarHeaderView || subview is UICollectionView {
            subview.removeFromSuperview()
        }
        setup()
    }

    // MARK: - Setup

    /// Configures the header and the grid and adds them.
    ///
    /// Each initialiser calls it once.
    private func setup() {
        clipsToBounds = true

        headerView.setStyle(style, formatters: formatters)
        addSubview(headerView)

        flowLayout.scrollDirection = direction

        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.isPagingEnabled = true
        collectionView.backgroundColor = .clear
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.showsVerticalScrollIndicator = false
        // Single selection is enforced in didSelectItemAt so that taps on a selected day
        // behave the same in both modes: UIKit reports them as deselections.
        collectionView.allowsMultipleSelection = true
        collectionView.register(CalendarDayCell.self, forCellWithReuseIdentifier: cellReuseIdentifier)

        addSubview(collectionView)

        // The grid follows the view's layout direction: now, when its own semantic content
        // attribute changes (see the override below) and when the trait does, as it can when the
        // view moves to another hierarchy.
        updateLayoutDirections()
        registerForTraitChanges([UITraitLayoutDirection.self]) { (view: CalendarView, _: UITraitCollection) in
            view.updateLayoutDirections()
        }

        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(CalendarView.handleLongPress))
        collectionView.addGestureRecognizer(longPress)

        // Keep the today marker honest across midnight and clock or time zone changes. The main
        // queue delivers a notification posted on the main thread at once, before the next layout.
        // Both notifications follow the device's time zone; `scheduleDayChange()` covers a
        // calendar in another one.
        for name in [Notification.Name.NSCalendarDayChanged, UIApplication.significantTimeChangeNotification] {
            let observer = NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) {
                [weak self] _ in
                MainActor.assumeIsolated { self?.reloadData() }
            }
            observers.insert(AnyCancellable { NotificationCenter.default.removeObserver(observer) })
        }
    }

    /// Reports a long press on a day of the displayed months to the delegate.
    ///
    /// Days out of range are reported too, although they cannot be tapped: see
    /// ``CalendarViewDelegate/calendar(_:didLongPressDate:withEvents:)``.
    @objc func handleLongPress(gesture: UILongPressGestureRecognizer) {

        guard gesture.state == .began else {
            return
        }

        let point = gesture.location(in: collectionView)

        guard
            let indexPath = collectionView.indexPathForItem(at: point),
            let date = dateFromIndexPath(indexPath)
        else {
            return
        }

        let events = snapshot.eventIndex[indexPath]
        delegate?.calendar(self, didLongPressDate: date, withEvents: events.isEmpty ? nil : events)
    }

    // MARK: - Layout

    /// The size of a month's page at the last layout.
    private var lastPageSize = CGSize.zero

    override open func layoutSubviews() {

        super.layoutSubviews()

        // The style's height, or more when the header's fonts have outgrown it with Dynamic Type.
        let headerHeight = headerView.fittingHeight

        headerView.frame = CGRect(
            x: 0.0,
            y: 0.0,
            width: bounds.size.width,
            height: headerHeight
        )

        collectionView.frame = CGRect(
            x: 0.0,
            y: headerHeight,
            width: bounds.size.width,
            height: max(0, bounds.size.height - headerHeight)
        )

        // Keep the displayed month in place when its page changes size, with the view or with the
        // header above it (its style's height, or its fonts at another text size); do not fight a
        // scroll.
        if lastPageSize != collectionView.bounds.size {
            lastPageSize = collectionView.bounds.size
            resetDisplayDate()
        }

        if displayDate == nil, bounds.width > 0, let firstMonth = snapshot.grid?.firstDayOfMonth(inSection: 0) {
            // First layout with content: settle on the first month and tell the delegate once.
            setDisplayDate(firstMonth)
        }

        if needsSelectabilityRefresh {
            needsSelectabilityRefresh = false
            refreshSelectability()
        }
    }

    /// Has the next layout ask the days on screen again whether they may be selected: see
    /// ``refreshSelectability()``.
    ///
    /// Waiting for the layout answers any number of selection changes with one round of
    /// questions, asked once the delegate has heard of them all, and keeps a selection made in
    /// code to the questions it has to ask itself.
    func setNeedsSelectabilityRefresh() {
        needsSelectabilityRefresh = true
        setNeedsLayout()
    }

    /// Follows a change of the view's own direction.
    ///
    /// The header and the grid do not inherit it, so it is handed on to them.
    public override var semanticContentAttribute: UISemanticContentAttribute {
        didSet {
            updateLayoutDirections()
        }
    }

    /// Hands the view's layout direction to the header and the grid, left to right when
    /// ``forceLtr`` says so, and keeps the displayed month on screen when the grid flips.
    internal func updateLayoutDirections() {
        let isRightToLeft = !forceLtr && effectiveUserInterfaceLayoutDirection == .rightToLeft
        let attribute: UISemanticContentAttribute = isRightToLeft ? .forceRightToLeft : .forceLeftToRight

        // The header mirrors with the calendar, whether the direction comes from the app or
        // from this view alone.
        if headerView.semanticContentAttribute != attribute {
            headerView.semanticContentAttribute = attribute
            headerView.setNeedsLayout()
        }

        // The layout mirrors its frames when the collection view runs right to left.
        guard collectionView.semanticContentAttribute != attribute else { return }
        collectionView.semanticContentAttribute = attribute
        flowLayout.invalidateLayout()
        resetDisplayDate()
    }

}

// MARK: - Reloading

extension CalendarView {

    /// Reloads every day cell, keeping the selection and the displayed month.
    ///
    /// Asks the data source for its range again. Selected days stay selected wherever the new grid
    /// puts them. Days that are no longer in range are deselected, and the delegate receives
    /// `didDeselectDate` for each. The calendar stays on the month it displays, or moves to the
    /// nearest month of the new range when that month is gone, and then the delegate receives
    /// `didScrollToMonth`.
    public func reloadData() {
        guard batchDepth == 0 else {
            needsReload = true
            return
        }
        needsReload = false
        refreshSnapshot()
    }

    /// Runs `changes` and reloads once for all of them.
    ///
    /// Setting ``style``, ``events``, ``dataSource``, ``marksWeekends`` or ``direction``, or
    /// calling ``reloadData()``, reloads at once outside a batch, so that the caller reads the new
    /// state on the next line. Inside `changes` they only ask for a reload, which runs when the
    /// outermost call returns; a nested call joins the outer one. Until then the grid, the
    /// selection and the displayed month are those of before the batch. ``setDisplayDate(_:animated:)``
    /// needs the new grid, so it reloads first when one is waiting: put it last in the batch.
    ///
    /// - Parameter changes: The changes to the view's properties.
    func performBatchUpdate(_ changes: () -> Void) {
        batchDepth += 1
        changes()
        batchDepth -= 1
        if batchDepth == 0 {
            reloadIfNeeded()
        }
    }

    /// Runs the reload a batch is holding back, for a caller inside the batch that needs the new
    /// grid.
    func reloadIfNeeded() {
        guard needsReload else { return }
        needsReload = false
        refreshSnapshot()
    }

    /// Asks the data source for its range, builds the snapshot again and applies it.
    ///
    /// The snapshot is built from the range, the style and the events, reusing the grid and the
    /// event index when none of them changed: the current day alone without a data source, zero
    /// months when the range is invalid. Called once per reload, not once per cell.
    func refreshSnapshot() {
        let start = dataSource?.startDate() ?? now()
        let end = dataSource?.endDate() ?? start
        let inputs = CalendarSnapshot.Inputs(start: start, end: end, style: style, events: events)
        let next = CalendarSnapshot(inputs, now: now(), reusing: snapshot)
        if next.grid == nil, snapshot.inputs != inputs {
            CalendarView.logger.error(
                """
                The data source's start date (\(start, privacy: .public)) is after its end date \
                (\(end, privacy: .public)); showing no months.
                """)
        }
        apply(next)
    }

    /// Replaces the snapshot with `next` and brings everything the view keeps in line with it.
    ///
    /// This is all a reload reconciles, in this order:
    ///
    /// 1. The formatters and the header, when the style or ``layoutCalendar`` changed.
    /// 2. The scrolling axis and the cells.
    /// 3. The selection: the same days in the new calendar, without those no longer in range.
    /// 4. The displayed month: the same month in the new calendar, or the nearest one the grid
    ///    has. ``displayDate``, ``lastNotifiedMonth`` and ``animationTargetMonth`` follow.
    /// 5. The title, which the formatters, the locale or the data source may have changed.
    /// 6. The content offset, when the month's page moved.
    /// 7. The wake-up at the next start of day.
    /// 8. The delegate, last, so that it finds the view consistent: `didDeselectDate` for each
    ///    day dropped, then `didScrollToMonth` when the month it last heard of is no longer the
    ///    one displayed, unless a scroll is under way, which reports the month it ends on.
    ///    ``calendarDidChange`` comes just before, when the selected days or the displayed month
    ///    are now written in another calendar.
    ///
    /// The layout owns two more: a new page size (``layoutSubviews()``) and a new layout
    /// direction (``updateLayoutDirections()``) put the displayed month back in place themselves,
    /// as neither comes with a reload.
    private func apply(_ next: CalendarSnapshot) {
        let previous = snapshot
        // Where the displayed month sits before the grid, the axis or the calendar moves it.
        let previousPage = displayDate.flatMap { pageOffset(forMonthOf: $0) }
        let previousDates = (selected: selection.days, displayed: displayDate)
        snapshot = next
        let calendarChanged = next.calendar != previous.calendar

        // 1. Formatters and header.
        if calendarChanged || headerView.style != style {
            rebuildFormatters()
            setNeedsLayout()  // the header's height follows the style
        }

        // 2. Axis and cells.
        if flowLayout.scrollDirection != direction {
            flowLayout.scrollDirection = direction
        }
        collectionView.reloadData()

        // 3. Selection. The reload cleared the cells' selection, so every kept day is shown again.
        var movedDates = false
        if calendarChanged {
            moveSelection(from: previous.calendar, to: next.calendar)
            movedDates = selection.days != previousDates.selected
        }
        var dropped: [Date] = []
        updateSelection(notify: false) { selection in
            var change = selection.retain { next.grid?.isInRange($0) ?? false }
            change.selected = selection.days
            dropped = change.deselected
            return change
        }
        // The layout that follows the reload asks about every day as it configures its cell.
        needsSelectabilityRefresh = false

        // 4. Displayed month. Without months it is kept for the day the range is valid again.
        if calendarChanged {
            let moved = { (month: Date) in next.calendar.firstDayOfMonth(matching: month, in: previous.calendar) }
            displayDate = displayDate.map(moved)
            movedDates = movedDates || displayDate != previousDates.displayed
            animationTargetMonth = animationTargetMonth.map(moved)
            // The same month in another time zone is no news to the delegate. A month of another
            // calendar system is another month, which step 8 announces.
            if next.calendar.identifier == previous.calendar.identifier {
                lastNotifiedMonth = lastNotifiedMonth.map(moved)
            }
        }
        if let grid = next.grid, let displayed = displayDate {
            let month = grid.nearestMonth(to: displayed)
            displayDate = month
            if animationTargetMonth != nil {
                animationTargetMonth = month
            }

            // 5. Title.
            updateTitle()

            // 6. Offset. Left alone when the page did not move, so that a reload during a drag or
            // an animation, such as events arriving, does not pull the grid from under it.
            // Set before the collection view lays out again, so that it never lays out at an
            // offset its new content does not reach, which UIKit would clamp as if it had bounced.
            if pageOffset(forMonthOf: month) != previousPage {
                moveOffset(to: scrollViewOffset(for: month), animated: false)
                animationTargetMonth = nil
            }
        } else if next.grid != nil {
            // Months but none displayed yet: the next layout settles on the first one.
            setNeedsLayout()
        }

        // 7. Today.
        scheduleDayChange()

        // 8. Delegate. An animation still on its way reports its month when it ends, and so does
        // a scroll still under the user's finger, which may have caught an animation and may yet
        // come to rest on another month than the one that animation was heading for.
        if movedDates {
            calendarDidChange?()
        }
        for day in dropped {
            delegate?.calendar(self, didDeselectDate: day)
        }
        if snapshot.grid != nil, animationTargetMonth == nil, !isUserScrolling, let displayDate {
            notifyScrolled(to: displayDate)
        }
    }
}

// MARK: - Grid

extension CalendarView {

    var startDay: Date {
        snapshot.grid?.startDay ?? layoutCalendar.startOfDay(for: now())
    }

    var endDay: Date {
        snapshot.grid?.endDay ?? layoutCalendar.startOfDay(for: now())
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

// MARK: - Today

extension CalendarView {

    /// Reloads at the next start of day in ``layoutCalendar``, so that the today marker moves at
    /// midnight there.
    ///
    /// The system's day-change notification follows the device's time zone, which is hours off
    /// for a ``Style/calendar`` in another one. Every reload calls this, so the wake-up follows a
    /// new calendar or clock, and firing reloads, which schedules the day after. The view holds
    /// the only reference to the wake-up, which ends with it.
    private func scheduleDayChange() {
        let nextDay = layoutCalendar.dateInterval(of: .day, for: now())?.end
        guard nextDay != dayChange?.date else { return }
        dayChange?.wakeUp.cancel()
        dayChange = nextDay.map { date in
            (date, scheduleWakeUp(date) { [weak self] in self?.dayDidChange() })
        }
    }

    /// Reloads for the new day.
    private func dayDidChange() {
        // Forgotten first, so that the reload schedules again even if the wake-up came early.
        dayChange = nil
        reloadData()
    }

    /// Calls `action` on the main actor at `date` with a wall-clock timer on the main queue.
    ///
    /// A `Timer` on the run loop would not do: it counts the time the device is awake, so one set
    /// for a midnight ten hours away fires seven hours late after the device slept for seven. A
    /// dispatch timer with a wall-clock deadline is measured against the clock itself, across
    /// sleep and changes of the clock, and fires at once when the moment has already passed.
    ///
    /// - Parameters:
    ///   - date: When to call.
    ///   - action: What to call, once.
    /// - Returns: A token that calls the timer off when cancelled or released.
    static func timerWakeUp(at date: Date, _ action: @escaping @MainActor () -> Void) -> AnyCancellable {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(wallDeadline: .now() + date.timeIntervalSinceNow)
        timer.setEventHandler {
            // The source's queue is the main queue, so the handler runs on the main thread.
            MainActor.assumeIsolated(action)
        }
        timer.resume()
        return AnyCancellable { timer.cancel() }
    }
}
