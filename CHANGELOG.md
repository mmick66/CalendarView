# Changelog

All notable changes to KDCalendar are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

## [2.2.0] - 2026-11-25

### Added

- `CalendarViewDataSource.title(forMonth:)`, which receives the first day of the
  month the header shows. Its default returns `headerString(_:)`, so existing
  data sources keep their titles.
- `KDCalendarView.displayedMonth(_:)`, a two-way binding to the month on screen.
  The calendar sets it to the first day of each month it settles on, and
  assigning a date scrolls to its month, animated inside `withAnimation`, even
  when the user has swiped away from that month. A month outside the range is
  set back to the month on screen.
- `KDCalendarView.mirrorsInRightToLeftLayouts(_:)`. A SwiftUI calendar can now
  mirror in a right-to-left layout, following the layout direction of the
  SwiftUI environment. It is off by default, as before.
- `CalendarView.reloadsEventsWhenStoreChanges` (KDCalendarEventKit), off by
  default. When on, a view that has loaded events loads them again after its
  store reports a change, such as an edit in the Calendar app. Changes reported
  close together or during a load start one query, and a reload never asks for
  calendar access.
- `CalendarEventStore.changeNotification`, the notification a store posts when
  its events change. It defaults to `nil`, so existing stores still conform;
  `EKEventStore` returns `EKEventStoreChanged`.
- Localisations of the VoiceOver strings in Catalan, Czech, Danish, Dutch,
  Finnish, French, German, Greek, Hungarian, Indonesian, Italian, Japanese,
  Korean, Norwegian Bokmål, Polish, Portuguese, Romanian, Russian, Spanish,
  Swedish, Turkish, Ukrainian and Simplified and Traditional Chinese.

### Changed

- `EventsManager` is a struct around one `CalendarEventStore` instead of an enum
  of static methods that each took a `store` argument. `EventsManager.shared`
  uses the system event store, and `EventsManager(store:)` another one, such as
  a test double. `CalendarView.eventsManager`, `EventsManager.shared` by
  default, is the manager `loadEvents()`, `saveEvent(_:)` and
  `addEvent(_:date:duration:)` use.

- Every public declaration has a documentation comment, and the lint keeps it
  that way. The closures of the SwiftUI modifiers and of
  `loadEvents(onComplete:)` name their parameters, such as
  `onLongPress(_ action: (_ date: Date, _ events: [CalendarEvent]) -> Void)`.

- `didScrollToMonth` is also sent when a reload leaves the calendar on another
  month. `didDeselectDate` for days a reload drops arrives once the view shows
  the whole reload.
- Setting `style`, `events`, `marksWeekends` or `direction` to the value it
  already has no longer reloads. Styles compare by value, and a colour made
  with `UIColor { traits in ... }` equals only itself: the documentation of
  `CalendarView.Style` explains how to create such colours once, so that a
  style built in a SwiftUI `body` does not reload the calendar on every update.
- The delegate's `canSelectDate`, and the `KDCalendarView.canSelect(_:)`
  predicate, are asked for each day as it is drawn as well as for taps and
  selections in code, and again for the days on screen at the layout that
  follows a change of the selection, so that VoiceOver knows which days are
  refused. Keep them quick and free of side effects, and call `reloadData()`
  when the answers change for another reason than the selection.
- `Style.headerHeight` and `Style.weekdaysHeight` are minimums: the header is
  taller when its fonts need more room.
- The weekday labels use the stand-alone weekday symbols, as column headings
  do: "Mo" rather than "Mo." in German.
- Setting `events` no longer asks the calendar about every day of every event.
  Twenty events spanning a 100-year range took about 7 seconds to index and now
  take well under 0.2 seconds.
- A `KDCalendarView` is set up with one reload, and an update that changes
  several modifier values at once (style, range, direction, weekend marking,
  events) reloads the calendar once instead of once per value. An update sets
  on the calendar only the values that changed since the last one, where it
  used to set `allowsDeselection` and `scrollEnabled` every time.
- `KDCalendarView.displayDate(_:)` treats `nil` as no request, so a date that
  follows `nil` scrolls again, even to the same month as before.
- The log message for an invalid data source range shows its dates instead of
  `<private>`.
