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
    
    
    override open func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        
        return super.layoutAttributesForElements(in: rect)?.map { attrs in
            let attrscp = attrs.copy() as! UICollectionViewLayoutAttributes
            self.applyLayoutAttributes(attrscp)
            return attrscp
        }
    }
    
    override open func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        
        if let attrs = super.layoutAttributesForItem(at: indexPath) {
            let attrscp = attrs.copy() as! UICollectionViewLayoutAttributes
            self.applyLayoutAttributes(attrscp)
            return attrscp
        }
        return nil
    }
    
    func applyLayoutAttributes(_ attributes : UICollectionViewLayoutAttributes) {
        guard attributes.representedElementKind == nil else { return }
        
        guard let collectionView = self.collectionView else { return }
        
        var xCellOffset = CGFloat(attributes.indexPath.item % 7) * self.itemSize.width
        var yCellOffset = CGFloat(attributes.indexPath.item / 7) * self.itemSize.height
        
        let offset = CGFloat(attributes.indexPath.section)
        
        switch self.scrollDirection {
        case .horizontal:   xCellOffset += offset * collectionView.frame.size.width
        case .vertical:     yCellOffset += offset * collectionView.frame.size.height
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
