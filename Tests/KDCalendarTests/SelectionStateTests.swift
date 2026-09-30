import Foundation
import Testing

@testable import KDCalendar

/// The selection rules on their own, with no view: taps, deselection, mode changes, assignment
/// and the days each change adds and removes.
struct SelectionStateTests {

    let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        utc.date(from: DateComponents(year: year, month: month, day: day))!
    }

    /// Every day of `range` in January 2024, except `refused`.
    private func january(except refused: Set<Int> = []) -> SelectionState.SelectableDays {
        { range in
            (1...31).map { date(2024, 1, $0) }.filter {
                range.contains($0) && !refused.contains(utc.component(.day, from: $0))
            }
        }
    }

    private func state(_ mode: CalendarView.SelectionMode) -> SelectionState {
        var state = SelectionState()
        _ = state.setMode(mode)
        return state
    }

    @Test func multipleModeAddsEachTapAndDropsEachDeselection() {
        var state = state(.multiple)
        #expect(state.tap(date(2024, 1, 10), selectable: january()) == .init(selected: [date(2024, 1, 10)]))
        #expect(state.tap(date(2024, 1, 5), selectable: january()) == .init(selected: [date(2024, 1, 5)]))
        #expect(state.days == [date(2024, 1, 10), date(2024, 1, 5)])
        #expect(state.tap(date(2024, 1, 5), selectable: january()) == nil, "a selected day changes nothing")

        #expect(state.deselect(date(2024, 1, 10)) == .init(deselected: [date(2024, 1, 10)]))
        #expect(state.deselect(date(2024, 1, 20)) == .init())
        #expect(state.days == [date(2024, 1, 5)])
    }

    @Test func singleModeReplacesTheDay() {
        var state = state(.single)
        _ = state.tap(date(2024, 1, 10), selectable: january())
        let change = state.tap(date(2024, 1, 12), selectable: january())
        #expect(change == .init(selected: [date(2024, 1, 12)], deselected: [date(2024, 1, 10)]))
        #expect(state.days == [date(2024, 1, 12)])
    }

    @Test func rangeModePairsTapsIntoRanges() {
        var state = state(.range)
        #expect(state.tap(date(2024, 1, 12), selectable: january()) == .init(selected: [date(2024, 1, 12)]))
        #expect(state.rangeStart == date(2024, 1, 12))

        // The second tap fills in the selectable days between the ends, in either order.
        let change = state.tap(date(2024, 1, 8), selectable: january(except: [10]))
        #expect(change?.selected == [date(2024, 1, 8), date(2024, 1, 9), date(2024, 1, 11)])
        #expect(change?.completedRange == date(2024, 1, 8)...date(2024, 1, 12))
        #expect(state.days == [date(2024, 1, 12), date(2024, 1, 8), date(2024, 1, 9), date(2024, 1, 11)])
        #expect(state.rangeStart == nil)

        // A third tap starts a new range and drops the old one.
        let restart = state.tap(date(2024, 1, 20), selectable: january())
        #expect(restart?.deselected == [date(2024, 1, 12), date(2024, 1, 8), date(2024, 1, 9), date(2024, 1, 11)])
        #expect(restart?.completedRange == nil)
        #expect(state.days == [date(2024, 1, 20)])
        #expect(state.rangeStart == date(2024, 1, 20))
    }

    @Test func deselectingInRangeModeClearsTheRange() {
        var state = state(.range)
        _ = state.tap(date(2024, 1, 2), selectable: january())
        _ = state.tap(date(2024, 1, 4), selectable: january())
        let change = state.deselect(date(2024, 1, 3))
        #expect(change.deselected == [date(2024, 1, 2), date(2024, 1, 3), date(2024, 1, 4)])
        #expect(state.days == [])

        _ = state.tap(date(2024, 1, 9), selectable: january())
        _ = state.deselect(date(2024, 1, 9))
        #expect(state.rangeStart == nil, "a cleared range start leaves nothing waiting")
    }

    @Test func changingTheModeDropsWhatTheNewModeCannotHold() {
        var state = state(.multiple)
        for day in [8, 10, 12] {
            _ = state.tap(date(2024, 1, day), selectable: january())
        }
        #expect(state.setMode(.multiple) == .init())
        #expect(state.setMode(.single) == .init(deselected: [date(2024, 1, 8), date(2024, 1, 10)]))
        #expect(state.setMode(.multiple) == .init())
        #expect(state.setMode(.range) == .init(deselected: [date(2024, 1, 12)]))
        #expect(state.days == [])
    }

    @Test func aProgrammaticRangeIsComplete() {
        var state = state(.range)
        _ = state.tap(date(2024, 1, 3), selectable: january())
        let change = state.replace(with: [date(2024, 1, 5), date(2024, 1, 6)])
        #expect(change == .init(selected: [date(2024, 1, 5), date(2024, 1, 6)], deselected: [date(2024, 1, 3)]))
        #expect(state.rangeStart == nil)
        #expect(state.tap(date(2024, 1, 20), selectable: january())?.completedRange == nil)
    }

    @Test func assigningShapesTheDaysToTheMode() {
        let requested = [date(2024, 1, 12), date(2024, 1, 8), date(2024, 1, 10), date(2024, 1, 12)]

        var multiple = state(.multiple)
        _ = multiple.assign(requested, selectable: january(except: [10]))
        #expect(multiple.days == [date(2024, 1, 12), date(2024, 1, 8)], "in order, once, and allowed")

        var single = state(.single)
        _ = single.assign(requested, selectable: january(except: [10]))
        #expect(single.days == [date(2024, 1, 8)])

        var range = state(.range)
        _ = range.assign(requested, selectable: january(except: [10]))
        #expect(range.days == [date(2024, 1, 8), date(2024, 1, 9), date(2024, 1, 11), date(2024, 1, 12)])
        #expect(range.rangeStart == nil)

        // A lone day is the first end of a range the next tap completes.
        _ = range.assign([date(2024, 1, 20)], selectable: january())
        #expect(range.rangeStart == date(2024, 1, 20))
        #expect(
            range.tap(date(2024, 1, 21), selectable: january())?.completedRange == date(2024, 1, 20)...date(2024, 1, 21)
        )
    }

    @Test func retainingDropsTheRangeStartWithItsDay() {
        var state = state(.range)
        _ = state.tap(date(2024, 1, 3), selectable: january())
        let change = state.retain { $0 != date(2024, 1, 3) }
        #expect(change == .init(deselected: [date(2024, 1, 3)]))
        #expect(state.rangeStart == nil)
    }

    @Test func movingCarriesTheRangeStart() {
        var state = state(.range)
        _ = state.tap(date(2024, 1, 3), selectable: january())
        state.move { $0.addingTimeInterval(3600) }
        #expect(state.days == [date(2024, 1, 3).addingTimeInterval(3600)])
        #expect(state.rangeStart == date(2024, 1, 3).addingTimeInterval(3600))
    }
}
