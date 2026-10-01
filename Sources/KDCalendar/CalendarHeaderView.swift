/*
 * CalendarHeaderView.swift
 * Created by Michael Michailidis on 07/04/2015.
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

/// The header of a ``CalendarView``: the month title above a row of weekday labels.
open class CalendarHeaderView: UIView {

    private(set) var style: CalendarView.Style = .default
    /// The weekday names come from here; the calendar view builds them once per style.
    private(set) var formatters = CalendarView.Formatters(
        calendar: CalendarView.Style.default.resolvedCalendar.fixed, locale: CalendarView.Style.default.locale)

    let monthLabel = UILabel()

    let dayLabels = (0..<7).map { _ in UILabel() }

    /// Lays the weekday labels out in equal columns, mirrored right to left with the header.
    private let weekdaysStack = UIStackView()

    // The constants come from the style's margins; updateStyle() sets them.
    private lazy var monthTop = monthLabel.topAnchor.constraint(equalTo: topAnchor)
    private lazy var monthBottom = monthLabel.bottomAnchor.constraint(equalTo: weekdaysStack.topAnchor)
    private lazy var weekdaysBottom = weekdaysStack.bottomAnchor.constraint(equalTo: bottomAnchor)
    private lazy var weekdaysHeight = weekdaysStack.heightAnchor.constraint(equalToConstant: 0)

    public override init(frame: CGRect) {
        super.init(frame: frame)
        buildLabels()
    }

    /// Creates a header from an archive, with fresh labels.
    required public init?(coder: NSCoder) {
        super.init(coder: coder)
        // Labels decoded from an archive are replaced by fresh ones; the style recreates the text.
        subviews.forEach { $0.removeFromSuperview() }
        buildLabels()
    }

    private func buildLabels() {
        monthLabel.backgroundColor = .clear
        monthLabel.adjustsFontForContentSizeCategory = true
        monthLabel.accessibilityTraits = .header
        monthLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(monthLabel)

        for label in dayLabels {
            label.backgroundColor = .clear
            label.adjustsFontForContentSizeCategory = true
            weekdaysStack.addArrangedSubview(label)
        }
        weekdaysStack.axis = .horizontal
        weekdaysStack.distribution = .fillEqually
        weekdaysStack.semanticContentAttribute = semanticContentAttribute
        weekdaysStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(weekdaysStack)

        NSLayoutConstraint.activate([
            monthTop, monthBottom, weekdaysBottom, weekdaysHeight,
            monthLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            monthLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            weekdaysStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            weekdaysStack.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        updateStyle()
    }

    /// The weekday labels follow the header's direction: a stack view mirrors with its own
    /// semantic content attribute.
    open override var semanticContentAttribute: UISemanticContentAttribute {
        didSet {
            weekdaysStack.semanticContentAttribute = semanticContentAttribute
        }
    }

    /// Restyles the header with `style` and the formatters built for it.
    func setStyle(_ style: CalendarView.Style, formatters: CalendarView.Formatters) {
        self.style = style
        self.formatters = formatters
        updateStyle()
    }

    /// Applies the header's current style again: fonts, colours, margins and weekday names.
    ///
    /// The calendar view calls this whenever its ``CalendarView/style`` changes, so there is no
    /// need to call it yourself.
    public func updateStyle() {
        monthLabel.textAlignment = .center
        monthLabel.font = style.headerFont
        monthLabel.textColor = style.headerTextColor
        monthLabel.backgroundColor = style.headerBackgroundColor

        // Weekday symbols are indexed from Sunday; rotate so the first label is the first weekday.
        let symbols = formatters.weekdaySymbols
        let start = style.effectiveFirstWeekday - 1

        for (i, label) in dayLabels.enumerated() {
            let symbol = symbols.isEmpty ? "" : symbols[(start + i) % symbols.count]
            label.font = style.weekdaysFont
            label.text =
                style.weekdayCasing == .capitalized
                ? symbol.capitalized(with: style.locale)
                : symbol.uppercased(with: style.locale)
            label.textColor = style.weekdaysTextColor
            label.textAlignment = .center
        }

        backgroundColor = style.weekdaysBackgroundColor

        monthTop.constant = style.headerTopMargin
        monthBottom.constant = -style.weekdaysTopMargin
        weekdaysBottom.constant = -style.weekdaysBottomMargin
        weekdaysHeight.constant = style.weekdaysHeight
    }
}
