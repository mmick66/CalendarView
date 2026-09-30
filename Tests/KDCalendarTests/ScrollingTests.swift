import Testing
import UIKit

@testable import KDCalendar

/// Scrolling, vertical paging, long press, right-to-left layout, appearance changes and the
/// archived-view path.
///
/// UIKit does not run scroll animations in a test process, so the tests move the content
/// offset and deliver the scroll view callbacks themselves, as UIKit would.
@Suite(.serialized)
@MainActor
struct ScrollingTests {

    final class FixedDataSource: CalendarViewDataSource {
        let start: Date
        let end: Date
        init(start: Date, end: Date) {
            self.start = start
            self.end = end
        }
        func startDate() -> Date { start }
        func endDate() -> Date { end }
    }

    final class RecordingDelegate: CalendarViewDelegate {
        var scrolledTo: [Date] = []
        var longPressed: [(Date, [CalendarEvent]?)] = []
        func calendar(_ calendar: CalendarView, didScrollToMonth date: Date) { scrolledTo.append(date) }
        func calendar(_ calendar: CalendarView, didSelectDate date: Date, withEvents events: [CalendarEvent]) {}
        func calendar(_ calendar: CalendarView, didLongPressDate date: Date, withEvents events: [CalendarEvent]?) {
            longPressed.append((date, events))
        }
    }

    /// A long press whose state and location the test controls.
    final class FakeLongPress: UILongPressGestureRecognizer {
        var fakeState: UIGestureRecognizer.State = .began
        var point = CGPoint.zero
        override var state: UIGestureRecognizer.State {
            get { fakeState }
            set { fakeState = newValue }
        }
        override func location(in view: UIView?) -> CGPoint { point }
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

