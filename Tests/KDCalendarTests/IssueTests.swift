import Testing
import UIKit

@testable import KDCalendar

/// Tests named after the GitHub issues they close.
@Suite(.serialized)
@MainActor
struct IssueTests {

    final class FixedDataSource: CalendarViewDataSource {
        var start: Date
        var end: Date
        init(start: Date, end: Date) {
            self.start = start
            self.end = end
        }
        func startDate() -> Date { start }
        func endDate() -> Date { end }
    }

    final class RecordingDelegate: CalendarViewDelegate {
        var selected: [Date] = []
        var deselected: [Date] = []
        var ranges: [ClosedRange<Date>] = []
        var canSelect: (Date) -> Bool = { _ in true }
        var styleForDate: (Date) -> CalendarView.Style? = { _ in nil }

        func calendar(_ calendar: CalendarView, didScrollToMonth date: Date) {}
        func calendar(_ calendar: CalendarView, didSelectDate date: Date, withEvents events: [CalendarEvent]) {
            selected.append(date)
        }
        func calendar(_ calendar: CalendarView, canSelectDate date: Date) -> Bool { canSelect(date) }
        func calendar(_ calendar: CalendarView, didDeselectDate date: Date) { deselected.append(date) }
        func calendar(_ calendar: CalendarView, didSelectRange range: ClosedRange<Date>) { ranges.append(range) }
        func calendar(_ calendar: CalendarView, styleForDate date: Date) -> CalendarView.Style? { styleForDate(date) }
    }

