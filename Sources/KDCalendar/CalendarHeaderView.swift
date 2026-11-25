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
///
/// The header is as tall as ``CalendarView/Style/headerHeight`` says, and taller when its fonts
/// need more room, as the default fonts do at the larger Dynamic Type sizes. The weekday labels
/// show shorter names when the short ones do not fit their columns.
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
        // A title or a weekday wider than its label gets smaller rather than cut short.
        for label in dayLabels + [monthLabel] {
            label.adjustsFontSizeToFitWidth = true
            label.minimumScaleFactor = Metrics.minimumFontScale
            label.baselineAdjustment = .alignCenters
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

        // The labels scale their fonts by themselves. The header then needs its layout again, to
        // make room for them and to tell the calendar view that its height changed.
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (header: CalendarHeaderView, _) in
            header.setNeedsLayout()
        }
    }

    /// The header's proportions, which do not depend on the style.
    private enum Metrics {
        /// The smallest a label's font gets to fit its text, as a fraction of the style's font.
        static let minimumFontScale: CGFloat = 0.5
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

        let names = weekdays(from: formatters.weekdayNames)
        for (label, name) in zip(dayLabels, names) {
            label.font = style.weekdaysFont
            label.textColor = style.weekdaysTextColor
            label.textAlignment = .center
            // VoiceOver reads the day's name in full, whatever the label has room to show.
            label.accessibilityLabel = name
        }

        backgroundColor = style.weekdaysBackgroundColor

        monthTop.constant = style.headerTopMargin
        monthBottom.constant = -style.weekdaysTopMargin
        weekdaysBottom.constant = -style.weekdaysBottomMargin
        fitWeekdays()
        setNeedsLayout()
    }

    // MARK: - Fitting the fonts

    /// The height the header needs for its style and its fonts.
    ///
    /// This is ``CalendarView/Style/headerHeight`` while the month title and the weekday labels
    /// have room for a line of their fonts, and that much more when they do not.
    ///
    /// The calendar view sizes the header with it, and lays out again when it changes.
    var fittingHeight: CGFloat {
        let extra = growth
        return style.headerHeight + extra.month + extra.weekdays
    }

    /// How much taller than the style says the month title and the weekday labels have to be to
    /// show a line of their fonts.
    ///
    /// A part the style gives no height stays without one, and so does all of a header whose
    /// height is zero: a style can still hide them.
    private var growth: (month: CGFloat, weekdays: CGFloat) {
        guard style.headerHeight > 0 else { return (0, 0) }
        func growth(of height: CGFloat, for font: UIFont) -> CGFloat {
            height > 0 ? max(0, ceil(font.lineHeight) - height) : 0
        }
        let fonts = scaledFonts
        let margins = style.headerTopMargin + style.weekdaysTopMargin + style.weekdaysBottomMargin
        let monthHeight = style.headerHeight - margins - style.weekdaysHeight
        return (growth(of: monthHeight, for: fonts.month), growth(of: style.weekdaysHeight, for: fonts.weekdays))
    }

    /// The fonts the labels draw with: the style's, scaled for the content size category.
    ///
    /// The labels do the scaling, so this brings their traits up to date first.
    private var scaledFonts: (month: UIFont, weekdays: UIFont) {
        monthLabel.updateTraitsIfNeeded()
        dayLabels.forEach { $0.updateTraitsIfNeeded() }
        return (monthLabel.font ?? style.headerFont, dayLabels.first?.font ?? style.weekdaysFont)
    }

    /// The weekday `symbols`, given Sunday first, in the order of the labels.
    private func weekdays(from symbols: [String]) -> [String] {
        guard !symbols.isEmpty else { return dayLabels.map { _ in "" } }
        // Weekday symbols are indexed from Sunday; rotate so the first label is the first weekday.
        let start = style.effectiveFirstWeekday - 1
        return dayLabels.indices.map { symbols[(start + $0) % symbols.count] }
    }

    /// The text of the weekday labels for `symbols`, given Sunday first: in the order of the
    /// labels and in the style's letter case.
    private func weekdayTexts(from symbols: [String]) -> [String] {
        weekdays(from: symbols).map { symbol in
            style.weekdayCasing == .capitalized
                ? symbol.capitalized(with: style.locale)
                : symbol.uppercased(with: style.locale)
        }
    }

    /// Gives the weekday labels the height their font needs and the names their columns have
    /// room for: the short ones, such as "Mon", or the shortest, such as "M".
    private func fitWeekdays() {
        let height = style.weekdaysHeight + growth.weekdays
        if weekdaysHeight.constant != height {
            weekdaysHeight.constant = height
        }

        var texts = weekdayTexts(from: formatters.weekdaySymbols)
        let font = scaledFonts.weekdays
        let columnWidth = bounds.width / CGFloat(dayLabels.count)
        let fits = texts.allSatisfy { ceil(($0 as NSString).size(withAttributes: [.font: font]).width) <= columnWidth }
        // Before the header has a width there is nothing to fit the names to.
        if !fits, columnWidth > 0, !formatters.narrowWeekdaySymbols.isEmpty {
            texts = weekdayTexts(from: formatters.narrowWeekdaySymbols)
        }
        for (label, text) in zip(dayLabels, texts) where label.text != text {
            label.text = text
        }
    }

    /// Fits the weekday labels to the header's width and to the fonts as they are now.
    ///
    /// When the fonts have changed the height the header needs, as a new content size category
    /// does, the superview, the calendar view, is asked to lay out again and resize the header.
    open override func layoutSubviews() {
        fitWeekdays()
        super.layoutSubviews()
        if abs(fittingHeight - bounds.height) > 0.5 {
            superview?.setNeedsLayout()
        }
    }
}
