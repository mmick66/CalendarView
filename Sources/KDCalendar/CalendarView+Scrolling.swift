import UIKit

extension CalendarView {

    /// Whether the user can scroll between months. Programmatic scrolling always works.
    public var isScrollEnabled: Bool {
        get { collectionView.isScrollEnabled }
        set { collectionView.isScrollEnabled = newValue }
    }

    /// Scrolls to the month containing `date`. Dates outside the data source's months are ignored.
    ///
    /// The delegate receives `didScrollToMonth` once the month is on screen: when the animation
    /// ends, or immediately when `animated` is `false`, the view has no size yet or the month
    /// is already on screen.
    public func setDisplayDate(_ date: Date, animated: Bool = false) {
        guard let indexPath = self.indexPathForDate(date),
            let month = snapshot.grid?.firstDayOfMonth(inSection: indexPath.section)
        else {
            return
        }

        self.displayDateOnHeader(month)

        collectionView.layoutIfNeeded()
        let offset = self.scrollViewOffset(for: month)
        // UIKit sends no end-of-animation callback when the offset does not change, which is
        // always the case before the first layout, so those scrolls report at once.
        let animated =
            animated && collectionView.bounds.width > 0 && collectionView.bounds.height > 0
            && collectionView.contentOffset != offset
        animationTargetMonth = animated ? month : nil
        collectionView.setContentOffset(offset, animated: animated)
        if !animated {
            self.notifyScrolled(to: month)
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

        guard let displayDate = self.displayDate else { return }

        guard let newDate = self.calendar.date(byAdding: .month, value: offset, to: displayDate) else { return }
        self.setDisplayDate(newDate, animated: true)
    }

    internal func resetDisplayDate() {
        guard let displayDate = self.displayDate else { return }

        collectionView.setContentOffset(
            self.scrollViewOffset(for: displayDate),
            animated: false
        )
    }

    func scrollViewOffset(for date: Date) -> CGPoint {
        var point = CGPoint.zero

        guard let section = self.indexPathForDate(date)?.section else { return point }
        let page = flowLayout.mirroredPage(section)

        switch self.direction {
        case .horizontal: point.x = CGFloat(page) * self.collectionView.bounds.width
        case .vertical: point.y = CGFloat(page) * self.collectionView.bounds.height
        @unknown default:
            point.x = CGFloat(page) * self.collectionView.bounds.width
        }

        return point
    }

    func displayDateOnHeader(_ date: Date) {
        self.headerView.monthLabel.text =
            dataSource?.headerString(date)
            ?? formatters.monthTitle.string(from: date).capitalized(with: style.locale)

        self.displayDate = date
    }
}

extension CalendarView {

    // MARK: UIScrollViewDelegate

    public func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        animationTargetMonth = nil
    }

    public func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        guard !decelerate else { return }  // scrollViewDidEndDecelerating reports once it settles
        self.updateAndNotifyScrolling()
    }

    public func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        animationTargetMonth = nil
        self.updateAndNotifyScrolling()
    }

    public func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        if let target = animationTargetMonth, self.dateFromScrollViewPosition() != target {
            return  // interrupted by a newer animation; that one reports when it settles
        }
        animationTargetMonth = nil
        self.updateAndNotifyScrolling()
    }

    func updateAndNotifyScrolling() {
        guard let date = self.dateFromScrollViewPosition() else { return }
        self.displayDateOnHeader(date)
        self.notifyScrolled(to: date)
    }

    /// Tells the delegate about a settled month, once per month.
    func notifyScrolled(to month: Date) {
        guard lastNotifiedMonth != month else { return }
        lastNotifiedMonth = month
        self.delegate?.calendar(self, didScrollToMonth: month)
    }

    /// The first day of the month on the current page.
    func dateFromScrollViewPosition() -> Date? {
        guard let grid = snapshot.grid else { return nil }

        let offset: CGFloat
        let length: CGFloat
        switch self.direction {
        case .horizontal:
            offset = self.collectionView.contentOffset.x
            length = self.collectionView.bounds.size.width
        case .vertical:
            offset = self.collectionView.contentOffset.y
            length = self.collectionView.bounds.size.height
        @unknown default:
            offset = self.collectionView.contentOffset.x
            length = self.collectionView.bounds.size.width
        }

        guard length > 0 else { return grid.firstDayOfMonth(inSection: 0) }
        let page = min(max(Int((offset / length).rounded()), 0), grid.numberOfSections - 1)
        return grid.firstDayOfMonth(inSection: flowLayout.mirroredPage(page))
    }
}
