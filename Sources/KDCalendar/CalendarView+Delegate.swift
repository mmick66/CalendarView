/*
 * CalendarView+Delegate.swift
 * Created by Michael Michailidis on 24/10/2017.
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

extension CalendarView: UICollectionViewDelegateFlowLayout {

    // MARK: Selection

    /// Whether the day at `indexPath` may be selected: it must be a day, in range, and allowed
    /// by the delegate.
    func shouldSelect(_ indexPath: IndexPath) -> Bool {
        guard let date = self.dateFromIndexPath(indexPath), !isOutOfRange(indexPath) else { return false }
        return delegate?.calendar(self, canSelectDate: date) ?? true
    }

    /// Selects the day at `indexPath` as a tap does, shows the change and notifies the delegate:
    /// first of the days the tap dropped, then of the tapped day, then of a range it completed.
    func didSelect(_ indexPath: IndexPath) {
        guard let date = self.dateFromIndexPath(indexPath) else { return }
        // The delegate may read the selection while it is asked which days are selectable, so
        // the change is worked out on a copy.
        var next = selection
        guard let change = next.tap(date, selectable: selectableDays(in:)) else { return }
        selection = next
        show(change)

        for dropped in change.deselected {
            delegate?.calendar(self, didDeselectDate: dropped)
        }
        delegate?.calendar(self, didSelectDate: date, withEvents: eventsByIndexPath[indexPath] ?? [])
        if let range = change.completedRange {
            delegate?.calendar(self, didSelectRange: range)
        }
    }

    /// Deselects the day at `indexPath`, shows the change and notifies the delegate. In range
    /// mode a deselection clears the whole range.
    func didDeselect(_ indexPath: IndexPath) {
        guard let date = self.dateFromIndexPath(indexPath) else { return }
        let change = selection.deselect(date)
        show(change)
        for dropped in change.deselected {
            delegate?.calendar(self, didDeselectDate: dropped)
        }
    }

    public func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        return shouldSelect(indexPath)
    }

    public func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        didSelect(indexPath)
    }

    public func collectionView(_ collectionView: UICollectionView, shouldDeselectItemAt indexPath: IndexPath) -> Bool {
        return enableDeselection
    }

    public func collectionView(_ collectionView: UICollectionView, didDeselectItemAt indexPath: IndexPath) {
        didDeselect(indexPath)
    }

    public func collectionView(_ collectionView: UICollectionView, shouldHighlightItemAt indexPath: IndexPath) -> Bool {
        return self.dateFromIndexPath(indexPath) != nil && !isOutOfRange(indexPath)
    }

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
        guard let months = currentMonths else { return nil }

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

        guard length > 0 else { return months.firstDay(ofSection: 0) }
        let page = min(max(Int((offset / length).rounded()), 0), months.numberOfSections - 1)
        return months.firstDay(ofSection: page)
    }

    func displayDateOnHeader(_ date: Date) {
        let formatter = DateFormatter()
        formatter.calendar = style.calendar
        formatter.timeZone = style.calendar.timeZone
        formatter.locale = style.locale
        formatter.setLocalizedDateFormatFromTemplate("yMMMM")

        self.headerView.monthLabel.text =
            dataSource?.headerString(date) ?? formatter.string(from: date).capitalized(with: style.locale)

        self.displayDate = date
    }
}
