# Changelog

All notable changes to KDCalendar are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [2.0.0] - 2026-09-08

The modernisation release. Swift 6, Swift Package Manager, iOS 17 and up. The
1.x API is kept; see the migration guide in the DocC catalog for the handful
of source changes.

### Added

- `selectionMode` with `.single`, `.multiple` and `.range`, `selectRange(_:)`
  and the `didSelectRange` delegate method. In range mode two taps select
  every selectable day between them, in either order and across months
  (#32). `multipleSelectionEnable` maps to the first two modes.
- `calendar(_:styleForDate:)` on the delegate, a style for one day: colour a
  holiday or grey out the days `canSelectDate` refuses (#136, #122).
- A calendar without a data source shows the current month (#135).
- `KDCalendarView`, a SwiftUI wrapper with a two-way selection binding and
  modifiers for style, direction, events, selection mode, per-day style and
  callbacks (#108).
- `KDCalendarEventKit`, a separate product for system calendar events, with
  `async` `loadEvents()` and `EventsManager.load(from:to:)` (#129).
- `isScrollEnabled` on `CalendarView` (#126).
- `Style.FirstWeekdayOptions.saturday` and `.automatic`, which follows the
  calendar's locale (#134).
- Dark mode through dynamic default colours, Dynamic Type through scaled default
  fonts, and VoiceOver labels and traits on every day.
- `dateRange`, the days the data source spans.
- Swift Package Manager manifest with two products, privacy manifest, DocC
  catalog, GitHub Actions CI, Swift Testing suite with 65 tests.
- Example app on the UIScene lifecycle with three tabs: the classic styled
  calendar, the default style in light and dark mode, and the SwiftUI wrapper.

### Changed

- Minimum deployment target is iOS 17. Swift 6 language mode with `@MainActor`
  isolation for the view, the cell, the header and both protocols.
- `CalendarView.Style` is a `Sendable`, `Equatable` struct. Mutating a style in
  place restyles the view. `Style.Default` is a deprecated alias of
  `Style.default` (#112, #140).
- `CalendarViewDataSource` and `CalendarViewDelegate` are class-bound and held
  weakly, so a view controller that is its calendar's delegate is released.
- The default calendar is `Calendar.current`. Every date the view computes or
  hands out is the start of a day in `style.calendar` (#130, #109, #104).
- `displayDate` and `didScrollToMonth` carry the first day of the displayed
  month; the delegate hears about each month once, including the first one.
- Selection goes through the collection view's own state with one set of rules
  for taps and programmatic calls; single selection reports the deselection of
  the previous day; `enableDeselection` only affects taps.
- Events mark every day they cover.
- The EventKit bridge requests full access, as iOS 17 requires, and no longer
  shifts event times by the local UTC offset. Apps need
  `NSCalendarsFullAccessUsageDescription`.
- The default weekend text colour is readable on the default fill; adjacent
  days have no background and a `quaternaryLabel` number.
- Library, tests and example app are separate: `Sources/`, `Tests/` and
  `Example/`. Carthage is no longer supported.
- CocoaPods: 2.0.0 is the final podspec release, with `Core` and `EventKit`
  subspecs. Use Swift Package Manager.

### Fixed

- Loading system events failed outright on iOS 17 and later (#115, #129).
- A recycled cell kept the previous day's "today", selected and weekend look on
  out-of-range days (#120, #127, #106).
- Selection styling did not show on iOS 15 and later, and multi-selection
  highlighted the wrong days (#140, #142, #59).
- `selectDate(Date())` landed on the UTC day, and month callbacks handed out UTC
  midnight, which local formatters rendered as the previous month (#130, #109).
- The end date was ignored when the range fitted in one month, in the CocoaPods
  release (#131).
- A start date after the end date crashed with `fatalError` (#132).
- A date outside the displayed months produced an invalid index path.
- The optional protocol methods had `internal` default implementations, so
  consumers had to implement all of them (#138, #114).
- `didScrollToMonth` fired for the first month on every reload, from inside
  `cellForItemAt`.
- Rapid `goToNextMonth()` calls snapped the header back to the old month when
  the interrupted animation reported its end (#133, #84).
- `deselectDate(_:)` on an unselected date selected it; `didDeselectDate` was
  sent even when deselection was disabled.
- Non-Gregorian calendars showed Gregorian month and weekday names (#134).
- Setting `events` before the view had a data source crashed.
- `layoutSubviews` reset the scroll offset on every pass.
- `init(frame:)` was not public.
- The Swift package declared iOS 8, put its sources inside the demo folder and
  linked EventKit for every consumer (#139, #116).
- Seven pull requests merged after 1.8.9 were never released, including the
  cell font fix (#147).

## [1.8.9] - 2020-01-20

Last Swift 5 release on iOS 8. The commit that also carries the unreleased
fixes merged up to November 2023 is tagged `1.8.9-legacy`.
