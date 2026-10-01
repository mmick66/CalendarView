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
/// whole number of cells cannot wrap a row and leave cells out. The item size follows the
/// page: a seventh of its width by a sixth of its height.
///
/// Right to left, the days of a week run from right to left and a horizontal calendar puts its
/// first month on the last page. The frames are mirrored here rather than with transforms.
open class CalendarFlowLayout: UICollectionViewFlowLayout {

    static let columns = 7
    static let rows = 6

    /// The scrolling axis, which the pages follow.
    private enum Axis {
        case horizontal, vertical

        /// The extent of `size` along the axis.
        func length(of size: CGSize) -> CGFloat {
            self == .vertical ? size.height : size.width
        }

        /// The coordinate of `point` along the axis.
        func position(of point: CGPoint) -> CGFloat {
            self == .vertical ? point.y : point.x
        }

        /// The point `distance` along the axis from the origin.
        func point(along distance: CGFloat) -> CGPoint {
            self == .vertical ? CGPoint(x: 0, y: distance) : CGPoint(x: distance, y: 0)
        }

        /// `size` with its extent along the axis replaced by `length`.
        func size(_ size: CGSize, withLength length: CGFloat) -> CGSize {
            self == .vertical
                ? CGSize(width: size.width, height: length) : CGSize(width: length, height: size.height)
        }
    }

    private var axis: Axis {
        scrollDirection == .vertical ? .vertical : .horizontal
    }

    /// The size of one page, a month.
    private var pageSize: CGSize {
        collectionView?.bounds.size ?? .zero
    }

    // The frames below mirror themselves right to left; UIKit must not flip them again.
    override open var flipsHorizontallyInOppositeLayoutDirection: Bool { false }

    /// Whether the collection view runs right to left.
    private var isRightToLeft: Bool {
        collectionView?.effectiveUserInterfaceLayoutDirection == .rightToLeft
    }

    /// Maps a section to its page along the scrolling axis, and a page back to its section.
    ///
    /// Right to left, a horizontal calendar puts its first month on the last page.
    private func mirroredPage(_ index: Int) -> Int {
        guard let collectionView, isRightToLeft, axis == .horizontal else { return index }
        return collectionView.numberOfSections - 1 - index
    }

    /// The content offset that shows the month of `section`.
    func contentOffset(forSection section: Int) -> CGPoint {
        axis.point(along: CGFloat(mirroredPage(section)) * axis.length(of: pageSize))
    }

    /// The section of the page nearest to `offset`, or `nil` when there are no sections.
    ///
    /// Before the collection view has a size every offset is on the first section.
    func section(atContentOffset offset: CGPoint) -> Int? {
        guard let sections = collectionView?.numberOfSections, sections > 0 else { return nil }
        let length = axis.length(of: pageSize)
        guard length > 0 else { return 0 }
        let page = Int((axis.position(of: offset) / length).rounded())
        return mirroredPage(min(max(page, 0), sections - 1))
    }

    /// Sizes the cells to fill a page, keeping the last size while the page has no area.
    override open func prepare() {
        let page = pageSize
        let size = CGSize(width: page.width / CGFloat(Self.columns), height: page.height / CGFloat(Self.rows))
        if size.width > 0 && size.height > 0 && itemSize != size {
            itemSize = size
        }
        super.prepare()
    }

    override open var collectionViewContentSize: CGSize {
        guard let collectionView else { return .zero }
        let pages = CGFloat(collectionView.numberOfSections)
        let page = pageSize
        return axis.size(page, withLength: pages * axis.length(of: page))
    }

    override open func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
        newBounds.size != pageSize
    }

    override open func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        guard let collectionView else { return nil }
        let sections = collectionView.numberOfSections
        let length = axis.length(of: pageSize)
        guard sections > 0, length > 0 else { return [] }

        let start = axis.position(of: CGPoint(x: rect.minX, y: rect.minY))
        let end = axis.position(of: CGPoint(x: rect.maxX, y: rect.maxY))
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
        guard let collectionView,
            indexPath.section < collectionView.numberOfSections,
            indexPath.item < collectionView.numberOfItems(inSection: indexPath.section)
        else {
            return nil
        }
        return attributes(for: indexPath)
    }

    private func attributes(for indexPath: IndexPath) -> UICollectionViewLayoutAttributes {
        let attributes = UICollectionViewLayoutAttributes(forCellWith: indexPath)
        let page = contentOffset(forSection: indexPath.section)
        let column = indexPath.item % Self.columns
        let origin = CGPoint(
            x: page.x + CGFloat(isRightToLeft ? Self.columns - 1 - column : column) * itemSize.width,
            y: page.y + CGFloat(indexPath.item / Self.columns) * itemSize.height
        )
        attributes.frame = CGRect(origin: origin, size: itemSize)
        return attributes
    }
}