- The documentation says more: `calendar(_:didLongPressDate:withEvents:)`
  states that a long press is reported for days that cannot be selected, such
  as days out of range; `CalendarEvent` and its `endDate` say which days an
  event marks (an event that ends exactly at midnight does not mark the day
  that starts then, and an event with no length still marks its day); and
  `KDCalendarView.range` says that its ends are moments, read as days in the
  style's calendar at each reload.
- The EventKit bridge keeps a view's manager and load state in one object
  instead of three associated objects. No behaviour change.

### Deprecated

- `Style.CellShapeOptions`, `Style.FirstWeekdayOptions`, `Style.WeekDaysTransform`
  and `Style.weekDayTransform`, renamed `Style.CellShape`, `Style.FirstWeekday`,
  `Style.WeekdayCasing` and `Style.weekdayCasing`. The old names still compile,
  with a fix-it.

- The static `EventsManager.store`, `hasFullAccess`, `load(from:to:store:)`,
  `save(_:store:)` and `add(event:store:)`, and the `store` argument of
  `CalendarView.loadEvents`, `saveEvent` and `addEvent`. Use
  `EventsManager.shared` or set `CalendarView.eventsManager` instead.
- `CalendarViewDataSource.headerString(_:)`. Implement `title(forMonth:)`
  instead; `headerString(_:)` will be removed in 3.0.

### Fixed

- `selectRange(_:)` dropped the selected days outside the new range without
  telling the delegate, and a range with no selectable day emptied the
  selection silently. The delegate now receives `didDeselectDate` for each day
  dropped, before `didSelectRange`, as it does when a tap or the selection mode
  drops days.
- Overlapping `loadEvents()` calls assigned their events in the order their
  queries finished, so an earlier load, such as one for the range before the
  data source changed it, could overwrite a later one. The latest call wins
  now: a load that a later one supersedes leaves `events` alone and throws
  `CancellationError`, which the completion form passes to its handler.
- An event saved with `saveEvent(_:)` or `addEvent(_:date:duration:)` while a
  `loadEvents()` query was running lost its dot when the load assigned a result
  that did not contain it. The load now keeps the events saved while it ran.
- A `KDCalendarView` selection binding applied after the device changed time
  zone, but before the calendar reloaded, could select the day before or after
  the one shown. The view now computes every date in the calendar its grid is
  laid out in until the reload moves the grid, the selection and the month
  titles to the new time zone together.
- After `reloadData()`, or any change that reloads, the calendar stays on the
  month it displayed, wherever the new range puts it, and moves to the nearest
  month when that month is no longer in range. `displayDate`, the title and the
  scroll position now agree, and `goToNextMonth()` and `goToPreviousMonth()`
  keep working after the range changes. Before, a range that gained earlier
  months showed another month under the old title.
- Assigning a data source after the first layout displays a month of its range
  with the right title.
- A time zone change keeps the displayed month, with `displayDate` on the first
  day of that month in the new zone.
- The header title follows a new `style.locale`, and the data source's
  `title(forMonth:)` is asked again after every reload.
- A vertical calendar stays on its month when the header changes height, with
  the text size or with `Style.headerHeight`.
- Month titles capitalise only their first letter: "Enero de 2024", not "Enero
  De 2024". A title that starts with the year is left as the locale writes it,
  such as "2024. január".
- The month title names the era in calendars that need one to name a year: a
  Japanese calendar shows "January Reiwa 6" rather than "January 6", and a
  Chinese calendar the year it started in.
- The right-to-left layout no longer depends on setting `forceLtr` after
  `semanticContentAttribute`, and follows later changes of the view's layout
  direction.
- A calendar that is right to left from its first layout opens on its first
  month, not its last.
- The today marker moves at midnight in `style.calendar`, also when that
  calendar is in another time zone than the device, and also when the device
  slept until then.
- A month whose first day has no midnight no longer breaks the grid (for
  example October 2023 in `America/Asuncion`, where daylight saving time starts
  at 00:00 on the 1st). Its days were handed out at 01:00 instead of the start
  of the day, days of later months resolved to the cells of the month before
  (`selectDate` selected a day a month early), and the last day of the range
  was out of range.
