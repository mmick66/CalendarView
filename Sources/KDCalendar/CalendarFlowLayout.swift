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

open class CalendarFlowLayout: UICollectionViewFlowLayout {

    // The frames below mirror themselves right to left; UIKit must not flip them again.
    override open var flipsHorizontallyInOppositeLayoutDirection: Bool { false }

    // The pages that `rect` touches decide the cells, rather than the flow layout's own
    // arrangement, which does not mirror the months with the frames below.
    override open func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        guard let collectionView = self.collectionView else { return nil }

        let (start, end, pageLength) =
            scrollDirection == .vertical
            ? (rect.minY, rect.maxY, collectionView.frame.size.height)
            : (rect.minX, rect.maxX, collectionView.frame.size.width)
        guard pageLength > 0 else { return [] }

        let first = max(Int((start / pageLength).rounded(.down)), 0)
        let last = min(Int((end / pageLength).rounded(.up)) - 1, collectionView.numberOfSections - 1)
        guard first <= last else { return [] }

        return (first...last).flatMap { page in
            let section = mirroredPage(page)
            return (0..<collectionView.numberOfItems(inSection: section)).compactMap { item in
                layoutAttributesForItem(at: IndexPath(item: item, section: section))
            }
        }
        .filter { $0.frame.intersects(rect) }
    }

    override open func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        let attributes = UICollectionViewLayoutAttributes(forCellWith: indexPath)
        self.applyLayoutAttributes(attributes)
        return attributes
    }

    /// Whether the collection view runs right to left, so that the days of a week, and the
    /// months of a horizontal calendar, run from right to left.
    var isRightToLeft: Bool {
        collectionView?.effectiveUserInterfaceLayoutDirection == .rightToLeft
    }

    /// Maps a section to its page along the scrolling axis, and a page back to its section.
    ///
    /// Right to left, a horizontal calendar puts its first month on the last page.
    func mirroredPage(_ index: Int) -> Int {
        guard let collectionView, isRightToLeft, scrollDirection == .horizontal else { return index }
        return collectionView.numberOfSections - 1 - index
    }

    func applyLayoutAttributes(_ attributes: UICollectionViewLayoutAttributes) {
        guard attributes.representedElementKind == nil else { return }

        guard let collectionView = self.collectionView else { return }

        let column = attributes.indexPath.item % 7
        var xCellOffset = CGFloat(isRightToLeft ? 6 - column : column) * self.itemSize.width
        var yCellOffset = CGFloat(attributes.indexPath.item / 7) * self.itemSize.height

        let offset = CGFloat(mirroredPage(attributes.indexPath.section))

        switch self.scrollDirection {
        case .horizontal: xCellOffset += offset * collectionView.frame.size.width
        case .vertical: yCellOffset += offset * collectionView.frame.size.height
        @unknown default:
            fatalError()
        }

        // set frame
        attributes.frame = CGRect(
            x: xCellOffset,
            y: yCellOffset,
            width: self.itemSize.width,
            height: self.itemSize.height
        )
    }
}