    private func makeCalendar(
        start: Date, end: Date, direction: UICollectionView.ScrollDirection = .horizontal
    ) -> CalendarView {
        var style = CalendarView.Style()
        style.locale = Locale(identifier: "en_US")
        style.calendar = utc
        let view = CalendarView(frame: CGRect(x: 0, y: 0, width: 350, height: 420))
        view.style = style
        view.direction = direction
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

    /// Finishes an animated scroll the way UIKit does: the offset lands and the callback fires.
    private func finishAnimation(_ view: CalendarView, at offset: CGPoint) {
        view.collectionView.contentOffset = offset
        view.scrollViewDidEndScrollingAnimation(view.collectionView)
        view.layoutIfNeeded()
    }

    // MARK: Animated scrolling

    @Test func anAnimatedScrollReportsTheMonthWhenItSettles() {
        let view = makeCalendar(start: date(2024, 1, 15), end: date(2024, 3, 10))
        #expect(delegate(of: view).scrolledTo == [date(2024, 1, 1)])
        view.setDisplayDate(date(2024, 2, 10), animated: true)
        #expect(view.displayDate == date(2024, 2, 1), "the header changes at once")
        #expect(delegate(of: view).scrolledTo == [date(2024, 1, 1)], "the delegate waits for the animation")
        #expect(view.animationTargetMonth == date(2024, 2, 1))
        finishAnimation(view, at: CGPoint(x: view.collectionView.bounds.width, y: 0))
        #expect(delegate(of: view).scrolledTo == [date(2024, 1, 1), date(2024, 2, 1)])
        #expect(view.animationTargetMonth == nil)
        #expect(view.collectionView.contentOffset.x == view.collectionView.bounds.width)
        #expect(cell(view, IndexPath(item: 3, section: 1))?.configuration.day == 1)
    }

    @Test func rapidNextMonthTapsEndOnTheLastTargetWithoutSnappingBack() {
        // Issue #133: the interrupted animation used to report the old month.
        let view = makeCalendar(start: date(2024, 1, 15), end: date(2024, 4, 10))
        let width = view.collectionView.bounds.width
        view.goToNextMonth()
        // The second tap interrupts the first animation at its current offset; UIKit reports the
        // end of the interrupted animation before starting the next one.
        view.collectionView.contentOffset = CGPoint(x: width * 0.3, y: 0)
        view.goToNextMonth()
        view.scrollViewDidEndScrollingAnimation(view.collectionView)
        #expect(view.displayDate == date(2024, 3, 1), "an interrupted animation does not report")
        view.collectionView.contentOffset = CGPoint(x: width * 1.4, y: 0)
        view.goToNextMonth()
        view.scrollViewDidEndScrollingAnimation(view.collectionView)
        finishAnimation(view, at: CGPoint(x: 3 * width, y: 0))
        #expect(view.displayDate == date(2024, 4, 1))
        #expect(view.headerView.monthLabel.text == "April 2024")
        #expect(delegate(of: view).scrolledTo.last == date(2024, 4, 1))
        #expect(!delegate(of: view).scrolledTo.dropFirst().contains(date(2024, 1, 1)), "no snap back to January")
        #expect(view.collectionView.contentOffset.x == 3 * view.collectionView.bounds.width)
    }

    @Test func aDragThatEndsOnAnotherPageReportsThatMonth() {
        let view = makeCalendar(start: date(2024, 1, 15), end: date(2024, 3, 10))
        view.setDisplayDate(date(2024, 3, 1), animated: true)
        // The user grabs the view mid-animation and lets it settle on February.
        view.collectionView(view.collectionView, shouldSelectItemAt: IndexPath(item: 0, section: 0))
        view.scrollViewWillBeginDragging(view.collectionView)
        #expect(view.animationTargetMonth == nil, "a drag cancels the animation's target")
        view.collectionView.contentOffset = CGPoint(x: view.collectionView.bounds.width, y: 0)
        view.scrollViewDidEndDecelerating(view.collectionView)
        #expect(view.displayDate == date(2024, 2, 1))
        #expect(delegate(of: view).scrolledTo.last == date(2024, 2, 1))
        // A stale animation end at another offset is ignored once a newer target is set.
        view.setDisplayDate(date(2024, 3, 1), animated: true)
        view.collectionView.contentOffset = CGPoint(x: 0, y: 0)
        view.scrollViewDidEndScrollingAnimation(view.collectionView)
        #expect(view.displayDate == date(2024, 3, 1))
        #expect(delegate(of: view).scrolledTo.last == date(2024, 2, 1), "the stale callback is ignored")
        finishAnimation(view, at: CGPoint(x: 2 * view.collectionView.bounds.width, y: 0))
        #expect(delegate(of: view).scrolledTo.last == date(2024, 3, 1))
    }

    @Test func aDragReleasedOnAPageBoundaryReportsThatMonth() {
        let view = makeCalendar(start: date(2024, 1, 15), end: date(2024, 3, 10))
        view.scrollViewWillBeginDragging(view.collectionView)
        view.collectionView.contentOffset = CGPoint(x: view.collectionView.bounds.width, y: 0)
        // Released exactly on February's page: UIKit does not decelerate, so no other callback follows.
        view.scrollViewDidEndDragging(view.collectionView, willDecelerate: false)
        #expect(view.displayDate == date(2024, 2, 1))
        #expect(view.headerView.monthLabel.text == "February 2024")
        #expect(delegate(of: view).scrolledTo == [date(2024, 1, 1), date(2024, 2, 1)])

        // A drag that will decelerate waits for the deceleration to end.
        view.scrollViewWillBeginDragging(view.collectionView)
        view.collectionView.contentOffset = CGPoint(x: 1.6 * view.collectionView.bounds.width, y: 0)
        view.scrollViewDidEndDragging(view.collectionView, willDecelerate: true)
        #expect(view.displayDate == date(2024, 2, 1))
        view.collectionView.contentOffset = CGPoint(x: 2 * view.collectionView.bounds.width, y: 0)
        view.scrollViewDidEndDecelerating(view.collectionView)
        #expect(delegate(of: view).scrolledTo == [date(2024, 1, 1), date(2024, 2, 1), date(2024, 3, 1)])
    }

    @Test func anAnimatedScrollBeforeTheFirstLayoutReportsTheMonth() {
        // SwiftUI sets the month during its update, before the view has a size. The offset does
        // not move, so UIKit never reports the end of an animation.
        // The same order as KDCalendarView: data source and delegate first, then the style.
        let view = CalendarView(frame: .zero)
        let dataSource = FixedDataSource(start: date(2024, 1, 15), end: date(2024, 3, 10))
        let delegate = RecordingDelegate()
        retained.objects.append(dataSource)
        retained.objects.append(delegate)
        view.dataSource = dataSource
        view.delegate = delegate
        var style = CalendarView.Style()
        style.calendar = utc
        view.style = style
        view.setDisplayDate(date(2024, 2, 10), animated: true)
        #expect(view.animationTargetMonth == nil, "no animation is waited for")
        view.frame = CGRect(x: 0, y: 0, width: 350, height: 420)
        Self.window.addSubview(view)
        view.layoutIfNeeded()
        #expect(delegate.scrolledTo == [date(2024, 2, 1)])
        #expect(view.displayDate == date(2024, 2, 1))
        #expect(view.collectionView.contentOffset.x == view.collectionView.bounds.width)
    }

    @Test func anAnimatedScrollToTheMonthOnScreenDoesNotWait() {
        let view = makeCalendar(start: date(2024, 1, 15), end: date(2024, 3, 10))
        view.setDisplayDate(date(2024, 2, 10))
        view.setDisplayDate(date(2024, 2, 20), animated: true)
        #expect(view.animationTargetMonth == nil, "the offset does not move, so no callback comes")
        #expect(delegate(of: view).scrolledTo == [date(2024, 1, 1), date(2024, 2, 1)])
        // A drag that ends on another month still reports it.
        view.collectionView.contentOffset = CGPoint(x: 2 * view.collectionView.bounds.width, y: 0)
        view.scrollViewDidEndDecelerating(view.collectionView)
        #expect(delegate(of: view).scrolledTo.last == date(2024, 3, 1))
    }

    // MARK: Vertical paging

    @Test func verticalPagingStacksMonthsAndScrollsOnTheYAxis() {
        let view = makeCalendar(start: date(2024, 1, 15), end: date(2024, 3, 10), direction: .vertical)
        let height = view.collectionView.bounds.height
        #expect(view.scrollViewOffset(for: date(2024, 2, 10)) == CGPoint(x: 0, y: height))
        #expect(view.flowLayout.scrollDirection == .vertical)
        view.setDisplayDate(date(2024, 3, 5))
        view.layoutIfNeeded()
        #expect(view.collectionView.contentOffset == CGPoint(x: 0, y: 2 * height))
        #expect(view.dateFromScrollViewPosition() == date(2024, 3, 1))
        #expect(cell(view, IndexPath(item: 4, section: 2))?.configuration.day == 1)
        let attributes = view.flowLayout.layoutAttributesForItem(at: IndexPath(item: 8, section: 1))
        #expect(attributes?.frame.origin.x == view.flowLayout.itemSize.width)
        #expect(attributes?.frame.origin.y == height + view.flowLayout.itemSize.height)

        view.setDisplayDate(date(2024, 2, 1), animated: true)
        finishAnimation(view, at: CGPoint(x: 0, y: height))
        #expect(delegate(of: view).scrolledTo.last == date(2024, 2, 1))
        #expect(view.dateFromScrollViewPosition() == date(2024, 2, 1))
    }

    @Test func switchingDirectionKeepsTheDisplayedMonth() {
        let view = makeCalendar(start: date(2024, 1, 15), end: date(2024, 3, 10))
        view.setDisplayDate(date(2024, 2, 10))
        view.direction = .vertical
        view.layoutIfNeeded()
        #expect(view.displayDate == date(2024, 2, 1))
        #expect(view.collectionView.contentOffset == CGPoint(x: 0, y: view.collectionView.bounds.height))
        view.direction = .horizontal
        view.layoutIfNeeded()
        #expect(view.collectionView.contentOffset == CGPoint(x: view.collectionView.bounds.width, y: 0))
    }

    /// At some widths a flow of the items wraps six days to a row, which must not leak into the
    /// page geometry: the content stays a whole number of pages and every day of the last page
    /// shows. The size is whole pixels at 3x, as Auto Layout makes it, so the content offset is
    /// not rounded off a page.
    @Test(arguments: [UICollectionView.ScrollDirection.horizontal, .vertical])
    func fractionalSizesKeepWholePagesAndEveryCell(direction: UICollectionView.ScrollDirection) {
        let view = makeCalendar(start: date(2024, 1, 15), end: date(2024, 3, 10), direction: direction)
        view.frame.size = CGSize(width: 258 + 1 / 3, height: view.style.headerHeight + 300)
        view.layoutIfNeeded()
        view.setDisplayDate(date(2024, 3, 10))
        view.layoutIfNeeded()

        let page = view.collectionView.bounds.size
        let pages = CGFloat(view.collectionView.numberOfSections)
        let content = view.flowLayout.collectionViewContentSize
        switch direction {
        case .vertical: #expect(content == CGSize(width: page.width, height: pages * page.height))
        default: #expect(content == CGSize(width: pages * page.width, height: page.height))
        }

        let visible = view.collectionView.indexPathsForVisibleItems
        #expect(visible.count == 42)
        #expect(visible.allSatisfy { $0.section == 2 })
        let onPage = view.flowLayout.layoutAttributesForElements(in: view.collectionView.bounds) ?? []
        #expect(Set(onPage.map(\.indexPath)) == Set((0..<42).map { IndexPath(item: $0, section: 2) }))
        for attributes in onPage {
            #expect(view.collectionView.bounds.contains(attributes.center))
        }
    }

    // MARK: Long press

    @Test func longPressReportsTheDayAndItsEvents() {
        let view = makeCalendar(start: date(2024, 1, 1), end: date(2024, 1, 31))
        view.events = [
            CalendarEvent(title: "a", startDate: date(2024, 1, 10), endDate: date(2024, 1, 10).addingTimeInterval(3600))
        ]
        view.layoutIfNeeded()
        let gesture = FakeLongPress()
        gesture.point = cell(view, IndexPath(item: 9, section: 0))!.center
        view.handleLongPress(gesture: gesture)
        #expect(delegate(of: view).longPressed.count == 1)
        #expect(delegate(of: view).longPressed.first?.0 == date(2024, 1, 10))
        #expect(delegate(of: view).longPressed.first?.1?.map(\.title) == ["a"])

        gesture.point = cell(view, IndexPath(item: 11, section: 0))!.center
        view.handleLongPress(gesture: gesture)
        #expect(delegate(of: view).longPressed.last?.0 == date(2024, 1, 12))
        #expect(delegate(of: view).longPressed.last?.1 == nil, "no events is reported as nil")

        gesture.fakeState = .changed
        view.handleLongPress(gesture: gesture)
        #expect(delegate(of: view).longPressed.count == 2, "only the beginning of a press counts")

        gesture.fakeState = .began
        gesture.point = CGPoint(x: -100, y: -100)
        view.handleLongPress(gesture: gesture)
        #expect(delegate(of: view).longPressed.count == 2, "a press outside the grid is ignored")
    }

    // MARK: Right to left

    @Test func rightToLeftLayoutMirrorsTheGridUnlessForcedLeftToRight() {
        let view = makeCalendar(start: date(2024, 1, 1), end: date(2024, 1, 31))
        view.semanticContentAttribute = .forceRightToLeft
        #expect(view.effectiveUserInterfaceLayoutDirection == .rightToLeft)
        view.forceLtr = true
        #expect(view.collectionView.transform == .identity)

        view.forceLtr = false
        view.layoutIfNeeded()
        #expect(view.collectionView.transform == CGAffineTransform(scaleX: -1, y: 1))
        #expect(
            cell(view, IndexPath(item: 0, section: 0))?.transform == CGAffineTransform(scaleX: -1, y: 1),
            "cells flip back")
        #expect(
            view.headerView.dayLabels.first!.frame.minX > view.headerView.dayLabels.last!.frame.minX,
            "Monday sits on the right")

