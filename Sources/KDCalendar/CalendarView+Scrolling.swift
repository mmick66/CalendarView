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
        collectionView.setContentOffset(offset, animated: animated)
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
        guard let displayDate else { return }

        guard let newDate = layoutCalendar.date(byAdding: .month, value: offset, to: displayDate) else { return }
        setDisplayDate(newDate, animated: true)
    }

    internal func resetDisplayDate() {
        guard let displayDate else { return }

        collectionView.setContentOffset(
            scrollViewOffset(for: displayDate),
            animated: false
        )
    }

    func scrollViewOffset(for date: Date) -> CGPoint {
        guard let section = indexPathForDate(date)?.section else { return .zero }
        return flowLayout.contentOffset(forSection: section)
    }

    func displayDateOnHeader(_ date: Date) {
        headerView.monthLabel.text =
            dataSource?.title(forMonth: date)
            ?? formatters.monthTitle.string(from: date).capitalized(with: style.locale)

        displayDate = date
    }
}

// MARK: - UIScrollViewDelegate

extension CalendarView {

    /// Forgets the month an animated scroll was heading for: the user has taken over.
    public func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        animationTargetMonth = nil
    }

    /// Reports the month the user dragged to, unless the scroll view goes on decelerating.
    public func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        guard !decelerate else { return }  // scrollViewDidEndDecelerating reports once it settles
        updateAndNotifyScrolling()
    }

    /// Reports the month the scroll view settled on.
    public func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        animationTargetMonth = nil
        updateAndNotifyScrolling()
    }

    /// Reports the month an animated scroll reached, unless a newer animation interrupted it.
    public func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        if let target = animationTargetMonth, dateFromScrollViewPosition() != target {
            return  // interrupted by a newer animation; that one reports when it settles
        }
        animationTargetMonth = nil
        updateAndNotifyScrolling()
    }

    func updateAndNotifyScrolling() {
        guard let date = dateFromScrollViewPosition() else { return }
        displayDateOnHeader(date)
        notifyScrolled(to: date)
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