    let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    static let window: UIWindow = {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 350, height: 500))
        window.isHidden = false
        return window
    }()

    final class Retained {
        var objects: [AnyObject] = []
    }
    let retained = Retained()

    init() {
        Self.window.subviews.forEach { $0.removeFromSuperview() }
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        utc.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func days(_ from: Date, _ to: Date) -> [Date] {
        var result: [Date] = []
        var day = from
        while day <= to {
            result.append(day)
            day = utc.date(byAdding: .day, value: 1, to: day)!
        }
        return result
    }

    private func makeCalendar(start: Date, end: Date, frame: CGRect = CGRect(x: 0, y: 0, width: 350, height: 420))
        -> CalendarView
    {
        var style = CalendarView.Style()
        style.locale = Locale(identifier: "en_US")
        style.calendar = utc
        let view = CalendarView(frame: frame)
        view.style = style
        let dataSource = FixedDataSource(start: start, end: end)
        let delegate = RecordingDelegate()
        retained.objects.append(dataSource)
        retained.objects.append(delegate)
        view.dataSource = dataSource
        view.delegate = delegate
        Self.window.addSubview(view)
        view.layoutIfNeeded()
        return view
    }

    private func delegate(of view: CalendarView) -> RecordingDelegate {
        view.delegate as! RecordingDelegate
    }

    private func cell(_ view: CalendarView, _ indexPath: IndexPath) -> CalendarDayCell? {
        view.collectionView.cellForItem(at: indexPath) as? CalendarDayCell
    }

    /// Simulates a tap: the collection view's own selection followed by the delegate callbacks.
    private func tap(_ view: CalendarView, _ date: Date) {
        let indexPath = view.indexPathForDate(date)!
        if view.selectedIndexPaths.contains(indexPath) {
            guard view.collectionView(view.collectionView, shouldDeselectItemAt: indexPath) else { return }
            view.collectionView.deselectItem(at: indexPath, animated: false)
            view.collectionView(view.collectionView, didDeselectItemAt: indexPath)
        } else {
            guard view.collectionView(view.collectionView, shouldSelectItemAt: indexPath) else { return }
            view.collectionView.selectItem(at: indexPath, animated: false, scrollPosition: [])
            view.collectionView(view.collectionView, didSelectItemAt: indexPath)
        }
    }

    // MARK: #32 range selection

    @Test func issue32_twoTapsSelectEveryDayBetweenThem() {
        let view = makeCalendar(start: date(2024, 1, 1), end: date(2024, 1, 31))
        view.selectionMode = .range
        tap(view, date(2024, 1, 8))
        #expect(view.selectedDates == [date(2024, 1, 8)])
        #expect(delegate(of: view).ranges.isEmpty)
        tap(view, date(2024, 1, 12))
        #expect(view.selectedDates == days(date(2024, 1, 8), date(2024, 1, 12)))
        #expect(delegate(of: view).selected == [date(2024, 1, 8), date(2024, 1, 12)])
        #expect(delegate(of: view).ranges == [date(2024, 1, 8)...date(2024, 1, 12)])
        #expect(Set(view.collectionView.indexPathsForSelectedItems ?? []).count == 5)
        #expect(cell(view, IndexPath(item: 9, section: 0))?.isSelected == true, "the 10th sits between the ends")
    }

    @Test func issue32_rangeWorksInReverseOrderAndAcrossMonths() {
        let view = makeCalendar(start: date(2024, 1, 1), end: date(2024, 3, 31))
        view.selectionMode = .range
        view.selectDate(date(2024, 2, 3))
        view.selectDate(date(2024, 1, 30))
        #expect(view.selectedDates.sorted() == days(date(2024, 1, 30), date(2024, 2, 3)))
        #expect(delegate(of: view).ranges == [date(2024, 1, 30)...date(2024, 2, 3)])
        view.setDisplayDate(date(2024, 2, 1))
        view.layoutIfNeeded()
        #expect(cell(view, view.indexPathForDate(date(2024, 2, 1))!)?.isSelected == true)
    }

    @Test func issue32_aThirdTapStartsANewRange() {
        let view = makeCalendar(start: date(2024, 1, 1), end: date(2024, 1, 31))
        view.selectionMode = .range
        tap(view, date(2024, 1, 8))
        tap(view, date(2024, 1, 10))
        tap(view, date(2024, 1, 20))
        #expect(view.selectedDates == [date(2024, 1, 20)])
        #expect(delegate(of: view).deselected == days(date(2024, 1, 8), date(2024, 1, 10)))
        #expect(view.collectionView.indexPathsForSelectedItems == [IndexPath(item: 19, section: 0)])
    }

    @Test func issue32_deselectingClearsTheRangeAndTheSameDayCanStartAgain() {
        let view = makeCalendar(start: date(2024, 1, 1), end: date(2024, 1, 31))
        view.selectionMode = .range
        tap(view, date(2024, 1, 8))
        tap(view, date(2024, 1, 10))
        tap(view, date(2024, 1, 9))
        #expect(view.selectedDates == [])
        #expect(view.collectionView.indexPathsForSelectedItems == [])
        #expect(delegate(of: view).deselected.count == 3)
        tap(view, date(2024, 1, 8))
        #expect(view.selectedDates == [date(2024, 1, 8)])
        tap(view, date(2024, 1, 9))
        #expect(view.selectedDates == [date(2024, 1, 8), date(2024, 1, 9)])
    }

    @Test func issue32_rangeSkipsDaysTheDelegateRefusesAndDaysOutOfRange() {
        let view = makeCalendar(start: date(2024, 1, 5), end: date(2024, 1, 31))
        view.selectionMode = .range
        delegate(of: view).canSelect = { [utc] in utc.component(.weekday, from: $0) != 1 }  // no Sundays
        view.selectDate(date(2024, 1, 6))
        view.selectDate(date(2024, 1, 9))
        #expect(view.selectedDates.sorted() == [date(2024, 1, 6), date(2024, 1, 8), date(2024, 1, 9)])
        view.selectRange(date(2024, 1, 1)...date(2024, 1, 8))
        #expect(view.selectedDates == [date(2024, 1, 5), date(2024, 1, 6), date(2024, 1, 8)])
        #expect(delegate(of: view).ranges.last == date(2024, 1, 5)...date(2024, 1, 8))
    }

    @Test func issue32_selectRangeWorksInEveryModeAndReplacesTheSelection() {
        let view = makeCalendar(start: date(2024, 1, 1), end: date(2024, 1, 31))
        view.selectDate(date(2024, 1, 20))
        view.selectRange(date(2024, 1, 2)...date(2024, 1, 4))
        #expect(view.selectedDates == days(date(2024, 1, 2), date(2024, 1, 4)))
        view.selectionMode = .range
        #expect(view.selectedDates == [], "switching to range mode starts clean")
        view.selectRange(date(2024, 1, 2)...date(2024, 1, 4))
        tap(view, date(2024, 1, 10))
        #expect(view.selectedDates == [date(2024, 1, 10)], "a tap after a programmatic range starts a new one")
    }

    @Test func issue32_multipleSelectionEnableBridgesToTheMode() {
        let view = makeCalendar(start: date(2024, 1, 1), end: date(2024, 1, 31))
        #expect(view.multipleSelectionEnable == true)
        view.multipleSelectionEnable = false
        #expect(view.selectionMode == .single)
        view.selectionMode = .range
        #expect(view.multipleSelectionEnable == true)
    }

    // MARK: #136 and #122 per-date styles

    @Test func issue136_aDelegateCanStyleOneDay() {
        let view = makeCalendar(start: date(2024, 1, 1), end: date(2024, 1, 31))
        var holiday = view.style
        holiday.cellColorDefault = .systemPink
        holiday.cellTextColorDefault = .white
        delegate(of: view).styleForDate = { [utc] in utc.component(.day, from: $0) == 6 ? holiday : nil }
        view.reloadData()
        view.layoutIfNeeded()
        #expect(cell(view, IndexPath(item: 5, section: 0))?.bgView.backgroundColor == .systemPink)
        #expect(cell(view, IndexPath(item: 5, section: 0))?.style == holiday)
        #expect(cell(view, IndexPath(item: 4, section: 0))?.bgView.backgroundColor == view.style.cellColorDefault)
        #expect(cell(view, IndexPath(item: 4, section: 0))?.style == view.style)
    }

    @Test func issue122_nonSelectableDaysCanBeGreyedOut() {
        let view = makeCalendar(start: date(2024, 1, 1), end: date(2024, 1, 31))
        var disabled = view.style
        disabled.cellTextColorDefault = disabled.cellColorOutOfRange
        disabled.cellColorDefault = .clear
        let isSunday: (Date) -> Bool = { [utc] in utc.component(.weekday, from: $0) == 1 }
        delegate(of: view).canSelect = isSunday
        delegate(of: view).styleForDate = { isSunday($0) ? nil : disabled }
        view.reloadData()
        view.layoutIfNeeded()
        let monday = cell(view, IndexPath(item: 0, section: 0))
        let sunday = cell(view, IndexPath(item: 6, section: 0))
        #expect(monday?.textLabel.textColor == view.style.cellColorOutOfRange)
        #expect(sunday?.textLabel.textColor == view.style.cellTextColorWeekend)
        view.selectDate(date(2024, 1, 1))
        view.selectDate(date(2024, 1, 7))
        #expect(view.selectedDates == [date(2024, 1, 7)])
    }

    // MARK: #135 no data source

    @Test func issue135_aCalendarWithoutADataSourceShowsTheCurrentMonth() {
        let view = CalendarView(frame: CGRect(x: 0, y: 0, width: 350, height: 420))
        Self.window.addSubview(view)
        view.layoutIfNeeded()
        #expect(view.numberOfSections(in: view.collectionView) == 1)
        #expect(view.displayDate == view.calendar.dateInterval(of: .month, for: Date())?.start)
        let today = view.indexPathForDate(Date())!
        #expect(cell(view, today)?.isToday == true)
        #expect(cell(view, today)?.isOutOfRange == false)
        #expect(view.dateRange == view.calendar.startOfDay(for: Date())...view.calendar.startOfDay(for: Date()))
    }

    // MARK: #117 cell font

    @Test func issue117_theCellFontFromAStyleIsApplied() {
        let view = makeCalendar(start: date(2024, 1, 1), end: date(2024, 1, 31))
        let font = UIFont.italicSystemFont(ofSize: 11)
        view.style.cellFont = font
        view.layoutIfNeeded()
        #expect(cell(view, IndexPath(item: 0, section: 0))?.textLabel.font == font)
        #expect(view.style.firstWeekday == .monday, "the other attributes are untouched")
    }

    // MARK: #128 tiny frames

    @Test func issue128_aFrameShorterThanTheHeaderDoesNotAssert() {
        let view = makeCalendar(
            start: date(2024, 1, 1), end: date(2024, 1, 31), frame: CGRect(x: 0, y: 0, width: 350, height: 50))
        view.setDisplayDate(date(2024, 1, 10))
        view.layoutIfNeeded()
        #expect(view.flowLayout.itemSize.width > 0 && view.flowLayout.itemSize.height > 0)
        #expect(view.collectionView.frame.height == 0)
        view.frame = CGRect(x: 0, y: 0, width: 350, height: 200)
        view.layoutIfNeeded()
        #expect(view.flowLayout.itemSize == CGSize(width: 50, height: 20))
        #expect(cell(view, IndexPath(item: 9, section: 0))?.day == 10)
    }
}
