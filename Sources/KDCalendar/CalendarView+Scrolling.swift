import UIKit

extension CalendarView {

    /// Whether the user can scroll between months.
    ///
    /// Programmatic scrolling always works.
    public var isScrollEnabled: Bool {
        get { collectionView.isScrollEnabled }
        set { collectionView.isScrollEnabled = newValue }
    }

    /// Scrolls to the month containing `date`.
    ///
    /// Dates outside the data source's months are ignored. The delegate receives `didScrollToMonth`
    /// once the month is on screen: when the animation ends, or immediately when `animated` is
    /// `false`, the view has no size yet or the month is already on screen.
    public func setDisplayDate(_ date: Date, animated: Bool = false) {
        // Inside a batch the grid may be waiting for its reload, and the month has to be in it.
        reloadIfNeeded()
        guard let indexPath = indexPathForDate(date),
            let month = snapshot.grid?.firstDayOfMonth(inSection: indexPath.section)
        else {
            return
        }

        displayDateOnHeader(month)

        collectionView.layoutIfNeeded()
        let offset = scrollViewOffset(for: month)
        // UIKit sends no end-of-animation callback when the offset does not change, which is
        // always the case before the first layout, so those scrolls report at once.
        let animated =
            animated && collectionView.bounds.width > 0 && collectionView.bounds.height > 0
            && collectionView.contentOffset != offset
        animationTargetMonth = animated ? month : nil
        moveOffset(to: offset, animated: animated)
        if !animated {
            notifyScrolled(to: month)
        }
    }

    /// Scrolls one month forward, animated.
    public func goToNextMonth() {
        goToMonth(offsetBy: 1)
    }

    /// Scrolls one month back, animated.
    public func goToPreviousMonth() {
        goToMonth(offsetBy: -1)
    }

    func goToMonth(offsetBy offset: Int) {
        // Inside a batch the displayed month may be waiting for its reload.
        reloadIfNeeded()
        guard let displayDate else { return }

        guard let newDate = layoutCalendar.date(byAdding: .month, value: offset, to: displayDate) else { return }
        setDisplayDate(newDate, animated: true)
    }

    /// Puts the page of the displayed month back on screen, without animation.
    ///
    /// For changes that move the page but not the month: a new page size or layout direction. An
    /// animated scroll on its way to the month ends here, so the delegate hears of the month now.
    internal func resetDisplayDate() {
        guard let displayDate else { return }

        moveOffset(to: scrollViewOffset(for: displayDate), animated: false)
        if animationTargetMonth != nil {
            animationTargetMonth = nil
            notifyScrolled(to: displayDate)
        }
    }

    /// Moves the grid to `offset`.
    ///
    /// Every programmatic move goes through here. A move without animation cuts short whatever the
    /// scroll view was doing, and UIKit ends a deceleration or a bounce cut short by calling the
    /// scroll view's delegate at once, while the offset is still the old one; ``isMovingOffset``
    /// keeps those calls from being taken for a scroll that settled on the month there. The caller
    /// reports the month itself. An animated move reports its end through the delegate, as ever.
    /// Either way the view has taken the grid over from the user.
    func moveOffset(to offset: CGPoint, animated: Bool) {
        isUserScrolling = false
        guard !animated else {
            collectionView.setContentOffset(offset, animated: true)
            return
        }
        isMovingOffset = true
        defer { isMovingOffset = false }
        collectionView.setContentOffset(offset, animated: false)
    }

    /// The content offset of the page of the month containing `date`, or `nil` when the grid does
    /// not have that month.
    func pageOffset(forMonthOf date: Date) -> CGPoint? {
        indexPathForDate(date).map { flowLayout.contentOffset(forSection: $0.section) }
    }

    func scrollViewOffset(for date: Date) -> CGPoint {
        pageOffset(forMonthOf: date) ?? .zero
    }

    /// Makes `date`, the first day of a month, the displayed month and writes its title.
    func displayDateOnHeader(_ date: Date) {
        displayDate = date
        updateTitle()
    }

    /// Writes the title of the displayed month in the header: the data source's, or the month and
    /// year from the formatters.
    ///
    /// Called when the month changes and after every reload, since a reload can bring new
    /// formatters, a new locale or a data source with another title.
    func updateTitle() {
        guard let displayDate else { return }
        headerView.monthLabel.text =
            dataSource?.title(forMonth: displayDate)
            ?? formatters.monthTitle.string(from: displayDate).capitalizingFirstLetter(with: style.locale)
    }
}