        view.forceLtr = true
        view.layoutIfNeeded()
        #expect(view.collectionView.transform == .identity)
        #expect(cell(view, IndexPath(item: 0, section: 0))?.transform == .identity)
    }

    // MARK: Appearance

    @Test func cellBordersFollowAnAppearanceChange() {
        let view = makeCalendar(start: date(2024, 1, 1), end: date(2024, 1, 31))
        view.style.cellSelectedBorderColor = UIColor { $0.userInterfaceStyle == .dark ? .white : .black }
        view.selectDate(date(2024, 1, 10))
        view.layoutIfNeeded()
        let selected = cell(view, IndexPath(item: 9, section: 0))!
        view.traitOverrides.userInterfaceStyle = .light
        view.layoutIfNeeded()
        #expect(selected.bgView.layer.borderColor.map { UIColor(cgColor: $0) } == UIColor.black)
        view.traitOverrides.userInterfaceStyle = .dark
        view.layoutIfNeeded()
        #expect(selected.bgView.layer.borderColor.map { UIColor(cgColor: $0) } == UIColor.white)
    }

    @Test func cellBordersFollowAContrastChange() {
        let view = makeCalendar(start: date(2024, 1, 1), end: date(2024, 1, 31))
        view.style.cellSelectedBorderColor = UIColor { $0.accessibilityContrast == .high ? .black : .gray }
        view.selectDate(date(2024, 1, 10))
        view.layoutIfNeeded()
        let selected = cell(view, IndexPath(item: 9, section: 0))!
        view.traitOverrides.accessibilityContrast = .normal
        view.layoutIfNeeded()
        #expect(selected.bgView.layer.borderColor.map { UIColor(cgColor: $0) } == UIColor.gray)
        view.traitOverrides.accessibilityContrast = .high
        view.layoutIfNeeded()
        #expect(selected.bgView.layer.borderColor.map { UIColor(cgColor: $0) } == UIColor.black)
    }

