/*
 * CalendarDayCell.swift
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

/// Everything a day cell shows. `cellForItemAt` builds one per cell and the cell applies it in a
/// single pass, so a reused cell never carries the previous day's state.
struct DayCellConfiguration: Equatable {
    /// The number shown, or `nil` for a blank cell.
    var day: Int?
    /// The day this cell shows, at the start of the day, or `nil` for an adjacent or empty cell.
    var date: Date?
    var isToday = false
    var isOutOfRange = false
    /// A day of the previous or next month, shown only as context for the grid.
    var isAdjacent = false
    var isWeekend = false
    var eventsCount = 0
    var style: CalendarView.Style = .default
    var accessibilityLabel: String?
    /// Hides the cell, for the cells outside the month when adjacent days are not shown.
    var isHidden = false

    /// The colours and accessibility state derived from the flags.
    struct Appearance: Equatable {
        var textColor: UIColor
        var backgroundColor: UIColor
        var borderColor: UIColor
        var borderWidth: CGFloat
        var isAccessibilityElement: Bool
        var accessibilityTraits: UIAccessibilityTraits
    }

    /// Precedence for the text: selected, out of range, today, adjacent, weekend, default.
    ///
    /// The background marks selection, then today unless out of range, and adjacent days have none.
    func appearance(isSelected: Bool) -> Appearance {
        let textColor: UIColor
        if isSelected {
            textColor = style.cellSelectedTextColor
        } else if isOutOfRange {
            textColor = style.cellColorOutOfRange
        } else if isToday {
            textColor = style.cellTextColorToday
        } else if isAdjacent {
            textColor = style.cellColorAdjacent
        } else if isWeekend {
            textColor = style.cellTextColorWeekend
        } else {
            textColor = style.cellTextColorDefault
        }

        let backgroundColor: UIColor
        if isSelected {
            backgroundColor = style.cellSelectedColor
        } else if isAdjacent {
            backgroundColor = .clear
        } else {
            backgroundColor = (isToday && !isOutOfRange) ? style.cellColorToday : style.cellColorDefault
        }

        var traits: UIAccessibilityTraits = .button
        if isSelected { traits.insert(.selected) }
        if isOutOfRange || isAdjacent { traits.insert(.notEnabled) }

        return Appearance(
            textColor: textColor,
            backgroundColor: backgroundColor,
            borderColor: isSelected ? style.cellSelectedBorderColor : style.cellBorderColor,
            borderWidth: isSelected ? style.cellSelectedBorderWidth : style.cellBorderWidth,
            // Adjacent days are only context for the grid and cannot be selected, so VoiceOver skips them.
            isAccessibilityElement: !isAdjacent,
            accessibilityTraits: traits
        )
    }
}

/// One day in the month grid.
///
/// Its look is derived from the day it is configured with and whether it is selected.
open class CalendarDayCell: UICollectionViewCell {

    var configuration = DayCellConfiguration() {
        didSet {
            textLabel.text = configuration.day.map(String.init)
            dotsView.isHidden = configuration.eventsCount == 0
            accessibilityLabel = configuration.accessibilityLabel
            isHidden = configuration.isHidden
            applyStyle()
            setNeedsLayout()
        }
    }

    var style: CalendarView.Style { configuration.style }

    open override var isSelected: Bool {
        didSet { applyStyle() }
    }

    // MARK: - Public methods

    /// Resets the day and the derived look, keeping the style. `prepareForReuse` calls this.
    public func clearStyles() {
        configuration = DayCellConfiguration(style: configuration.style)
    }

    open override func prepareForReuse() {
        super.prepareForReuse()
        clearStyles()
    }

    let textLabel = UILabel()
    let dotsView = UIView()
    let bgView = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        buildSubviews()
    }

    /// Creates a cell from an archive, with fresh subviews.
    required public init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        contentView.subviews.forEach { $0.removeFromSuperview() }
        subviews.filter { $0 !== contentView }.forEach { $0.removeFromSuperview() }
        buildSubviews()
    }

    private func buildSubviews() {
        self.textLabel.textAlignment = NSTextAlignment.center

        self.addSubview(self.bgView)
        self.addSubview(self.textLabel)
        self.addSubview(self.dotsView)

        self.textLabel.adjustsFontForContentSizeCategory = true
        self.dotsView.isHidden = true
        self.applyStyle()

        // Border colours are CGColors, which do not follow appearance changes on their own:
        // reapply them whenever a trait a dynamic colour may depend on changes (style, contrast, level...).
        registerForTraitChanges(UITraitCollection.systemTraitsAffectingColorAppearance) {
            (cell: CalendarDayCell, _) in
            cell.applyStyle()
        }
    }

    /// The cell's proportions, which do not depend on the style.
    private enum Metrics {
        /// The gap between the cell's edges and its background and label.
        static let contentInset: CGFloat = 3
        /// The event dot's diameter, as a fraction of the cell's height.
        static let dotDiameterRatio: CGFloat = 0.08
        /// The distance from the cell's bottom edge to the dot's centre, in dot diameters.
        static let dotBottomOffset: CGFloat = 2.5
    }

    override open func layoutSubviews() {
        super.layoutSubviews()

        let contentFrame = bounds.insetBy(dx: Metrics.contentInset, dy: Metrics.contentInset)
        let backgroundFrame = style.cellShape.backgroundFrame(in: contentFrame)
        bgView.frame = backgroundFrame
        bgView.layer.cornerRadius = style.cellShape.cornerRadius(for: backgroundFrame)
        textLabel.frame = backgroundFrame

        let dotDiameter = bounds.height * Metrics.dotDiameterRatio
        dotsView.frame = CGRect(x: 0, y: 0, width: dotDiameter, height: dotDiameter)
        dotsView.center = CGPoint(
            x: backgroundFrame.midX,
            y: bounds.height - Metrics.dotBottomOffset * dotDiameter
        )
        dotsView.layer.cornerRadius = dotDiameter / 2
    }

    private func applyStyle() {
        let appearance = configuration.appearance(isSelected: isSelected)
        self.dotsView.backgroundColor = style.cellEventColor
        self.textLabel.font = style.cellFont
        self.textLabel.textColor = appearance.textColor
        self.bgView.backgroundColor = appearance.backgroundColor
        self.bgView.layer.borderColor = appearance.borderColor.resolvedColor(with: traitCollection).cgColor
        self.bgView.layer.borderWidth = appearance.borderWidth
        self.isAccessibilityElement = appearance.isAccessibilityElement
        self.accessibilityTraits = appearance.accessibilityTraits
    }
}