- Setting `multipleSelectionEnable` to `true` leaves `.range` mode alone
  instead of switching it to `.multiple`; only `.single` becomes `.multiple`,
  and `false` still means `.single`.
- A custom `Style.calendar` whose time zone is `TimeZone.autoupdatingCurrent`,
  or whose locale is `Locale.autoupdatingCurrent`, now follows a change of the
  device's settings at the next reload, as `Calendar.autoupdatingCurrent` does.
  Until then the grid's dates and the selection no longer drift to the new time
  zone.
- The header grows to fit its fonts at the larger Dynamic Type sizes instead of
  clipping the month title and the weekday labels.
- Weekday labels show one-letter names when the short ones do not fit their
  columns, and day numbers shrink to fit their cells, instead of truncating or
  clipping.
- VoiceOver reads "Today" and the number of events in the language of
  `Style.locale`, the language the date is read in, rather than in the app's
  language. In a language the library has no strings for, the words are the
  app's and the count now takes its plural form by that language's rules, not
  the device's.
- Days the delegate's `canSelectDate` refuses are announced as dimmed buttons
  by VoiceOver, like days out of range.
- VoiceOver reads the weekday labels as full weekday names.
- `KDCalendarView.displayDate(_:)` compared instants, so `.displayDate(Date())`
  scrolled back to the current month every time the body ran, undoing the
  user's swipes. It now scrolls only when the value moves to another month. The
  demo and the README example bind the month with `displayedMonth(_:)` instead.
- A `KDCalendarView` selection no longer shifts by a day after the device, or
  the style's calendar, moves to another time zone. The selection binding now
  follows the view to the new zone's midnights, where it used to keep the old
  instants and select the day before on the next update.
- `loadEvents(onComplete:)` never called its handler when the view was released
  before the load started. The handler is now always called exactly once, with
  `CancellationError` in that case.

## [2.1.0] - 2026-09-30

### Added

- `CalendarEventStore`, the part of `EKEventStore` the EventKit bridge uses.
  Every EventKit call takes a `store` argument, defaulting to the shared
  `EventsManager.store`, so a test double can stand in. The bridge has tests
  now.
- `EventsManager.save(_:store:)` and `CalendarView.saveEvent(_:store:)`, which
  throw `EventsManagerError.authorization` without access, or the store's own
  error when it refuses the event. `add(event:)` and `addEvent(_:date:duration:)`
  still return `false` for either.
- `Style.resolvedCalendar`: `Style.calendar`, given `Style.locale` when it has
  no locale of its own. `CalendarView.calendar` returns it.
- `CalendarEvent` is `Equatable` and `Hashable`, comparing title, start and end
  date, so apps can diff or deduplicate their events.

### Changed

- Right to left, `CalendarFlowLayout` mirrors the cell frames instead of the
  view scaling its collection view, and every cell, by -1. No view carries a
  transform any more, so hit-testing and snapshots see the real frames. The
  collection view's `semanticContentAttribute` follows `forceLtr`.

### Fixed

- Cell borders kept their old colour when Increase Contrast (or another trait
  a dynamic colour can depend on, besides light and dark mode) changed. They
  are reapplied on any trait change that affects colour appearance now.
- With `showAdjacentDays` on, the cells before the first month stayed empty
  while the cells after the last month showed the next month's days. The first
  month now shows the end of the previous month too.
- `loadEvents()` and `EventsManager.load(from:to:)` reported an error thrown
  while asking for calendar access as `EventsManagerError.authorization`. They
  throw that error now.
- A dynamic `cellBorderColor` or `cellSelectedBorderColor` could take the
  wrong appearance, because it was resolved against whatever trait collection
  was current rather than the cell's. Day cells now resolve it against their
  own traits.
- `loadEvents()` queried EventKit on the main thread, which could hitch
  scrolling for a long range or a busy calendar. `EKEventStore` now runs the
  query off the main actor, and `CalendarEventStore.events(from:to:)` is
  `async`.
- The default `Style.calendar` and `Style.locale` were snapshots of the user's
  settings taken at launch, so after the device changed time zone "today" and
  the grid stayed in the old zone. They are `Calendar.autoupdatingCurrent` and
  `Locale.autoupdatingCurrent` now, and the view rebuilds its grid, keeping the
  selected days, when the time zone changes.
