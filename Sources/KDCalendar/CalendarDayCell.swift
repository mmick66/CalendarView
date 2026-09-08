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

/// One day in the month grid. Its look is derived from its flags every time one changes, so a
/// reused cell never carries the previous day's state.
open class CalendarDayCell: UICollectionViewCell {

    var style: CalendarView.Style = .default {
        didSet {
            applyStyle()
            setNeedsLayout()
        }
    }

    /// The day this cell shows, at the start of the day, or `nil` for an empty cell.
    var date: Date?

    var eventsCount = 0 {
        didSet {
            self.dotsView.isHidden = (eventsCount == 0)
            self.setNeedsLayout()
        }
    }

    var day: Int? {
        set {
            guard let value = newValue else { return self.textLabel.text = nil }
            self.textLabel.text = String(value)
        }
        get {
            guard let value = self.textLabel.text else { return nil }
            return Int(value)
        }
    }

    var isToday: Bool = false {
        didSet { applyStyle() }
    }

    var isOutOfRange: Bool = false {
        didSet { applyStyle() }
    }

    var isAdjacent: Bool = false {
        didSet { applyStyle() }
    }

    var isWeekend: Bool = false {
        didSet { applyStyle() }
    }

    open override var isSelected: Bool {
        didSet { applyStyle() }
    }

    // MARK: - Public methods

    /// Resets the day flags and the derived look. `prepareForReuse` calls this.
    public func clearStyles() {
        isToday = false
        isOutOfRange = false
        isAdjacent = false
        isWeekend = false
        eventsCount = 0
        date = nil
        day = nil
        isHidden = false
        applyStyle()
    }

    open override func prepareForReuse() {
        super.prepareForReuse()
        clearStyles()
    }

    let textLabel = UILabel()
    let dotsView = UIView()
    let bgView = UIView()

    override init(frame: CGRect) {

        self.textLabel.textAlignment = NSTextAlignment.center

        super.init(frame: frame)

        self.addSubview(self.bgView)
        self.addSubview(self.textLabel)

        self.addSubview(self.dotsView)

        self.applyStyle()
    }

    required public init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }

    override open func layoutSubviews() {

        super.layoutSubviews()

        var elementsFrame = self.bounds.insetBy(dx: 3.0, dy: 3.0)

        if style.cellShape.isRound {  // square of
            let smallestSide = min(elementsFrame.width, elementsFrame.height)
            elementsFrame = elementsFrame.insetBy(
                dx: (elementsFrame.width - smallestSide) / 2.0,
                dy: (elementsFrame.height - smallestSide) / 2.0
            )
        }

        self.bgView.frame = elementsFrame
        self.textLabel.frame = elementsFrame

        let size = self.bounds.height * 0.08  // always a percentage of the whole cell
        self.dotsView.frame = CGRect(x: 0, y: 0, width: size, height: size)
        self.dotsView.center = CGPoint(x: self.textLabel.center.x, y: self.bounds.height - (2.5 * size))
        self.dotsView.layer.cornerRadius = size * 0.5  // round it

        switch style.cellShape {
        case .square:
            self.bgView.layer.cornerRadius = 0.0
        case .round:
            self.bgView.layer.cornerRadius = elementsFrame.width * 0.5
        case .bevel(let radius):
            self.bgView.layer.cornerRadius = radius
        }
    }

    /// Derives every colour from the flags. Precedence for the text: selected, out of range,
    /// today, adjacent, weekend, default. The background marks today unless out of range.
    private func applyStyle() {
        self.dotsView.backgroundColor = style.cellEventColor
        self.textLabel.font = style.cellFont

        if isSelected {
            self.bgView.layer.borderColor = style.cellSelectedBorderColor.cgColor
            self.bgView.layer.borderWidth = style.cellSelectedBorderWidth
            self.bgView.backgroundColor = style.cellSelectedColor
        } else {
            self.bgView.layer.borderColor = style.cellBorderColor.cgColor
            self.bgView.layer.borderWidth = style.cellBorderWidth
            self.bgView.backgroundColor = (isToday && !isOutOfRange) ? style.cellColorToday : style.cellColorDefault
        }

        if isSelected {
            self.textLabel.textColor = style.cellSelectedTextColor
        } else if isOutOfRange {
            self.textLabel.textColor = style.cellColorOutOfRange
        } else if isToday {
            self.textLabel.textColor = style.cellTextColorToday
        } else if isAdjacent {
            self.textLabel.textColor = style.cellColorAdjacent
        } else if isWeekend {
            self.textLabel.textColor = style.cellTextColorWeekend
        } else {
            self.textLabel.textColor = style.cellTextColorDefault
        }
    }
}