    @Test func cellBordersResolveAgainstTheCellsOwnAppearance() {
        let dynamic = UIColor { $0.userInterfaceStyle == .dark ? .white : .black }
        let dayCell = CalendarDayCell(frame: CGRect(x: 0, y: 0, width: 40, height: 40))
        Self.window.addSubview(dayCell)
        dayCell.traitOverrides.userInterfaceStyle = .dark
        dayCell.layoutIfNeeded()
        #expect(dayCell.traitCollection.userInterfaceStyle == .dark)
        // The current trait collection is light, as it can be during cellForItemAt.
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            var style = CalendarView.Style()
            style.cellBorderColor = dynamic
            dayCell.configuration = DayCellConfiguration(day: 7, style: style)
            #expect(dayCell.bgView.layer.borderColor.map { UIColor(cgColor: $0) } == UIColor.white)
            style.cellSelectedBorderColor = dynamic
            dayCell.configuration = DayCellConfiguration(day: 7, style: style)
            dayCell.isSelected = true
            #expect(dayCell.bgView.layer.borderColor.map { UIColor(cgColor: $0) } == UIColor.white)
        }
    }

    // MARK: Archived views

    @Test func aViewDecodedFromAnArchiveWorks() throws {
        let original = CalendarView(frame: CGRect(x: 0, y: 0, width: 350, height: 420))
        let data = try NSKeyedArchiver.archivedData(withRootObject: original, requiringSecureCoding: false)
        let unarchiver = try NSKeyedUnarchiver(forReadingFrom: data)
        unarchiver.requiresSecureCoding = false
        let decoded = try #require(unarchiver.decodeObject(forKey: NSKeyedArchiveRootObjectKey) as? CalendarView)
        decoded.awakeFromNib()
        #expect(decoded.subviews.filter { $0 is UICollectionView }.count == 1, "setup runs once")
        #expect(decoded.subviews.filter { $0 is CalendarHeaderView }.count == 1)
        #expect(decoded.collectionView.superview === decoded, "the archived grid is replaced by the view's own")
        #expect(decoded.headerView.superview === decoded)
        #expect(decoded.headerView.monthLabel.superview === decoded.headerView)
        #expect(decoded.headerView.dayLabels.count == 7)
        Self.window.addSubview(decoded)
        decoded.layoutIfNeeded()
        #expect(decoded.numberOfSections(in: decoded.collectionView) == 1)
        #expect(cell(decoded, decoded.indexPathForDate(Date())!)?.configuration.isToday == true)
    }
}