// MARK: - UIScrollViewDelegate

extension CalendarView {

    /// Forgets the month an animated scroll was heading for: the user has taken over.
    public func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        animationTargetMonth = nil
        isUserScrolling = true
    }

    /// Reports the month the user dragged to, unless the scroll view goes on decelerating.
    public func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        guard !decelerate else { return }  // scrollViewDidEndDecelerating reports once it settles
        isUserScrolling = false
        guard !isMovingOffset else { return }
        updateAndNotifyScrolling()
    }

    /// Reports the month the scroll view settled on.
    public func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        isUserScrolling = false
        guard !isMovingOffset else { return }  // interrupted by the view's own move
        animationTargetMonth = nil
        updateAndNotifyScrolling()
    }

    /// Reports the month an animated scroll reached, unless a newer animation interrupted it.
    public func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        guard !isMovingOffset else { return }  // interrupted by the view's own move
        if let target = animationTargetMonth, dateFromScrollViewPosition() != target {
            return  // interrupted by a newer animation; that one reports when it settles
        }
        animationTargetMonth = nil
        updateAndNotifyScrolling()
    }

    /// Makes the month on the current page the displayed month and reports it: to the delegate
    /// when it has not heard of the month yet, and to ``scrollDidSettle`` every time.
    func updateAndNotifyScrolling() {
        guard let date = dateFromScrollViewPosition() else { return }
        displayDateOnHeader(date)
        notifyScrolled(to: date)
        scrollDidSettle?(date)
    }

    /// Tells the delegate about a settled month, once per month.
    func notifyScrolled(to month: Date) {
        guard lastNotifiedMonth != month else { return }
        lastNotifiedMonth = month
        delegate?.calendar(self, didScrollToMonth: month)
    }

    /// The first day of the month on the current page.
    func dateFromScrollViewPosition() -> Date? {
        guard let grid = snapshot.grid,
            let section = flowLayout.section(atContentOffset: collectionView.contentOffset)
        else {
            return nil
        }
        return grid.firstDayOfMonth(inSection: section)
    }
}

// MARK: - The displayed month across reloads

extension MonthGrid {

    /// The first day of the month of the grid nearest to the month containing `date`.
    ///
    /// That month itself when the grid has it; otherwise the first month for an earlier date and
    /// the last month for a later one, the months of a grid being consecutive.
    func nearestMonth(to date: Date) -> Date {
        if let section = indexPath(for: date)?.section {
            return months[section].firstDate
        }
        let first = months[0].firstDate
        return date < first ? first : months[months.count - 1].firstDate
    }
}

extension Calendar {

    /// The first day of the month of this calendar that stands for `month`, the first day of a
    /// month of `previous`.
    ///
    /// The same month when only the time zone differs: 1 March in Athens becomes 1 March in New
    /// York, not the last evening of February. In another calendar system months do not line up,
    /// and the result is the month that holds the middle of the old one.
    ///
    /// - Parameters:
    ///   - month: The first day of a month, at the start of the day in `previous`.
    ///   - previous: The calendar `month` was computed in.
    /// - Returns: The first day of the matching month, at the start of the day in this calendar.
    func firstDayOfMonth(matching month: Date, in previous: Calendar) -> Date {
        let length = previous.range(of: .day, in: .month, for: month)?.count ?? 1
        let middle = previous.date(byAdding: .day, value: (length - 1) / 2, to: month) ?? month
        // Days run from midnight to midnight in every calendar, so Gregorian ones can carry the
        // day from one time zone to the other whatever the identifiers.
        var from = Calendar(identifier: .gregorian)
        from.timeZone = previous.timeZone
        var to = Calendar(identifier: .gregorian)
        to.timeZone = timeZone
        let day = from.dateComponents([.era, .year, .month, .day], from: middle)
        let moved = to.date(from: day) ?? middle
        return dateInterval(of: .month, for: moved)?.start ?? startOfDay(for: moved)
    }
}

extension String {

    /// This string with its first letter as `locale` writes the first letter of a title.
    ///
    /// The rest is left as it is, unlike `capitalized(with:)` on the whole string, which would
    /// also capitalise the "de" of "enero de 2024". The letter gets its title case, not its upper
    /// case: the two differ where a script keeps its capitals for text set all in capitals, as
    /// Georgian does, whose "იანვარი" stays as it is.
    func capitalizingFirstLetter(with locale: Locale) -> String {
        guard let first else { return self }
        return String(first).capitalized(with: locale) + dropFirst()
    }
}
