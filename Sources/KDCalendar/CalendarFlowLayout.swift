/*
 * CalendarFlowLayout.swift
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

/// Lays each month out as one page of the collection view: seven columns by six rows of
/// `itemSize` cells, the pages side by side (`.horizontal`) or stacked (`.vertical`).
///
/// It is a flow layout for its `itemSize` and `scrollDirection`, but it does not flow: the
/// content size and the cells in a rect come from the page grid, so a size that is not a
/// whole number of cells cannot wrap a row and leave cells out.
///
/// Right to left, the days of a week run from right to left and a horizontal calendar puts its
/// first month on the last page. The frames are mirrored here rather than with transforms.
open class CalendarFlowLayout: UICollectionViewFlowLayout {

    static let columns = 7

    /// The size of one page, a month.
    private var pageSize: CGSize {
        collectionView?.bounds.size ?? .zero
    }

    private var isVertical: Bool {
        scrollDirection == .vertical
    }

    // The frames below mirror themselves right to left; UIKit must not flip them again.
    override open var flipsHorizontallyInOppositeLayoutDirection: Bool { false }

    /// Whether the collection view runs right to left.
    var isRightToLeft: Bool {
        collectionView?.effectiveUserInterfaceLayoutDirection == .rightToLeft
    }

    /// Maps a section to its page along the scrolling axis, and a page back to its section.
    ///
    /// Right to left, a horizontal calendar puts its first month on the last page.
    func mirroredPage(_ index: Int) -> Int {
        guard let collectionView, isRightToLeft, !isVertical else { return index }
        return collectionView.numberOfSections - 1 - index
    }

    override open var collectionViewContentSize: CGSize {
        guard let collectionView = self.collectionView else { return .zero }
        let pages = CGFloat(collectionView.numberOfSections)
        let page = pageSize
        return isVertical
            ? CGSize(width: page.width, height: pages * page.height)
            : CGSize(width: pages * page.width, height: page.height)
    }

    override open func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
        newBounds.size != pageSize
    }

    override open func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        guard let collectionView = self.collectionView else { return nil }
        let sections = collectionView.numberOfSections
        let page = pageSize
        let (start, length) = isVertical ? (rect.minY, page.height) : (rect.minX, page.width)
        let end = isVertical ? rect.maxY : rect.maxX
        guard sections > 0, length > 0 else { return [] }

        let first = max(Int((start / length).rounded(.down)), 0)
        let last = min(Int((end / length).rounded(.down)), sections - 1)
        guard first <= last else { return [] }

        var result: [UICollectionViewLayoutAttributes] = []
        for page in first...last {
            let section = mirroredPage(page)
            for item in 0..<collectionView.numberOfItems(inSection: section) {
                let attributes = self.attributes(for: IndexPath(item: item, section: section))
                if attributes.frame.intersects(rect) {
                    result.append(attributes)
                }
            }
        }
        return result
    }

    override open func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        guard let collectionView = self.collectionView,
            indexPath.section < collectionView.numberOfSections,
            indexPath.item < collectionView.numberOfItems(inSection: indexPath.section)
        else {
            return nil
        }
        return attributes(for: indexPath)
    }

    private func attributes(for indexPath: IndexPath) -> UICollectionViewLayoutAttributes {
        let attributes = UICollectionViewLayoutAttributes(forCellWith: indexPath)
        let page = CGFloat(mirroredPage(indexPath.section))
        let column = indexPath.item % Self.columns
        var origin = CGPoint(
            x: CGFloat(isRightToLeft ? Self.columns - 1 - column : column) * itemSize.width,
            y: CGFloat(indexPath.item / Self.columns) * itemSize.height
        )
        if isVertical {
            origin.y += page * pageSize.height
        } else {
            origin.x += page * pageSize.width
        }
        attributes.frame = CGRect(origin: origin, size: itemSize)
        return attributes
    }
}