- Assigning `dataSource` kept a grid built before it, such as the current month
  alone built when `style` was set first. Until the next reload or layout,
  `setDisplayDate`, `selectDate` and `indexPathForDate` ignored the data
  source's days. Assigning a data source now reloads the calendar from it.
- At some sizes that are not a whole number of cells, such as a width of
  258⅓ points, the grid lost days: `CalendarFlowLayout` moved each day into
  its page but kept the flow layout's content size and its choice of visible
  cells, and the flow wrapped six days to a row. The content was then not a
  whole number of pages and days on screen were left blank. The layout now
  computes both from the page grid.
- A drag released without deceleration, such as one let go exactly on a page,
  left the header and `didScrollToMonth` on the old month. The view now reports
  the month when such a drag ends.
- `firstWeekday = .automatic` ignored `Style.locale` when `Style.calendar` had
  no locale, as a calendar made with `Calendar(identifier:)` has none: weeks
  started on Sunday whatever the locale. It follows the locale now, as weekends
  already did.
- `setDisplayDate(_:animated: true)` never reported `didScrollToMonth` when the
  view had no size yet or the month was already on screen, because UIKit sends
  no end-of-animation callback when the offset does not move. SwiftUI's
  `onScrollToMonth` missed the first month of an animated update this way. Such
  scrolls now report at once, as non-animated ones do.
- `loadEvents()` stopped at the start of the last day of the range, so events
  later on that day were missed.
- `loadEvents()` missed every event after the first four years of a longer
  range, because EventKit shortens a query to four years. The `EKEventStore`
  bridge now queries such a range in chunks.
- The header did not mirror when a calendar was right-to-left on its own
  rather than through the app's layout direction.
- A `CalendarView` decoded from an archive crashed in the header's
  `init(coder:)`; the view, header and cells now decode and rebuild themselves.
- The selection was stored as index paths that went stale when the grid was
  rebuilt: after the range gained or lost a month, the first weekday changed or
  the time zone changed, another day was highlighted, `deselectDate` did
  nothing, and a grid that lost months crashed on reload. The selection is kept
  as days now and `selectedIndexPaths` is derived from the current grid. A
  reload deselects the days that left the range and tells the delegate with
  `didDeselectDate`.
- `KDCalendarView` replayed an assigned selection as taps, so in `.range` mode
  a week became its last day and in `.single` mode several days showed only
  the last while the binding kept them all. The binding is now applied as a
  whole in the shape of the selection mode, and set to the days the calendar
  shows when they differ.
- A reused cell kept the VoiceOver label of the day it showed before, so with
  `showAdjacentDays` a neighbouring month's day was read out as another date.
  Reuse clears the label, and VoiceOver skips adjacent days, which cannot be
  selected.
- Changing `selectionMode` dropped selected days without telling the delegate:
  switching to `.single` keeps only the last day and switching to `.range`
  clears the selection. The delegate now receives `didDeselectDate` for each
  day dropped. `KDCalendarView` drops them from the binding too, where it used
  to reapply them in the new mode's shape, so switching to `.range` filled the
  days between them; a selection set together with the new mode still wins.
- `selectRange` walked every day between its bounds, so a range with far-off
  ends such as `Date.distantPast...Date.distantFuture` blocked the main thread.
  It walks only the days in range now.
- A tap that replaced the selection, in `.single` mode or when starting a new
  range, reported the dropped days with `didDeselectDate` while the view showed
  no selection at all. The delegate now hears once the view shows the new
  day, as it does when the selection mode changes.

## [2.0.1] - 2026-09-08

### Fixed

- An event with a far-off end date, such as an open-ended system event, was
  bucketed day by day over its whole span and could block the main thread for
  seconds. Bucketing is clamped to the displayed months.
- The data source was asked for its range on every cell (about 150 calls per
  reload); it is asked once per reload.
- The today marker did not move at midnight or after a clock or time zone
  change; the view reloads on `NSCalendarDayChanged` and
  `significantTimeChangeNotification`.
- Weekends ignored `style.locale` when `style.calendar` had no locale, so a
  Saudi calendar marked Sunday instead of Friday. `CalendarView.calendar` now
  carries the style's locale in that case.

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
