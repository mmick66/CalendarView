import SwiftUI
import Testing
import UIKit

@testable import KDCalendar

/// Dark mode, Dynamic Type, accessibility, scrolling control and the SwiftUI wrapper.
@Suite(.serialized)
@MainActor
struct PlatformTests: CalendarFixture {

    static let window = makeWindow(height: 600)
    let retained = Retained()

    init() {
        Self.resetWindow()
    }

    @Test func defaultColoursAdaptToDarkMode() {
        let style = CalendarView.Style.default
        let light = UITraitCollection(userInterfaceStyle: .light)
        let dark = UITraitCollection(userInterfaceStyle: .dark)
        #expect(
            style.headerBackgroundColor.resolvedColor(with: light)
                != style.headerBackgroundColor.resolvedColor(with: dark))
        #expect(style.cellColorDefault.resolvedColor(with: light) != style.cellColorDefault.resolvedColor(with: dark))
        #expect(
            style.cellSelectedTextColor.resolvedColor(with: light)
                != style.cellSelectedTextColor.resolvedColor(with: dark))
        #expect(CalendarView.Style() == CalendarView.Style.default, "two default styles are equal")
    }

    @Test func defaultFontsScaleWithDynamicType() {
        let style = CalendarView.Style.default
        let large = UITraitCollection(preferredContentSizeCategory: .accessibilityExtraLarge)
        let scaled = UIFontMetrics(forTextStyle: .body).scaledFont(
            for: UIFont.systemFont(ofSize: 17), compatibleWith: large)
        #expect(scaled.pointSize > style.cellFont.pointSize)
        let view = makeCalendar(start: date(2024, 1, 1), end: date(2024, 1, 31))
        #expect(cell(view, IndexPath(item: 0, section: 0))?.textLabel.adjustsFontForContentSizeCategory == true)
        #expect(view.headerView.monthLabel.adjustsFontForContentSizeCategory == true)
    }

    @Test func dayCellsDescribeThemselvesToVoiceOver() {
        let view = makeCalendar(start: date(2024, 1, 10), end: date(2024, 1, 20))
        view.events = [
            CalendarEvent(title: "a", startDate: date(2024, 1, 15), endDate: date(2024, 1, 15).addingTimeInterval(3600))
        ]
        view.layoutIfNeeded()
        // January 2024 starts on a Monday, so day n is item n - 1.
        let fifteenth = cell(view, IndexPath(item: 14, section: 0))
        #expect(fifteenth?.isAccessibilityElement == true)
        #expect(fifteenth?.accessibilityLabel == "Monday, January 15, 2024, 1 event")
        #expect(fifteenth?.accessibilityTraits.contains(.button) == true)
        #expect(fifteenth?.accessibilityTraits.contains(.notEnabled) == false)
        let outOfRange = cell(view, IndexPath(item: 2, section: 0))
        #expect(outOfRange?.accessibilityLabel == "Wednesday, January 3, 2024")
        #expect(outOfRange?.accessibilityTraits.contains(.notEnabled) == true)
        view.selectDate(date(2024, 1, 15))
        #expect(fifteenth?.accessibilityTraits.contains(.selected) == true)
        #expect(view.headerView.monthLabel.accessibilityTraits.contains(.header) == true)
    }

    @Test func reusedCellsDoNotKeepTheirVoiceOverLabelAsAdjacentDays() {
        let view = makeCalendar(start: date(2024, 1, 1), end: date(2024, 3, 31))
        view.style.showAdjacentDays = true
        view.layoutIfNeeded()
        // January 2024 starts on a Monday, so the 5th is item 4.
        let reused = cell(view, IndexPath(item: 4, section: 0))!
        #expect(reused.accessibilityLabel == "Friday, January 5, 2024")
        reused.prepareForReuse()
        #expect(reused.accessibilityLabel == nil)
        reused.configuration.isAdjacent = true
        #expect(reused.isAccessibilityElement == false, "adjacent days cannot be selected")
        reused.configuration.isAdjacent = false
        #expect(reused.isAccessibilityElement == true)
        // Scrolling recycles in-month cells as adjacent days of the next months.
        for month in [2, 3] {
            view.setDisplayDate(date(2024, month, 1))
            view.layoutIfNeeded()
        }
        let adjacent = view.collectionView.visibleCells.compactMap { $0 as? CalendarDayCell }.filter(
            \.configuration.isAdjacent)
        #expect(!adjacent.isEmpty)
        for dayCell in adjacent {
            #expect(dayCell.accessibilityLabel == nil)
            #expect(dayCell.isAccessibilityElement == false)
        }
    }

    @Test func todayIsSpokenAsSuch() {
        let now = Date()
        let local = Calendar.current
        let view = makeCalendar(
            start: local.date(byAdding: .day, value: -3, to: now)!, end: local.date(byAdding: .day, value: 3, to: now)!,
            calendar: local)
        view.setDisplayDate(now)
        view.layoutIfNeeded()
        let today = cell(view, view.indexPathForDate(now)!)
        #expect(today?.accessibilityLabel?.hasSuffix(", Today") == true)
    }

    @Test func scrollingCanBeDisabled() {
        // Issue #126.
        let view = makeCalendar(start: date(2024, 1, 1), end: date(2024, 3, 31))
        #expect(view.isScrollEnabled == true)
        view.isScrollEnabled = false
        #expect(view.collectionView.isScrollEnabled == false)
        view.setDisplayDate(date(2024, 2, 1))
        #expect(view.displayDate == date(2024, 2, 1), "programmatic scrolling still works")
    }

    // MARK: Dynamic Type

    /// Gives `view` a text size, as the user's setting does, and lays it out.
    private func setTextSize(_ category: UIContentSizeCategory, of view: CalendarView) {
        view.traitOverrides.preferredContentSizeCategory = category
        view.layoutIfNeeded()
    }

    /// The width `label` needs to draw its text in its font, unshrunk.
    private func textWidth(of label: UILabel) -> CGFloat {
        ceil(((label.text ?? "") as NSString).size(withAttributes: [.font: label.font!]).width)
    }

    @Test func headerGrowsToFitItsFontsAtTheLargestTextSize() {
        let view = makeCalendar(start: date(2024, 1, 1), end: date(2024, 3, 31))
        let header = view.headerView
        setTextSize(.large, of: view)
        #expect(header.frame.height == 80, "the style's height at the default size")

        setTextSize(.accessibilityExtraExtraExtraLarge, of: view)
        #expect(header.monthLabel.font.pointSize > 40, "the fonts did scale")
        #expect(header.monthLabel.frame.height >= header.monthLabel.font.lineHeight, "the title has its line")
        for label in header.dayLabels {
            #expect(label.frame.height >= label.font.lineHeight, "a weekday has its line")
        }
        #expect(header.frame.height > 80)
        #expect(header.frame.height == header.fittingHeight)
        #expect(header.bounds.height == header.dayLabels[0].superview!.frame.maxY + view.style.weekdaysBottomMargin)
        #expect(view.collectionView.frame.minY == header.frame.maxY, "the grid starts below the taller header")
        #expect(view.collectionView.frame.maxY == view.bounds.maxY)

        // The header is laid out again when the size changes back.
        setTextSize(.large, of: view)
        #expect(header.frame.height == 80)
        #expect(header.monthLabel.frame == CGRect(x: 0, y: 5, width: 350, height: 30))
        #expect(view.collectionView.frame == CGRect(x: 0, y: 80, width: 350, height: 340))
    }

    @Test func headerGrowsOnlyWhereTheStyleGivesItRoom() {
        let view = makeCalendar(start: date(2024, 1, 1), end: date(2024, 3, 31))
        // A custom font too tall for the style's heights makes room for itself at any text size.
        view.style.headerFont = UIFont.systemFont(ofSize: 40)
        setTextSize(.large, of: view)
        let line = ceil(view.style.headerFont.lineHeight)
        #expect(view.headerView.monthLabel.frame.height == line)
        #expect(view.headerView.frame.height == 80 - 30 + line)

        // A header the style gives no height stays without one.
        view.style.headerHeight = 0
        setTextSize(.accessibilityExtraExtraExtraLarge, of: view)
        #expect(view.headerView.frame.height == 0)
        #expect(view.collectionView.frame == view.bounds)
    }

    @Test func weekdayLabelsUseShorterNamesRatherThanTruncate() {
        let view = makeCalendar(start: date(2024, 1, 1), end: date(2024, 3, 31))
        let labels = view.headerView.dayLabels
        setTextSize(.large, of: view)
        #expect(labels.map(\.text) == ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"])

        setTextSize(.accessibilityExtraExtraExtraLarge, of: view)
        #expect(
            labels.map(\.text) == ["M", "T", "W", "T", "F", "S", "S"], "\"Mon\" is 77 points wide in a 50 point column")
        for label in labels {
            #expect(textWidth(of: label) <= label.frame.width, "\(label.text ?? "") fits its column")
            #expect(label.adjustsFontSizeToFitWidth, "and a wider name would shrink")
        }
        #expect(
            labels.map(\.accessibilityLabel) == [
                "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday",
            ], "VoiceOver still reads the names in full")

        // The names follow the width as well as the text size.
        view.frame.size.width = 700
        view.layoutIfNeeded()
        #expect(labels.map(\.text) == ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"])
        view.style.weekdayCasing = .uppercase
        view.frame.size.width = 350
        view.layoutIfNeeded()
        #expect(labels.map(\.text) == ["M", "T", "W", "T", "F", "S", "S"])
        setTextSize(.large, of: view)
        #expect(labels.map(\.text) == ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"])
    }

    @Test func dayNumbersShrinkToFitTheirCells() {
        let view = makeCalendar(start: date(2024, 1, 1), end: date(2024, 3, 31))
        func dayCells() -> [CalendarDayCell] {
            view.collectionView.visibleCells.compactMap { $0 as? CalendarDayCell }.filter {
                $0.configuration.day != nil
            }
        }
        setTextSize(.large, of: view)
        #expect(dayCells().count == 31)
        #expect(dayCells().allSatisfy { $0.textLabel.font.pointSize == 17 }, "the style's font where it fits")

        setTextSize(.accessibilityExtraExtraExtraLarge, of: view)
        let scaled = UIFontMetrics(forTextStyle: .body).scaledFont(
            for: UIFont.systemFont(ofSize: 17), compatibleWith: view.traitCollection)
        #expect(scaled.lineHeight > dayCells()[0].textLabel.frame.height, "the scaled font is too tall for a cell")
        for dayCell in dayCells() {
            let label = dayCell.textLabel
            #expect(label.font.lineHeight <= label.frame.height, "day \(label.text ?? "") has its line")
            #expect(textWidth(of: label) <= label.frame.width, "day \(label.text ?? "") has its width")
        }
        #expect(Set(dayCells().map { $0.textLabel.font.pointSize }).count == 1, "one size for every day of the month")
        #expect(dayCells()[0].textLabel.font.pointSize > 17, "still larger than at the default size")

        // Selecting a day restyles its cell; the number stays fitted.
        view.selectDate(date(2024, 1, 15))
        let selected = cell(view, IndexPath(item: 14, section: 0))!
        #expect(selected.isSelected)
        #expect(selected.textLabel.font.lineHeight <= selected.textLabel.frame.height)

        // A small calendar leaves its cells little room: the number gets as small as it has to
        // and is never replaced by an ellipsis.
        view.frame.size = CGSize(width: 255, height: 255)
        view.layoutIfNeeded()
        #expect(dayCells().count == 31)
        for dayCell in dayCells() {
            let label = dayCell.textLabel
            #expect(label.font.pointSize < 17)
            #expect(label.font.lineHeight <= label.frame.height, "day \(label.text ?? "") has its line")
            #expect(textWidth(of: label) <= label.frame.width, "day \(label.text ?? "") has its width")
            #expect(label.lineBreakMode == .byClipping)
        }

        view.frame.size = CGSize(width: 350, height: 420)
        setTextSize(.large, of: view)
        #expect(dayCells().allSatisfy { $0.textLabel.font.pointSize == 17 }, "and back")
    }

    @Test func verticalCalendarKeepsItsMonthWhenTheHeaderChangesHeight() {
        let view = makeCalendar(start: date(2024, 1, 1), end: date(2024, 6, 30), direction: .vertical)
        setTextSize(.large, of: view)
        view.setDisplayDate(date(2024, 3, 10))
        view.layoutIfNeeded()
        #expect(view.collectionView.contentOffset == CGPoint(x: 0, y: 2 * 340))

        // A taller header leaves shorter pages: the third one starts higher up.
        setTextSize(.accessibilityExtraExtraExtraLarge, of: view)
        let page = view.collectionView.bounds.height
        #expect(page < 340)
        #expect(view.collectionView.contentOffset == CGPoint(x: 0, y: 2 * page))
        #expect(view.displayDate == date(2024, 3, 1))

        setTextSize(.large, of: view)
        view.style.headerHeight = 140
        view.layoutIfNeeded()
        #expect(view.collectionView.contentOffset == CGPoint(x: 0, y: 2 * 280), "a new style height does the same")
    }

    // MARK: Localisation

    /// The month title of 15 January 2024 in a calendar and a locale.
    private func monthTitle(_ identifier: Calendar.Identifier, _ locale: String) -> String {
        var calendar = Calendar(identifier: identifier)
        calendar.timeZone = utc.timeZone
        let formatters = CalendarView.Formatters(calendar: calendar, locale: Locale(identifier: locale))
        return formatters.monthTitle.string(from: date(2024, 1, 15))
    }

    @Test func monthTitleNamesTheEraWhereAYearNeedsIt() {
        // Reiwa 6: "January 6" names no year.
        let japanese = monthTitle(.japanese, "en_US")
        #expect(japanese.contains("January") && japanese.contains("Reiwa") && japanese.contains("6"))
        #expect(monthTitle(.japanese, "ja_JP") == "令和6年1月")
        // The Chinese calendar counts sixty years to an era: its title names the year by the
        // Gregorian year it started in rather than "40".
        #expect(monthTitle(.chinese, "en_US").contains("2023"))
        #expect(monthTitle(.chinese, "zh_CN").contains("2023"))

        // Where the year's number is enough, the title stays as it was.
        #expect(monthTitle(.gregorian, "en_US") == "January 2024")
        #expect(monthTitle(.gregorian, "ja_JP") == "2024年1月")
        #expect(monthTitle(.hebrew, "en_US") == "Shevat 5784")
        #expect(monthTitle(.buddhist, "en_US") == "January 2567")
        #expect(monthTitle(.persian, "en_US") == "Dey 1402")
        #expect(monthTitle(.republicOfChina, "en_US") == "January 113")
        #expect(monthTitle(.islamicUmmAlQura, "en_US") == "Rajab 1445")

        var calendar = Calendar(identifier: .japanese)
        calendar.timeZone = utc.timeZone
        let view = makeCalendar(start: date(2024, 1, 1), end: date(2024, 3, 31), calendar: calendar)
        #expect(view.headerView.monthLabel.text?.contains("Reiwa") == true, "the header shows it")
    }

    @Test func voiceOverSpeaksTheWholeLabelInTheStyleLocalesLanguage() {
        let monday = date(2024, 1, 15)
        func label(_ locale: String, isToday: Bool = false, events: Int = 0) -> String {
            let view = makeCalendar(start: date(2024, 1, 1), end: date(2024, 1, 31), locale: Locale(identifier: locale))
            return view.accessibilityLabel(for: monday, isToday: isToday, eventsCount: events)
        }
        // The tests run in an English app: only the date used to be French.
        #expect(Bundle.main.preferredLocalizations.first == "en")
        #expect(label("fr_FR", isToday: true, events: 2) == "lundi 15 janvier 2024, aujourd’hui, 2 événements")
        #expect(label("fr_CA", events: 1).hasSuffix(", 1 événement"), "a region uses its language's strings")
        #expect(label("de_DE", isToday: true, events: 1) == "Montag, 15. Januar 2024, heute, 1 Ereignis")
        #expect(label("el_GR", isToday: true, events: 3).hasSuffix(", σήμερα, 3 γεγονότα"))
        #expect(label("ja_JP", isToday: true, events: 3).hasSuffix(", 今日, 3件のイベント"))
        #expect(label("zh_CN", isToday: true, events: 3).hasSuffix(", 今天, 3 个日程"))
        #expect(label("zh_TW", isToday: true, events: 3).hasSuffix(", 今天, 3 個活動"), "Traditional, by the script")
        #expect(label("en_GB", isToday: true, events: 1).hasSuffix(" 2024, Today, 1 event"))

        // The plural form follows the rules of the language, not those of the app's.
        #expect(label("ru_RU", events: 1).hasSuffix(", 1 событие"))
        #expect(label("ru_RU", events: 3).hasSuffix(", 3 события"))
        #expect(label("ru_RU", events: 5).hasSuffix(", 5 событий"))
        #expect(label("ru_RU", events: 21).hasSuffix(", 21 событие"))
        #expect(label("pl_PL", events: 22).hasSuffix(", 22 wydarzenia"))
        #expect(label("pl_PL", events: 25).hasSuffix(", 25 wydarzeń"))

        // A language the library has no strings in: the date in the locale, the words in the app's.
        #expect(Bundle.kdCalendarStrings(for: Locale(identifier: "he_IL")) == nil)
        #expect(label("he_IL", isToday: true, events: 2).hasSuffix(", Today, 2 events"))
        // The count then takes its plural form by the rules of the language the words are in,
        // which is the app's and not always the device's.
        let hebrew = CalendarView.Formatters(calendar: utc, locale: Locale(identifier: "he_IL"))
        #expect(hebrew.stringsBundle === Bundle.kdCalendar)
        #expect(hebrew.stringsLocale == Bundle.kdCalendarLocale)
        #expect(Bundle.kdCalendarLocale.identifier == "en")
        #expect(label("he_IL", events: 21).hasSuffix(", 21 events"))

        // A cell carries the label.
        let french = makeCalendar(
            start: date(2024, 1, 1), end: date(2024, 1, 31), locale: Locale(identifier: "fr_FR"))
        french.events = [CalendarEvent(title: "a", startDate: monday, endDate: monday.addingTimeInterval(3600))]
        french.layoutIfNeeded()
        #expect(
            cell(french, IndexPath(item: 14, section: 0))?.accessibilityLabel == "lundi 15 janvier 2024, 1 événement")
    }

    @Test func everyLocalisationHasBothVoiceOverStrings() {
        let languages = Bundle.kdCalendar.localizations
        let promised = ["de", "el", "en", "es", "fr", "it", "ja", "nl", "pt", "zh-Hans"]
        #expect(Set(languages).isSuperset(of: promised))

        for language in languages where language != "en" {
            let formatters = CalendarView.Formatters(calendar: utc, locale: Locale(identifier: language))
            #expect(formatters.stringsBundle !== Bundle.kdCalendar, "\(language) has its own strings")
            #expect(formatters.stringsBundle.bundleURL.lastPathComponent == "\(language).lproj")
            let today = String(localized: "Today", bundle: formatters.stringsBundle, locale: formatters.stringsLocale)
            #expect(today != "Today" && !today.isEmpty, "\(language) translates Today")
            // Counts in every plural category a language may have.
            for count in [1, 2, 3, 5, 11, 21, 22, 25, 100] {
                let events = String(
                    localized: "\(count) events", bundle: formatters.stringsBundle, locale: formatters.stringsLocale)
                #expect(events.contains("\(count)"), "\(language) shows the count in \(events)")
                #expect(!events.contains("%") && !events.hasSuffix("events"), "\(language) translates \(events)")
            }
        }
    }

    @Test func aLocaleFindsTheStringsOfItsLanguageAndScript() {
        func strings(_ locale: String) -> String? {
            Bundle.kdCalendarStrings(for: Locale(identifier: locale))?.bundleURL.lastPathComponent
        }
        #expect(strings("fr_FR") == "fr.lproj")
        #expect(strings("pt_PT") == "pt.lproj")
        #expect(strings("pt_BR") == "pt.lproj")
        #expect(strings("nb_NO") == "nb.lproj")
        #expect(strings("zh_CN") == "zh-Hans.lproj")
        #expect(strings("zh_SG") == "zh-Hans.lproj")
        #expect(strings("zh_TW") == "zh-Hant.lproj")
        #expect(strings("zh_HK") == "zh-Hant.lproj")
        #expect(strings("en_AU") == "en.lproj")
        #expect(strings("he_IL") == nil)
        #expect(strings("sr_Latn_RS") == nil)
    }

    // MARK: VoiceOver

    @Test func daysTheDelegateRefusesAreNotEnabledForVoiceOver() {
        let view = makeCalendar(start: date(2024, 1, 1), end: date(2024, 1, 31))
        var asked: [Date: Int] = [:]
        delegate(of: view).canSelect = { [utc] day in
            asked[day, default: 0] += 1
            return utc.component(.day, from: day) != 13
        }
        view.reloadData()
        view.layoutIfNeeded()

        // January 2024 starts on a Monday, so day n is item n - 1.
        let refused = cell(view, IndexPath(item: 12, section: 0))
        #expect(refused?.configuration.isSelectable == false)
        #expect(refused?.configuration.isOutOfRange == false)
        #expect(refused?.accessibilityTraits.contains(.button) == true)
        #expect(refused?.accessibilityTraits.contains(.notEnabled) == true, "a dimmed button, like a day out of range")
        let allowed = cell(view, IndexPath(item: 11, section: 0))
        #expect(allowed?.accessibilityTraits.contains(.notEnabled) == false)

        #expect(asked.count == 31, "every day in range")
        #expect(asked.values.allSatisfy { $0 == 1 }, "the delegate is asked once for a cell")
    }

    @Test func daysOutOfRangeDoNotAskTheDelegate() {
        let view = makeCalendar(start: date(2024, 1, 10), end: date(2024, 1, 20))
        var asked: [Date] = []
        delegate(of: view).canSelect = { day in
            asked.append(day)
            return true
        }
        view.reloadData()
        view.layoutIfNeeded()
        #expect(Set(asked) == Set((10...20).map { date(2024, 1, $0) }))
        #expect(cell(view, IndexPath(item: 2, section: 0))?.accessibilityTraits.contains(.notEnabled) == true)
    }

    @Test func aSelectionChangeAsksAgainWhichDaysOnScreenMayBeSelected() {
        // A delegate that allows two days refuses every other day once two are selected, and
        // allows them again when one is deselected. It counts in its own callbacks, so the view
        // has to ask after it has told the delegate.
        let view = makeCalendar(start: date(2024, 1, 1), end: date(2024, 1, 31))
        let recorder = delegate(of: view)
        recorder.canSelect = { [unowned recorder] _ in recorder.selected.count - recorder.deselected.count < 2 }
        view.reloadData()
        view.layoutIfNeeded()
        // January 2024 starts on a Monday, so day n is item n - 1. The view asks at its next
        // layout, which comes before VoiceOver reads the cell.
        func isDimmed(_ day: Int) -> Bool? {
            view.layoutIfNeeded()
            return cell(view, IndexPath(item: day - 1, section: 0))?.accessibilityTraits.contains(.notEnabled)
        }
        #expect(isDimmed(20) == false)

        view.selectDate(date(2024, 1, 5))
        #expect(isDimmed(20) == false)
        view.collectionView(view.collectionView, didSelectItemAt: IndexPath(item: 5, section: 0))
        #expect(view.selectedDates == [date(2024, 1, 5), date(2024, 1, 6)])
        #expect(isDimmed(20) == true, "a third day would be refused")
        #expect(isDimmed(5) == false, "a selected day can still be deselected")
        #expect(isDimmed(6) == false)

        view.deselectDate(date(2024, 1, 5))
        #expect(isDimmed(20) == false, "there is room for a day again")
        #expect(isDimmed(5) == false)

        // The same goes for a selection that is assigned or cleared without telling the delegate.
        recorder.canSelect = { [unowned view] _ in view.selectedDates.count < 2 }
        view.setSelection([date(2024, 1, 7), date(2024, 1, 8)])
        #expect(view.selectedDates == [date(2024, 1, 7), date(2024, 1, 8)])
        #expect(isDimmed(20) == true)
        view.clearAllSelectedDates()
        #expect(isDimmed(20) == false)
    }

    @Test func aRefreshOfSelectabilityAsksOnlyTheDaysOnScreenThatAreInRange() {
        let view = makeCalendar(start: date(2024, 1, 10), end: date(2024, 3, 20))
        // A selected day, so that the reload has a selection to show again.
        view.selectDate(date(2024, 1, 15))
        var asked: [Date] = []
        delegate(of: view).canSelect = { day in
            asked.append(day)
            return true
        }
        view.reloadData()
        #expect(asked.isEmpty, "a reload leaves the asking to the layout that follows")
        view.layoutIfNeeded()
        let january = Set((10...31).map { date(2024, 1, $0) })
        #expect(Set(asked) == january)
        #expect(asked.count == january.count, "once for each cell")

        asked = []
        view.refreshSelectability()
        #expect(Set(asked) == january, "not the days out of range, nor the months off screen")
        #expect(asked.count == january.count)

        // A selection change has the next layout ask, once however many changes there were, and
        // adds nothing to what the selection asks for itself.
        asked = []
        view.selectDate(date(2024, 1, 20))
        view.deselectDate(date(2024, 1, 15))
        #expect(asked == [date(2024, 1, 20)])
        view.layoutIfNeeded()
        #expect(asked.count == 1 + january.count)
        asked = []
        view.setNeedsLayout()
        view.layoutIfNeeded()
        #expect(asked.isEmpty, "a layout with no selection change before it asks nothing")
    }

    @Test func aSelectedDayStaysEnabledWhenItCanNoLongerBeSelected() {
        // Activating a selected day deselects it, which the delegate's answer does not prevent.
        let refused = DayCellConfiguration(isSelectable: false)
        #expect(refused.appearance(isSelected: false).accessibilityTraits == [.button, .notEnabled])
        #expect(refused.appearance(isSelected: true).accessibilityTraits == [.button, .selected])
        #expect(DayCellConfiguration().appearance(isSelected: false).accessibilityTraits == .button)
    }

    @Test func weekdayLabelsAreColumnHeadingsWithFullNamesForVoiceOver() {
        let view = makeCalendar(start: date(2024, 1, 1), end: date(2024, 1, 31))
        #expect(view.headerView.dayLabels.map(\.text) == ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"])
        #expect(
            view.headerView.dayLabels.map(\.accessibilityLabel) == [
                "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday",
            ])

        // German abbreviates a weekday inside a date as "Mo." and heads a column with "Mo".
        let german = makeCalendar(
            start: date(2024, 1, 1), end: date(2024, 1, 31), firstWeekday: .sunday, locale: Locale(identifier: "de_DE"))
        #expect(german.headerView.dayLabels.map(\.text) == ["So", "Mo", "Di", "Mi", "Do", "Fr", "Sa"])
        #expect(
            german.headerView.dayLabels.map(\.accessibilityLabel) == [
                "Sonntag", "Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag",
            ])
        german.style.firstWeekday = .monday
        #expect(german.headerView.dayLabels.first?.accessibilityLabel == "Montag", "the names follow the first weekday")
    }

    // MARK: Style equality

    @Test func stylesWithSeparateDynamicColoursAreNotEqual() {
        // As the documentation of Style says: UIColor compares a colour made from a closure by
        // identity, so a style has to share the colour to compare equal.
        func dynamicColour() -> UIColor {
            UIColor { traits in traits.userInterfaceStyle == .dark ? .white : .black }
        }
        var first = CalendarView.Style()
        var second = CalendarView.Style()
        first.cellColorDefault = dynamicColour()
        second.cellColorDefault = dynamicColour()
        #expect(first != second)

        let shared = dynamicColour()
        first.cellColorDefault = shared
        second.cellColorDefault = shared
        #expect(first == second)

        first.cellColorDefault = .label
        second.cellColorDefault = .label
        #expect(first == second, "system colours compare by value")
        first.cellColorDefault = UIColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1)
        second.cellColorDefault = UIColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1)
        #expect(first == second, "and so do fixed components")
    }

    // MARK: SwiftUI

    /// Holds a selection for a `Binding`, standing in for `@State`.
    ///
    /// Unchecked: nothing synchronises it. Only this suite's tests and the views they host touch
    /// it, and the suite is main-actor isolated and serialized.
    final class SelectionBox: @unchecked Sendable {
        var dates: [Date] = []
        var changes = 0
        var binding: Binding<[Date]> {
            Binding(
                get: { self.dates },
                set: {
                    self.dates = $0; self.changes += 1
                })
        }
    }

    private func findCalendarView(in view: UIView) -> CalendarView? {
        if let calendar = view as? CalendarView { return calendar }
        for subview in view.subviews {
            if let found = findCalendarView(in: subview) { return found }
        }
        return nil
    }

    @Test func swiftUIWrapperHostsACalendarAndReportsSelection() {
        let box = SelectionBox()
        let style = makeStyle()
        let range = date(2024, 1, 1)...date(2024, 3, 31)
        let host = UIHostingController(
            rootView: KDCalendarView(range: range, selection: box.binding)
                .calendarStyle(style)
                .allowsMultipleSelection(false)
                .events([CalendarEvent(title: "a", startDate: date(2024, 1, 5), endDate: date(2024, 1, 6))]))
        Self.window.rootViewController = host
        host.view.frame = Self.window.bounds
        host.view.layoutIfNeeded()

        let calendar = findCalendarView(in: host.view)
        #expect(calendar != nil)
        guard let calendar else { return }
        #expect(calendar.dateRange == range)
        #expect(calendar.multipleSelectionEnable == false)
        #expect(calendar.style == style)
        #expect(calendar.events.count == 1)
        #expect(calendar.headerView.monthLabel.text == "January 2024")

        // A selection in the view flows into the binding.
        calendar.selectDate(date(2024, 1, 10))
        #expect(box.dates == [date(2024, 1, 10)])
        #expect(box.changes == 1)

        // A new value from SwiftUI flows into the view.
        box.dates = [date(2024, 2, 14)]
        host.rootView = KDCalendarView(range: range, selection: box.binding).calendarStyle(style)
            .allowsMultipleSelection(false)
        host.view.layoutIfNeeded()
        #expect(calendar.selectedDates == [date(2024, 2, 14)])
        #expect(box.dates == [date(2024, 2, 14)], "the sync does not echo back into the binding")
    }

    @Test func swiftUIRangeChangeKeepsTheSelectedDayHighlighted() {
        let box = SelectionBox()
        let style = makeStyle()
        let host = UIHostingController(
            rootView: KDCalendarView(range: date(2024, 3, 1)...date(2024, 4, 30), selection: box.binding)
                .calendarStyle(style))
        Self.window.rootViewController = host
        host.view.frame = Self.window.bounds
        host.view.layoutIfNeeded()
        guard let calendar = findCalendarView(in: host.view) else {
            Issue.record("no calendar view hosted")
            return
        }
        calendar.selectDate(date(2024, 3, 15))

        // An earlier start adds February in front of March.
        host.rootView = KDCalendarView(range: date(2024, 2, 10)...date(2024, 4, 30), selection: box.binding)
            .calendarStyle(style)
        host.view.layoutIfNeeded()
        let indexPath = calendar.indexPathForDate(date(2024, 3, 15))!
        #expect(indexPath.section == 1)
        #expect(calendar.selectedDates == [date(2024, 3, 15)])
        #expect(calendar.collectionView.indexPathsForSelectedItems == [indexPath])
        #expect(box.dates == [date(2024, 3, 15)])
    }

    @Test func swiftUIRangeChangeDropsTheLeftDaysFromTheBinding() async {
        let box = SelectionBox()
        let style = makeStyle()
        var range = date(2024, 3, 1)...date(2024, 4, 30)
        var mode = CalendarView.SelectionMode.multiple
        func view() -> KDCalendarView {
            KDCalendarView(range: range, selection: box.binding).calendarStyle(style).selectionMode(mode)
        }
        guard let hosted = hostCalendar(view()) else { return }
        let (host, calendar) = hosted

        // A range that now ends in March leaves 20 April out of both the view and the binding.
        calendar.selectDate(date(2024, 3, 15))
        calendar.selectDate(date(2024, 4, 20))
        #expect(box.dates == [date(2024, 3, 15), date(2024, 4, 20)])
        range = date(2024, 3, 1)...date(2024, 3, 31)
        host.rootView = view()
        host.view.layoutIfNeeded()
        await settle()
        #expect(calendar.selectedDates == [date(2024, 3, 15)])
        #expect(box.dates == [date(2024, 3, 15)])

        // A picked range is cut at the new end.
        range = date(2024, 3, 1)...date(2024, 4, 30)
        mode = .range
        box.dates = []
        host.rootView = view()
        host.view.layoutIfNeeded()
        calendar.selectDate(date(2024, 3, 28))
        calendar.selectDate(date(2024, 4, 2))
        #expect(box.dates.count == 6)
        range = date(2024, 3, 1)...date(2024, 3, 30)
        host.rootView = view()
        host.view.layoutIfNeeded()
        await settle()
        let kept = (28...30).map { date(2024, 3, $0) }
        #expect(calendar.selectedDates == kept)
        #expect(box.dates == kept)
    }

    @Test func swiftUIModifiersReachTheCalendar() async {
        let box = SelectionBox()
        let style = makeStyle()
        var holiday = style
        holiday.cellColorDefault = .systemPink
        let scrolled = SelectionBox()
        let pressed = SelectionBox()
        let range = date(2024, 1, 1)...date(2024, 3, 31)
        let events = [CalendarEvent(title: "a", startDate: date(2024, 2, 5), endDate: date(2024, 2, 6))]

        let host = UIHostingController(
            rootView: KDCalendarView(range: range, selection: box.binding)
                .calendarStyle(style)
                .direction(.vertical)
                .selectionMode(.range)
                .allowsDeselection(false)
                .marksWeekends(false)
                .scrollEnabled(false)
                .events(events)
                .displayDate(date(2024, 2, 14))
                .canSelect { [utc] in utc.component(.day, from: $0) != 13 }
                .styleForDate { [utc] in utc.component(.day, from: $0) == 14 ? holiday : nil }
                .onScrollToMonth { scrolled.dates.append($0) }
                .onLongPress { date, _ in pressed.dates.append(date) })
        Self.window.rootViewController = host
        host.view.frame = Self.window.bounds
        host.view.layoutIfNeeded()

        guard let calendar = findCalendarView(in: host.view) else {
            Issue.record("no calendar view hosted")
            return
        }
        #expect(calendar.direction == .vertical)
        #expect(calendar.selectionMode == .range)
        #expect(calendar.enableDeselection == false)
        #expect(calendar.marksWeekends == false)
        #expect(calendar.isScrollEnabled == false)
        #expect(calendar.events.count == 1)
        #expect(calendar.displayDate == date(2024, 2, 1))
        await settle()
        #expect(scrolled.dates == [date(2024, 2, 1)], "the display date applies before the first month is announced")
        #expect(calendar.shouldSelect(calendar.indexPathForDate(date(2024, 2, 13))!) == false)
        #expect(calendar.shouldSelect(calendar.indexPathForDate(date(2024, 2, 12))!) == true)
        calendar.layoutIfNeeded()
        let fourteenth =
            calendar.collectionView.cellForItem(at: calendar.indexPathForDate(date(2024, 2, 14))!) as? CalendarDayCell
        #expect(fourteenth?.dayBackgroundView.backgroundColor == .systemPink)
        calendar.delegate?.calendar(calendar, didLongPressDate: date(2024, 2, 20), withEvents: nil)
        #expect(pressed.dates == [date(2024, 2, 20)])

        // A range picked in the view reaches the binding as every day in it.
        calendar.selectDate(date(2024, 2, 5))
        calendar.selectDate(date(2024, 2, 7))
        #expect(box.dates == [date(2024, 2, 5), date(2024, 2, 6), date(2024, 2, 7)])

        // New range and events from SwiftUI reach the view.
        host.rootView = KDCalendarView(range: date(2024, 1, 1)...date(2024, 6, 30), selection: box.binding)
            .calendarStyle(style)
            .events(events + [CalendarEvent(title: "b", startDate: date(2024, 3, 1), endDate: date(2024, 3, 2))])
        host.view.layoutIfNeeded()
        #expect(calendar.numberOfSections(in: calendar.collectionView) == 6)
        #expect(calendar.events.count == 2)
        #expect(calendar.direction == .horizontal, "modifiers not repeated fall back to their defaults")
    }

    @Test func swiftUIDisplayDateChangeReportsTheMonthAfterTheViewUpdate() async {
        let box = SelectionBox()
        let scrolled = SelectionBox()
        let style = makeStyle()
        var displayDate = date(2024, 1, 10)
        func view() -> KDCalendarView {
            KDCalendarView(range: date(2024, 1, 1)...date(2024, 6, 30), selection: box.binding)
                .calendarStyle(style)
                .displayDate(displayDate)
                .onScrollToMonth { scrolled.dates.append($0) }
        }
        guard let hosted = hostCalendar(view()) else { return }
        let (host, calendar) = hosted
        await settle()
        scrolled.dates = []

        // The month is applied during the update, but announced only once the update has ended,
        // so the action may change state.
        displayDate = date(2024, 4, 20)
        host.rootView = view()
        host.view.layoutIfNeeded()
        #expect(calendar.displayDate == date(2024, 4, 1))
        #expect(scrolled.dates == [])
        await settle()
        #expect(scrolled.dates == [date(2024, 4, 1)])

        // A scroll outside a view update is still announced right away.
        calendar.setDisplayDate(date(2024, 5, 3))
        #expect(scrolled.dates == [date(2024, 4, 1), date(2024, 5, 1)])
    }

    /// Hosts `view` in the window and returns the host with the calendar inside it.
    private func hostCalendar<Content: View>(_ view: Content) -> (UIHostingController<Content>, CalendarView)? {
        let host = UIHostingController(rootView: view)
        Self.window.rootViewController = host
        host.view.frame = Self.window.bounds
        host.view.layoutIfNeeded()
        guard let calendar = findCalendarView(in: host.view) else {
            Issue.record("no calendar view hosted")
            return nil
        }
        return (host, calendar)
    }

    /// Lets work queued on the main actor run, such as the wrapper correcting its binding.
    private func settle() async {
        for _ in 0..<5 { await Task.yield() }
    }

    @Test func swiftUIRangeSetFromTheBindingSelectsEveryDayInIt() async {
        let box = SelectionBox()
        let style = makeStyle()
        let range = date(2024, 1, 1)...date(2024, 3, 31)
        func view() -> KDCalendarView {
            KDCalendarView(range: range, selection: box.binding).calendarStyle(style).selectionMode(.range)
        }
        guard let hosted = hostCalendar(view()) else { return }
        let (host, calendar) = hosted

        // A whole week, as the demo's "Select this week" sets it.
        let week = (8...14).map { date(2024, 1, $0) }
        box.dates = week
        host.rootView = view()
        host.view.layoutIfNeeded()
        await settle()
        #expect(calendar.selectedDates == week)
        #expect(box.dates == week)
        #expect(box.changes == 0, "a value the view shows as given is left alone")

        // The ends of a range fill in, and the binding learns the days between them.
        box.dates = [date(2024, 2, 9), date(2024, 2, 5)]
        host.rootView = view()
        host.view.layoutIfNeeded()
        await settle()
        let filled = (5...9).map { date(2024, 2, $0) }
        #expect(calendar.selectedDates == filled)
        #expect(box.dates == filled)
        #expect(box.changes == 1)

        // The range is complete: the next tap starts a new one and the one after completes it.
        calendar.selectDate(date(2024, 2, 20))
        #expect(box.dates == [date(2024, 2, 20)])
        calendar.selectDate(date(2024, 2, 22))
        #expect(box.dates == (20...22).map { date(2024, 2, $0) })
    }

    @Test func swiftUIBindingIsCorrectedToWhatTheViewShows() async {
        let box = SelectionBox()
        let style = makeStyle()
        let range = date(2024, 1, 1)...date(2024, 3, 31)
        var mode = CalendarView.SelectionMode.single
        func view() -> KDCalendarView {
            KDCalendarView(range: range, selection: box.binding)
                .calendarStyle(style)
                .selectionMode(mode)
                .canSelect { [utc] in utc.component(.day, from: $0) != 13 }
        }
        guard let hosted = hostCalendar(view()) else { return }
        let (host, calendar) = hosted

        // Single mode keeps the last day, not each one in turn.
        box.dates = [date(2024, 1, 8), date(2024, 1, 10), date(2024, 1, 12)]
        host.rootView = view()
        host.view.layoutIfNeeded()
        await settle()
        #expect(calendar.selectedDates == [date(2024, 1, 12)])
        #expect(box.dates == [date(2024, 1, 12)])

        // A correction gives way to a newer value.
        box.dates = [date(2024, 1, 8), date(2024, 1, 10)]
        host.rootView = view()
        host.view.layoutIfNeeded()
        box.dates = [date(2024, 1, 20)]
        await settle()
        #expect(box.dates == [date(2024, 1, 20)])

        // Refused days are dropped; a time of day alone is not worth a correction.
        mode = .multiple
        let changes = box.changes
        let morning = utc.date(byAdding: .hour, value: 9, to: date(2024, 1, 5))!
        box.dates = [morning]
        host.rootView = view()
        host.view.layoutIfNeeded()
        await settle()
        #expect(calendar.selectedDates == [date(2024, 1, 5)])
        #expect(box.changes == changes)
        box.dates = [morning, date(2024, 1, 13)]
        host.rootView = view()
        host.view.layoutIfNeeded()
        await settle()
        #expect(calendar.selectedDates == [date(2024, 1, 5)])
        #expect(box.dates == [date(2024, 1, 5)])
    }

    @Test func swiftUIModeChangeLeavesTheBindingWithTheDaysKept() async {
        let box = SelectionBox()
        let style = makeStyle()
        let range = date(2024, 1, 1)...date(2024, 3, 31)
        var mode = CalendarView.SelectionMode.multiple
        func view() -> KDCalendarView {
            KDCalendarView(range: range, selection: box.binding).calendarStyle(style).selectionMode(mode)
        }
        guard let hosted = hostCalendar(view()) else { return }
        let (host, calendar) = hosted

        // As in the demo: three days in multiple mode, then the picker switches to single.
        for day in [8, 10, 12] { calendar.selectDate(date(2024, 1, day)) }
        #expect(box.dates == [date(2024, 1, 8), date(2024, 1, 10), date(2024, 1, 12)])
        mode = .single
        host.rootView = view()
        host.view.layoutIfNeeded()
        await settle()
        #expect(calendar.selectedDates == [date(2024, 1, 12)])
        #expect(box.dates == [date(2024, 1, 12)])

        // Range mode starts clean rather than filling the days in between.
        mode = .multiple
        host.rootView = view()
        host.view.layoutIfNeeded()
        for day in [8, 10] { calendar.selectDate(date(2024, 1, day)) }
        #expect(box.dates == [date(2024, 1, 12), date(2024, 1, 8), date(2024, 1, 10)])
        mode = .range
        host.rootView = view()
        host.view.layoutIfNeeded()
        await settle()
        #expect(calendar.selectedDates == [])
        #expect(box.dates == [])

        // A selection that comes with the new mode is applied in its shape.
        mode = .multiple
        box.dates = [date(2024, 2, 9), date(2024, 2, 5)]
        host.rootView = view()
        host.view.layoutIfNeeded()
        await settle()
        #expect(calendar.selectedDates == [date(2024, 2, 9), date(2024, 2, 5)])
        mode = .range
        box.dates = [date(2024, 2, 20), date(2024, 2, 22)]
        host.rootView = view()
        host.view.layoutIfNeeded()
        await settle()
        #expect(calendar.selectedDates == (20...22).map { date(2024, 2, $0) })
        #expect(box.dates == (20...22).map { date(2024, 2, $0) })
    }

    // MARK: SwiftUI display date

    /// Settles the calendar on the page of `section`, as a swipe that came to rest there does.
    private func swipe(_ calendar: CalendarView, toSection section: Int) {
        calendar.scrollViewWillBeginDragging(calendar.collectionView)
        calendar.collectionView.contentOffset = calendar.flowLayout.contentOffset(forSection: section)
        calendar.scrollViewDidEndDecelerating(calendar.collectionView)
    }

    @Test func swiftUIDisplayDateInTheSameMonthDoesNotScrollBack() async {
        // `.displayDate(Date())` hands the wrapper a new instant on every body run.
        let box = SelectionBox()
        let style = makeStyle()
        var displayDate: Date? = date(2024, 2, 10)
        func view() -> KDCalendarView {
            KDCalendarView(range: date(2024, 1, 1)...date(2024, 6, 30), selection: box.binding)
                .calendarStyle(style)
                .displayDate(displayDate)
        }
        guard let hosted = hostCalendar(view()) else { return }
        let (host, calendar) = hosted
        #expect(calendar.displayDate == date(2024, 2, 1))

        swipe(calendar, toSection: 3)
        #expect(calendar.displayDate == date(2024, 4, 1))
        displayDate = date(2024, 2, 10, hour: 1)
        host.rootView = view()
        host.view.layoutIfNeeded()
        await settle()
        #expect(calendar.displayDate == date(2024, 4, 1), "a later moment of the same month is not a new request")
        #expect(calendar.collectionView.contentOffset == calendar.flowLayout.contentOffset(forSection: 3))

        // Another month is one, and so is the first month again after that.
        displayDate = date(2024, 5, 3)
        host.rootView = view()
        host.view.layoutIfNeeded()
        #expect(calendar.displayDate == date(2024, 5, 1))
        displayDate = date(2024, 2, 28)
        host.rootView = view()
        host.view.layoutIfNeeded()
        #expect(calendar.displayDate == date(2024, 2, 1))

        // No date asks for nothing, and the date that follows it is a request again.
        swipe(calendar, toSection: 3)
        displayDate = nil
        host.rootView = view()
        host.view.layoutIfNeeded()
        #expect(calendar.displayDate == date(2024, 4, 1))
        displayDate = date(2024, 2, 28)
        host.rootView = view()
        host.view.layoutIfNeeded()
        #expect(calendar.displayDate == date(2024, 2, 1))
    }

    /// The demo's shape with real `@State`: the scroll callback changes state, the body runs again
    /// and hands the calendar the next moment `now` returns as its display date.
    struct ScrollCallbackCalendar: View {
        let range: ClosedRange<Date>
        let style: CalendarView.Style
        let now: () -> Date
        let bodyRuns: SelectionBox
        @State private var selection: [Date] = []
        @State private var month = Date.distantPast

        var body: some View {
            let _ = bodyRuns.changes += 1
            VStack {
                Text(month, format: .dateTime.month().year())
                KDCalendarView(range: range, selection: $selection)
                    .calendarStyle(style)
                    .displayDate(now())
                    .onScrollToMonth { month = $0 }
            }
        }
    }

    /// Waits until `condition` holds, for as long as SwiftUI may take to run a body again.
    private func wait(until condition: () -> Bool) async {
        for _ in 0..<200 where !condition() {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test func swiftUIDisplayDateOfNowStaysOnTheMonthTheUserSwipedTo() async {
        let bodyRuns = SelectionBox()
        var now = date(2024, 2, 10)
        let view = ScrollCallbackCalendar(
            range: date(2024, 1, 1)...date(2024, 6, 30), style: makeStyle(),
            now: {
                now += 1
                return now
            }, bodyRuns: bodyRuns)
        guard let hosted = hostCalendar(view) else { return }
        let (host, calendar) = hosted
        await wait { calendar.displayDate == date(2024, 2, 1) && bodyRuns.changes > 1 }
        #expect(calendar.displayDate == date(2024, 2, 1))

        // Two months ahead: the callback changes state and the body runs again.
        let runs = bodyRuns.changes
        swipe(calendar, toSection: 3)
        await wait { bodyRuns.changes > runs }
        #expect(bodyRuns.changes > runs)
        host.view.layoutIfNeeded()
        await settle()
        #expect(calendar.displayDate == date(2024, 4, 1))
        #expect(calendar.collectionView.contentOffset == calendar.flowLayout.contentOffset(forSection: 3))
    }

    // MARK: SwiftUI displayed month

    /// Holds a month for a `Binding`, standing in for `@State`.
    ///
    /// Unchecked for the same reason as ``SelectionBox``: main actor only, by the suite's isolation.
    final class MonthBox: @unchecked Sendable {
        var month: Date
        var changes = 0
        init(_ month: Date) { self.month = month }
        var binding: Binding<Date> {
            Binding(
                get: { self.month },
                set: {
                    self.month = $0; self.changes += 1
                })
        }
    }

    @Test func swiftUIDisplayedMonthFollowsSwipesAndScrollsWhenAssigned() async {
        let box = SelectionBox()
        let month = MonthBox(date(2024, 2, 10))
        let scrolled = SelectionBox()
        let style = makeStyle()
        func view() -> KDCalendarView {
            KDCalendarView(range: date(2024, 1, 1)...date(2024, 6, 30), selection: box.binding)
                .calendarStyle(style)
                .displayDate(date(2024, 5, 20))
                .displayedMonth(month.binding)
                .onScrollToMonth { scrolled.dates.append($0) }
        }
        guard let hosted = hostCalendar(view()) else { return }
        let (host, calendar) = hosted
        await settle()
        #expect(calendar.displayDate == date(2024, 2, 1), "the binding decides, not displayDate(_:)")
        #expect(month.month == date(2024, 2, 10))
        #expect(month.changes == 0, "a day of the month on screen is left as it is")

        // A swipe sets the binding to the month the calendar settles on, and the body that runs
        // next leaves the calendar there.
        swipe(calendar, toSection: 3)
        #expect(month.month == date(2024, 4, 1))
        #expect(month.changes == 1)
        host.rootView = view()
        host.view.layoutIfNeeded()
        await settle()
        #expect(calendar.displayDate == date(2024, 4, 1))

        // The value from before the swipe scrolls back, which displayDate(_:) cannot do: to it
        // the value never changed.
        month.month = date(2024, 2, 10)
        host.rootView = view()
        host.view.layoutIfNeeded()
        #expect(calendar.displayDate == date(2024, 2, 1))
        #expect(calendar.collectionView.contentOffset == calendar.flowLayout.contentOffset(forSection: 1))
        await settle()
        #expect(month.month == date(2024, 2, 10))
        #expect(month.changes == 1, "applying the binding does not echo back into it")
        #expect(scrolled.dates == [date(2024, 2, 1), date(2024, 4, 1), date(2024, 2, 1)])
    }

    @Test func swiftUIDisplayedMonthOutOfRangeIsSetBackAfterTheViewUpdate() async {
        let box = SelectionBox()
        let month = MonthBox(date(2024, 2, 10))
        let style = makeStyle()
        func view() -> KDCalendarView {
            KDCalendarView(range: date(2024, 1, 1)...date(2024, 6, 30), selection: box.binding)
                .calendarStyle(style)
                .displayedMonth(month.binding)
        }
        guard let hosted = hostCalendar(view()) else { return }
        let (host, calendar) = hosted

        // The view cannot show 2030, so the binding returns to the month on screen, once the
        // update has ended: state must not change during it.
        month.month = date(2030, 1, 1)
        host.rootView = view()
        host.view.layoutIfNeeded()
        #expect(month.month == date(2030, 1, 1))
        await settle()
        #expect(month.month == date(2024, 2, 1))
        #expect(calendar.displayDate == date(2024, 2, 1))

        // A correction gives way to a newer value.
        month.month = date(2030, 1, 1)
        host.rootView = view()
        host.view.layoutIfNeeded()
        month.month = date(2024, 5, 5)
        await settle()
        #expect(month.month == date(2024, 5, 5))
        host.rootView = view()
        host.view.layoutIfNeeded()
        #expect(calendar.displayDate == date(2024, 5, 1))
    }

    @Test func swiftUIDisplayedMonthBeforeTheRangeIsSetToTheFirstMonthShown() async {
        // No month is on screen during the first update, so the first layout sets the binding.
        let box = SelectionBox()
        let month = MonthBox(date(2020, 7, 4))
        let view = KDCalendarView(range: date(2024, 1, 1)...date(2024, 6, 30), selection: box.binding)
            .calendarStyle(makeStyle())
            .displayedMonth(month.binding)
        guard let hosted = hostCalendar(view) else { return }
        await settle()
        #expect(hosted.1.displayDate == date(2024, 1, 1))
        #expect(month.month == date(2024, 1, 1))
    }

    /// A calendar whose month lives in real SwiftUI state that the test can assign.
    @MainActor @Observable final class MonthModel {
        var month: Date
        @ObservationIgnored var bodyRuns = 0
        init(month: Date) { self.month = month }
    }

    struct BoundMonthCalendar: View {
        let range: ClosedRange<Date>
        let style: CalendarView.Style
        @Bindable var model: MonthModel
        @State private var selection: [Date] = []

        var body: some View {
            let _ = model.bodyRuns += 1
            VStack {
                Text(model.month, format: .dateTime.month().year())
                KDCalendarView(range: range, selection: $selection)
                    .calendarStyle(style)
                    .displayedMonth($model.month)
            }
        }
    }

    @Test func swiftUIDisplayedMonthInRealStateKeepsTheSwipedMonthAndRepeats() async {
        let model = MonthModel(month: date(2024, 2, 10))
        let view = BoundMonthCalendar(range: date(2024, 1, 1)...date(2024, 6, 30), style: makeStyle(), model: model)
        guard let hosted = hostCalendar(view) else { return }
        let (host, calendar) = hosted
        await wait { calendar.displayDate == date(2024, 2, 1) }
        #expect(calendar.displayDate == date(2024, 2, 1))

        // The swipe changes state, the body runs again and the calendar stays where it is.
        let runs = model.bodyRuns
        swipe(calendar, toSection: 3)
        #expect(model.month == date(2024, 4, 1))
        await wait { model.bodyRuns > runs }
        #expect(model.bodyRuns > runs)
        host.view.layoutIfNeeded()
        await settle()
        #expect(calendar.displayDate == date(2024, 4, 1))
        #expect(model.month == date(2024, 4, 1))

        // The same value as at the start brings February back.
        model.month = date(2024, 2, 10)
        await wait { calendar.displayDate == date(2024, 2, 1) }
        #expect(calendar.displayDate == date(2024, 2, 1))
        #expect(model.month == date(2024, 2, 10))
        #expect(calendar.animationTargetMonth == nil)

        // Assigned with an animation, the month scrolls into place.
        withAnimation { model.month = date(2024, 5, 20) }
        await wait { calendar.displayDate == date(2024, 5, 1) }
        #expect(calendar.displayDate == date(2024, 5, 1))
        #expect(calendar.animationTargetMonth == date(2024, 5, 1), "an animated scroll is under way")
        #expect(model.month == date(2024, 5, 20))
    }

    @Test func swiftUIDisplayedMonthFollowsAScrollThatReturnsToTheMonthItLeft() async {
        // An animated scroll that the user catches and drags back comes to rest on the month the
        // delegate last heard of, so no didScrollToMonth says that the calendar is there again.
        let model = MonthModel(month: date(2024, 2, 10))
        let view = BoundMonthCalendar(range: date(2024, 1, 1)...date(2024, 6, 30), style: makeStyle(), model: model)
        guard let hosted = hostCalendar(view) else { return }
        let (host, calendar) = hosted
        await wait { calendar.displayDate == date(2024, 2, 1) }
        #expect(calendar.lastNotifiedMonth == date(2024, 2, 1))

        // The app asks for March with an animation.
        withAnimation { model.month = date(2024, 3, 20) }
        await wait { calendar.animationTargetMonth == date(2024, 3, 1) }
        #expect(calendar.animationTargetMonth == date(2024, 3, 1), "an animated scroll is under way")
        #expect(calendar.displayDate == date(2024, 3, 1))

        // The user catches the grid and lets it settle back on February.
        let runs = model.bodyRuns
        swipe(calendar, toSection: 1)
        #expect(calendar.displayDate == date(2024, 2, 1))
        #expect(calendar.lastNotifiedMonth == date(2024, 2, 1), "the delegate heard of no new month")
        #expect(model.month == date(2024, 2, 1), "the binding says where the calendar is all the same")

        // The body that runs next, for this or any other reason, leaves the calendar there.
        await wait { model.bodyRuns > runs }
        #expect(model.bodyRuns > runs)
        host.view.layoutIfNeeded()
        await settle()
        #expect(calendar.displayDate == date(2024, 2, 1))
        #expect(calendar.animationTargetMonth == nil)
        #expect(calendar.collectionView.contentOffset == calendar.flowLayout.contentOffset(forSection: 1))
        #expect(model.month == date(2024, 2, 1))
    }

    // MARK: SwiftUI can select

    @Test func swiftUICanSelectWithNewStateReachesTheDaysOnScreen() {
        // The predicate is a closure, so the wrapper cannot tell a new one from the old one, and
        // it reloads nothing for it. VoiceOver still has to hear which days it refuses now.
        let box = SelectionBox()
        let style = makeStyle()
        var closedDays: Set<Date> = []
        func view() -> KDCalendarView {
            let closed = closedDays
            return KDCalendarView(range: date(2024, 1, 1)...date(2024, 1, 31), selection: box.binding)
                .calendarStyle(style)
                .canSelect { !closed.contains($0) }
        }
        guard let hosted = hostCalendar(view()) else { return }
        let (host, calendar) = hosted
        calendar.layoutIfNeeded()
        // January 2024 starts on a Monday, so day n is item n - 1.
        func isDimmed(_ day: Int) -> Bool? {
            calendar.layoutIfNeeded()
            return cell(calendar, IndexPath(item: day - 1, section: 0))?.accessibilityTraits.contains(.notEnabled)
        }
        #expect(isDimmed(10) == false)

        closedDays = [date(2024, 1, 10)]
        host.rootView = view()
        host.view.layoutIfNeeded()
        #expect(isDimmed(10) == true)
        #expect(isDimmed(11) == false)
        calendar.selectDate(date(2024, 1, 10))
        #expect(box.dates == [], "and a tap is refused, as it was without the refresh")

        closedDays = []
        host.rootView = view()
        host.view.layoutIfNeeded()
        #expect(isDimmed(10) == false)
    }

    // MARK: SwiftUI configuration

    @Test func swiftUIConfigurationStartsFromTheDefaultsOfANewCalendarView() {
        // The coordinator takes a new view to show the default configuration, and the first
        // update sets only what differs from it.
        let view = CalendarView(frame: .zero)
        let configuration = KDCalendarView.Configuration(range: date(2024, 1, 1)...date(2024, 3, 31))
        #expect(view.style == configuration.style)
        #expect(view.direction == configuration.direction)
        #expect(view.selectionMode == configuration.selectionMode)
        #expect(view.enableDeselection == configuration.allowsDeselection)
        #expect(view.marksWeekends == configuration.marksWeekends)
        #expect(view.isScrollEnabled == configuration.isScrollEnabled)
        #expect(view.forceLtr == !configuration.mirrorsInRightToLeftLayouts)
        #expect(view.semanticContentAttribute == configuration.semanticContentAttribute)
        #expect(view.events == configuration.events)
        #expect(configuration.displayDate == nil)
    }

    @Test func swiftUIUpdateSetsOnlyTheValuesThatChanged() {
        let box = SelectionBox()
        let style = makeStyle()
        var allowsDeselection = true
        var isScrollEnabled = true
        var events: [CalendarEvent] = []
        func view() -> KDCalendarView {
            KDCalendarView(range: date(2024, 1, 1)...date(2024, 3, 31), selection: box.binding)
                .calendarStyle(style)
                .allowsDeselection(allowsDeselection)
                .scrollEnabled(isScrollEnabled)
                .events(events)
        }
        guard let hosted = hostCalendar(view()) else { return }
        let (host, calendar) = hosted

        // Changed behind the wrapper's back, to tell a value that is set from one left alone.
        calendar.enableDeselection = false
        calendar.isScrollEnabled = false
        events = [CalendarEvent(title: "a", startDate: date(2024, 1, 5), endDate: date(2024, 1, 6))]
        host.rootView = view()
        host.view.layoutIfNeeded()
        #expect(calendar.events == events, "the update ran")
        #expect(calendar.enableDeselection == false)
        #expect(calendar.isScrollEnabled == false)

        // A value that changes reaches the view, and only that one.
        allowsDeselection = false
        host.rootView = view()
        host.view.layoutIfNeeded()
        allowsDeselection = true
        host.rootView = view()
        host.view.layoutIfNeeded()
        #expect(calendar.enableDeselection == true)
        #expect(calendar.isScrollEnabled == false)
        isScrollEnabled = false
        host.rootView = view()
        host.view.layoutIfNeeded()
        isScrollEnabled = true
        host.rootView = view()
        host.view.layoutIfNeeded()
        #expect(calendar.isScrollEnabled == true)
        #expect(calendar.events == events)
    }

    // MARK: SwiftUI right to left

    @Test func swiftUIMirroringCalendarRunsRightToLeftInARightToLeftEnvironment() throws {
        let box = SelectionBox()
        let view = KDCalendarView(range: date(2024, 1, 1)...date(2024, 3, 31), selection: box.binding)
            .calendarStyle(makeStyle())
            .mirrorsInRightToLeftLayouts()
            .environment(\.layoutDirection, .rightToLeft)
        let calendar = try #require(hostCalendar(view)).1
        calendar.layoutIfNeeded()
        let width = calendar.collectionView.bounds.width

        // Monday sits on the right and January is the last page.
        #expect(calendar.forceLtr == false)
        #expect(calendar.collectionView.effectiveUserInterfaceLayoutDirection == .rightToLeft)
        #expect(calendar.displayDate == date(2024, 1, 1))
        #expect(calendar.collectionView.contentOffset.x == 2 * width)
        #expect(cell(calendar, IndexPath(item: 0, section: 0))?.frame.maxX == 3 * width)
        #expect(calendar.headerView.dayLabels.first!.frame.minX > calendar.headerView.dayLabels.last!.frame.minX)
    }

    @Test func swiftUIMirroringFollowsTheLayoutDirectionOfTheEnvironment() throws {
        let box = SelectionBox()
        let style = makeStyle()
        var mirrors = true
        var layoutDirection = LayoutDirection.leftToRight
        func view() -> some View {
            KDCalendarView(range: date(2024, 1, 1)...date(2024, 3, 31), selection: box.binding)
                .calendarStyle(style)
                .mirrorsInRightToLeftLayouts(mirrors)
                .environment(\.layoutDirection, layoutDirection)
        }
        let hosted = try #require(hostCalendar(view()))
        let (host, calendar) = hosted
        let width = calendar.collectionView.bounds.width
        let firstCell = IndexPath(item: 0, section: 0)
        /// Runs the body again and lays the calendar out.
        func update() {
            host.rootView = view()
            host.view.layoutIfNeeded()
            calendar.layoutIfNeeded()
        }

        // Left to right, a mirroring calendar looks like any other.
        calendar.layoutIfNeeded()
        #expect(calendar.forceLtr == false)
        #expect(calendar.collectionView.effectiveUserInterfaceLayoutDirection == .leftToRight)
        #expect(cell(calendar, firstCell)?.frame.minX == 0)

        // The environment turns, and the calendar with it, staying on its month.
        layoutDirection = .rightToLeft
        update()
        #expect(calendar.collectionView.effectiveUserInterfaceLayoutDirection == .rightToLeft)
        #expect(calendar.displayDate == date(2024, 1, 1))
        #expect(calendar.collectionView.contentOffset.x == 2 * width)
        #expect(cell(calendar, firstCell)?.frame.maxX == 3 * width)
        #expect(calendar.headerView.dayLabels.first!.frame.minX > calendar.headerView.dayLabels.last!.frame.minX)
        layoutDirection = .leftToRight
        update()
        #expect(calendar.collectionView.effectiveUserInterfaceLayoutDirection == .leftToRight)
        #expect(calendar.displayDate == date(2024, 1, 1))
        #expect(calendar.collectionView.contentOffset.x == 0)
        #expect(cell(calendar, firstCell)?.frame.minX == 0)

        // Without mirroring the grid runs left to right whatever the environment says.
        mirrors = false
        layoutDirection = .rightToLeft
        update()
        #expect(calendar.forceLtr == true)
        #expect(calendar.collectionView.effectiveUserInterfaceLayoutDirection == .leftToRight)
        #expect(cell(calendar, firstCell)?.frame.minX == 0)
        #expect(calendar.headerView.dayLabels.first!.frame.minX < calendar.headerView.dayLabels.last!.frame.minX)
        mirrors = true
        update()
        #expect(calendar.collectionView.effectiveUserInterfaceLayoutDirection == .rightToLeft)
        #expect(calendar.displayDate == date(2024, 1, 1))
        #expect(cell(calendar, firstCell)?.frame.maxX == 3 * width)
    }

    @Test func swiftUICalendarDoesNotMirrorUnlessAsked() throws {
        let box = SelectionBox()
        let view = KDCalendarView(range: date(2024, 1, 1)...date(2024, 3, 31), selection: box.binding)
            .calendarStyle(makeStyle())
            .environment(\.layoutDirection, .rightToLeft)
        let calendar = try #require(hostCalendar(view)).1
        calendar.layoutIfNeeded()
        #expect(calendar.forceLtr == true)
        #expect(calendar.collectionView.effectiveUserInterfaceLayoutDirection == .leftToRight)
        #expect(cell(calendar, IndexPath(item: 0, section: 0))?.frame.minX == 0)
    }

    @Test func swiftUIMirroringCalendarThatStartsRightToLeftFollowsTheEnvironment() throws {
        // The wrapper sets `forceLtr` and the semantic content attribute as each changes, in no
        // particular order, and the first turn comes straight after the first layout.
        let box = SelectionBox()
        let style = makeStyle()
        var mirrors = true
        var layoutDirection = LayoutDirection.rightToLeft
        func view() -> some View {
            KDCalendarView(range: date(2024, 1, 1)...date(2024, 3, 31), selection: box.binding)
                .calendarStyle(style)
                .mirrorsInRightToLeftLayouts(mirrors)
                .environment(\.layoutDirection, layoutDirection)
        }
        let (host, calendar) = try #require(hostCalendar(view()))
        let width = calendar.collectionView.bounds.width
        let firstCell = IndexPath(item: 0, section: 0)
        /// Runs the body again and lays the calendar out.
        func update() {
            host.rootView = view()
            host.view.layoutIfNeeded()
            calendar.layoutIfNeeded()
        }
        /// Whether the calendar shows January, mirrored or not.
        func expectJanuary(isRightToLeft: Bool, _ comment: Comment) {
            let direction: UIUserInterfaceLayoutDirection = isRightToLeft ? .rightToLeft : .leftToRight
            #expect(calendar.collectionView.effectiveUserInterfaceLayoutDirection == direction, comment)
            #expect(calendar.headerView.effectiveUserInterfaceLayoutDirection == direction, comment)
            #expect(calendar.displayDate == date(2024, 1, 1), comment)
            #expect(calendar.headerView.monthLabel.text == "January 2024", comment)
            #expect(calendar.collectionView.contentOffset.x == (isRightToLeft ? 2 * width : 0), comment)
            if isRightToLeft {
                #expect(cell(calendar, firstCell)?.frame.maxX == 3 * width, comment)
            } else {
                #expect(cell(calendar, firstCell)?.frame.minX == 0, comment)
            }
        }

        calendar.layoutIfNeeded()
        expectJanuary(isRightToLeft: true, "right to left from the first update")
        layoutDirection = .leftToRight
        update()
        expectJanuary(isRightToLeft: false, "the environment turns left to right")
        layoutDirection = .rightToLeft
        update()
        expectJanuary(isRightToLeft: true, "and back")

        // Mirroring alone changes, then both at once, each way.
        mirrors = false
        update()
        #expect(calendar.forceLtr == true)
        expectJanuary(isRightToLeft: false, "mirroring off in a right-to-left environment")
        mirrors = true
        update()
        #expect(calendar.forceLtr == false)
        expectJanuary(isRightToLeft: true, "mirroring on in a right-to-left environment")
        mirrors = false
        layoutDirection = .leftToRight
        update()
        expectJanuary(isRightToLeft: false, "mirroring off as the environment turns left to right")
        mirrors = true
        layoutDirection = .rightToLeft
        update()
        expectJanuary(isRightToLeft: true, "mirroring on as the environment turns right to left")
    }

    // MARK: SwiftUI reloads

    @Test func swiftUIUpdateThatChangesSeveralValuesReloadsOnce() {
        let box = SelectionBox()
        var style = makeStyle()
        var range = date(2024, 1, 1)...date(2024, 3, 31)
        var direction = UICollectionView.ScrollDirection.horizontal
        var marksWeekends = true
        var events: [CalendarEvent] = []
        var displayDate = date(2024, 2, 10)
        func view() -> KDCalendarView {
            KDCalendarView(range: range, selection: box.binding)
                .calendarStyle(style)
                .direction(direction)
                .marksWeekends(marksWeekends)
                .events(events)
                .displayDate(displayDate)
        }
        guard let hosted = hostCalendar(view()) else { return }
        let (host, calendar) = hosted
        // The coordinator is the data source: count the view's calls on their way to it.
        let source = CountingDataSource(calendar.dataSource!)
        retained.objects.append(source)
        calendar.dataSource = source
        source.calls = 0

        // Five values that each reload a calendar view, a display date and a selection that both
        // need the new range.
        style.firstWeekday = .sunday
        style.locale = Locale(identifier: "de_DE")
        range = date(2024, 1, 1)...date(2024, 6, 30)
        direction = .vertical
        marksWeekends = false
        events = [CalendarEvent(title: "a", startDate: date(2024, 5, 20), endDate: date(2024, 5, 20, hour: 1))]
        displayDate = date(2024, 5, 3)
        box.dates = [date(2024, 5, 20)]
        host.rootView = view()
        host.view.layoutIfNeeded()

        #expect(source.calls == 2, "one reload for all of them: the start and the end, once")
        #expect(calendar.numberOfSections(in: calendar.collectionView) == 6)
        #expect(calendar.getCachedSectionInfo(0)?.firstDay == 1, "January 2024 starts on a Monday")
        #expect(calendar.flowLayout.scrollDirection == .vertical)
        #expect(calendar.marksWeekends == false)
        #expect(calendar.displayDate == date(2024, 5, 1))
        #expect(calendar.headerView.monthLabel.text == "Mai 2024")
        let selected = calendar.indexPathForDate(date(2024, 5, 20))!
        #expect(calendar.selectedDates == [date(2024, 5, 20)])
        #expect(calendar.collectionView.indexPathsForSelectedItems == [selected])
        #expect(calendar.snapshot.eventIndex.count(at: selected) == 1)

        // An update that changes nothing does not reload.
        host.rootView = view()
        host.view.layoutIfNeeded()
        #expect(source.calls == 2)

        // Neither does one that only scrolls or selects.
        displayDate = date(2024, 3, 3)
        box.dates = [date(2024, 3, 8)]
        host.rootView = view()
        host.view.layoutIfNeeded()
        #expect(calendar.displayDate == date(2024, 3, 1))
        #expect(calendar.selectedDates == [date(2024, 3, 8)])
        #expect(source.calls == 2)
    }

    @Test func swiftUICalendarIsSetUpWithOneReload() {
        // makeUIView hands a new view its data source and the modifiers' values together, so the
        // first update finds nothing left to reload for.
        let box = SelectionBox()
        let style = makeStyle(firstWeekday: .sunday)
        let range = date(2024, 1, 1)...date(2024, 3, 31)
        let events = [CalendarEvent(title: "a", startDate: date(2024, 1, 5), endDate: date(2024, 1, 6))]
        let wrapper = KDCalendarView(range: range, selection: box.binding)
            .calendarStyle(style)
            .direction(.vertical)
            .marksWeekends(false)
            .selectionMode(.single)
            .mirrorsInRightToLeftLayouts()
            .events(events)
            .displayDate(date(2024, 2, 10))
        let view = CalendarView(frame: CGRect(x: 0, y: 0, width: 350, height: 420))
        // Every reload reads the clock, the same number of times.
        var clockReads = 0
        view.now = {
            clockReads += 1
            return Date()
        }
        let coordinator = wrapper.makeCoordinator()
        retained.objects.append(coordinator)

        wrapper.connect(view, to: coordinator, layoutDirection: .rightToLeft)
        let readsToSetUp = clockReads
        #expect(view.dataSource === coordinator)
        #expect(view.delegate === coordinator)
        #expect(view.dateRange == range)
        #expect(view.style == style)
        #expect(view.direction == .vertical)
        #expect(view.marksWeekends == false)
        #expect(view.selectionMode == .single)
        #expect(view.forceLtr == false)
        #expect(view.collectionView.effectiveUserInterfaceLayoutDirection == .rightToLeft)
        #expect(view.events == events)
        #expect(view.snapshot.eventIndex.isEmpty == false, "the reload came after the events")
        #expect(view.getCachedSectionInfo(0)?.firstDay == 1, "and after the style: Monday in a week from Sunday")

        var shown = wrapper.configuration
        shown.layoutDirection = .rightToLeft
        shown.displayDate = nil
        #expect(coordinator.configuration == shown, "all but the display date, which the first update scrolls to")

        clockReads = 0
        view.reloadData()
        #expect(readsToSetUp > 0)
        #expect(readsToSetUp == clockReads, "setting the view up read the clock as often as one reload does")
    }

    // MARK: SwiftUI time zones

    /// The given day of 2024 at midnight in `calendar`.
    private func day(_ calendar: Calendar, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: 2024, month: month, day: day))!
    }

    /// Changes the device's time zone and tells every calendar view, as the system does.
    private func moveDevice(to timeZone: TimeZone) {
        NSTimeZone.default = timeZone
        NotificationCenter.default.post(name: UIApplication.significantTimeChangeNotification, object: nil)
    }

    @Test func swiftUISelectionKeepsItsDayWhenTheDeviceMovesToAnotherTimeZone() {
        // No test may run while the device's time zone is another, so this one never suspends.
        let original = NSTimeZone.default
        defer { moveDevice(to: original) }
        NSTimeZone.default = TimeZone(identifier: "Europe/Athens")!
        let athens = gregorian(in: "Europe/Athens")
        let newYork = gregorian(in: "America/New_York")
        let box = SelectionBox()
        // The default style, whose calendar follows the device.
        func view() -> KDCalendarView {
            KDCalendarView(range: day(athens, 1, 15)...day(athens, 6, 15), selection: box.binding)
        }
        guard let hosted = hostCalendar(view()) else { return }
        let (host, calendar) = hosted
        calendar.selectDate(day(athens, 3, 15))
        #expect(box.dates == [day(athens, 3, 15)])
        #expect(box.changes == 1)

        // The device moves west, where midnight on the 15th in Athens is 18:00 on the 14th. The
        // view keeps the 15th, at another instant, and the binding has to follow it.
        moveDevice(to: TimeZone(identifier: "America/New_York")!)
        #expect(calendar.selectedDates == [day(newYork, 3, 15)])
        #expect(box.dates == [day(newYork, 3, 15)])
        #expect(box.changes == 2)

        // The update that follows reads the binding in New York and finds the day the view shows.
        host.rootView = view()
        host.view.layoutIfNeeded()
        #expect(calendar.selectedDates == [day(newYork, 3, 15)])
        #expect(calendar.collectionView.indexPathsForSelectedItems == [calendar.indexPathForDate(day(newYork, 3, 15))!])
        #expect(box.dates == [day(newYork, 3, 15)])
        #expect(box.changes == 2)

        // East again, where the binding read in Athens would still be the 15th, at 07:00. It is
        // set to midnight all the same.
        moveDevice(to: TimeZone(identifier: "Europe/Athens")!)
        host.rootView = view()
        host.view.layoutIfNeeded()
        #expect(calendar.selectedDates == [day(athens, 3, 15)])
        #expect(box.dates == [day(athens, 3, 15)])
    }

    @Test func swiftUIDisplayedMonthKeepsItsMonthWhenTheDeviceMovesToAnotherTimeZone() {
        // No test may run while the device's time zone is another, so this one never suspends.
        let original = NSTimeZone.default
        defer { moveDevice(to: original) }
        NSTimeZone.default = TimeZone(identifier: "Europe/Athens")!
        let athens = gregorian(in: "Europe/Athens")
        let newYork = gregorian(in: "America/New_York")
        let box = SelectionBox()
        let month = MonthBox(day(athens, 2, 10))
        func view() -> KDCalendarView {
            KDCalendarView(range: day(athens, 1, 15)...day(athens, 6, 15), selection: box.binding)
                .displayedMonth(month.binding)
        }
        guard let hosted = hostCalendar(view()) else { return }
        let (host, calendar) = hosted
        swipe(calendar, toSection: 3)
        #expect(month.month == day(athens, 4, 1))

        // Midnight on 1 April in Athens is 17:00 on 31 March in New York: read there, the binding
        // would ask for March.
        moveDevice(to: TimeZone(identifier: "America/New_York")!)
        #expect(calendar.displayDate == day(newYork, 4, 1))
        #expect(month.month == day(newYork, 4, 1))
        host.rootView = view()
        host.view.layoutIfNeeded()
        #expect(calendar.displayDate == day(newYork, 4, 1))
        #expect(calendar.headerView.monthLabel.text?.hasPrefix("April") == true)
        #expect(month.month == day(newYork, 4, 1))
    }

    @Test func swiftUICorrectionsWaitingForATimeZoneChangeSetTheDatesOfTheNewZone() async {
        let athens = gregorian(in: "Europe/Athens")
        let newYork = gregorian(in: "America/New_York")
        let box = SelectionBox()
        let month = MonthBox(day(athens, 3, 10))
        var style = makeStyle(calendar: athens)
        func view() -> KDCalendarView {
            KDCalendarView(range: day(athens, 1, 15)...day(athens, 6, 15), selection: box.binding)
                .calendarStyle(style)
                .displayedMonth(month.binding)
        }
        guard let hosted = hostCalendar(view()) else { return }
        let (host, calendar) = hosted
        func update() {
            host.rootView = view()
            host.view.layoutIfNeeded()
        }
        await settle()

        // The bindings ask for a day and a month the range does not have. The view shows what it
        // can, and the bindings are to be corrected once the update has ended.
        box.dates = [day(athens, 3, 15), day(athens, 8, 1)]
        month.month = day(athens, 9, 1)
        update()
        #expect(calendar.selectedDates == [day(athens, 3, 15)])
        #expect(calendar.displayDate == day(athens, 3, 1))
        #expect(box.dates == [day(athens, 3, 15), day(athens, 8, 1)], "state does not change during a view update")

        // Before they are, the style moves to New York, where midnight on the 15th in Athens is
        // the evening of the 14th, and midnight on 1 March the evening of 29 February.
        style.calendar = newYork
        update()
        #expect(calendar.selectedDates == [day(newYork, 3, 15)])
        #expect(calendar.displayDate == day(newYork, 3, 1))
        await settle()
        #expect(box.dates == [day(newYork, 3, 15)], "what the view shows now, not what it showed in Athens")
        #expect(month.month == day(newYork, 3, 1))

        // So the next update finds the bindings and the view agreeing.
        update()
        await settle()
        #expect(calendar.selectedDates == [day(newYork, 3, 15)])
        #expect(calendar.displayDate == day(newYork, 3, 1))
        #expect(box.dates == [day(newYork, 3, 15)])
        #expect(month.month == day(newYork, 3, 1))
    }

    @Test func swiftUIBindingsFollowAStyleThatMovesToAnotherTimeZone() async {
        let athens = gregorian(in: "Europe/Athens")
        let newYork = gregorian(in: "America/New_York")
        let box = SelectionBox()
        let month = MonthBox(day(athens, 2, 10))
        var style = makeStyle(calendar: athens)
        func view() -> KDCalendarView {
            KDCalendarView(range: day(athens, 1, 15)...day(athens, 6, 15), selection: box.binding)
                .calendarStyle(style)
                .displayedMonth(month.binding)
        }
        guard let hosted = hostCalendar(view()) else { return }
        let (host, calendar) = hosted
        func update() {
            host.rootView = view()
            host.view.layoutIfNeeded()
        }
        swipe(calendar, toSection: 3)
        calendar.selectDate(day(athens, 4, 15))
        #expect(box.dates == [day(athens, 4, 15)])
        #expect(month.month == day(athens, 4, 1))

        // The view moves its dates during the update, when the bindings cannot be set. Their old
        // values are not read in New York, in this update or in one that comes before they are set.
        style.calendar = newYork
        update()
        #expect(calendar.selectedDates == [day(newYork, 4, 15)])
        #expect(calendar.displayDate == day(newYork, 4, 1))
        #expect(box.dates == [day(athens, 4, 15)], "state does not change during a view update")
        #expect(month.month == day(athens, 4, 1))
        update()
        #expect(calendar.selectedDates == [day(newYork, 4, 15)])
        #expect(calendar.displayDate == day(newYork, 4, 1))
        await settle()
        #expect(box.dates == [day(newYork, 4, 15)])
        #expect(month.month == day(newYork, 4, 1))
        update()
        await settle()
        #expect(calendar.selectedDates == [day(newYork, 4, 15)])
        #expect(calendar.displayDate == day(newYork, 4, 1))
        #expect(box.dates == [day(newYork, 4, 15)])
        #expect(month.month == day(newYork, 4, 1))

        // Values that come with the new time zone are the app's own, and are applied as given.
        style.calendar = athens
        box.dates = [day(athens, 5, 20)]
        month.month = day(athens, 5, 1)
        update()
        await settle()
        #expect(calendar.selectedDates == [day(athens, 5, 20)])
        #expect(calendar.displayDate == day(athens, 5, 1))
        #expect(box.dates == [day(athens, 5, 20)])
        #expect(month.month == day(athens, 5, 1))
    }
}
