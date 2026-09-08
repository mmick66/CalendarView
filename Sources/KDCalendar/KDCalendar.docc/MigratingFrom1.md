# Migrating from 1.x

2.0 keeps the 1.x API and changes what happens underneath it.

## Overview

Most 1.x code compiles against 2.0 unchanged. The differences are a higher deployment
target, Swift 6, a value type for styles, a local calendar by default, and system events
moving to their own product.

## Requirements

- iOS 17 or later; Xcode 26.
- Swift 6 language mode. `CalendarViewDataSource` and `CalendarViewDelegate` are
  `@MainActor` and class-bound, and ``CalendarView/delegate`` and
  ``CalendarView/dataSource`` are weak. Keep a strong reference to the objects you
  assign; a view controller that owns the calendar is the usual one.

## Source changes

| 1.x | 2.0 |
| --- | --- |
| `let style = CalendarView.Style()` then `style.cellShape = .round` | `var style = CalendarView.Style()` |
| `CalendarView.Style.Default` | ``CalendarView/Style/default`` (the old name is deprecated) |
| `KDCALENDAR_EVENT_MANAGER_ENABLED` compile flag | `import KDCalendarEventKit` |
| `pod 'KDCalendar/EventManager'` | `pod 'KDCalendar/EventKit'` |
| `EventsManagerError.Authorization` | `EventsManagerError.authorization` |
| `NSCalendarsUsageDescription` | `NSCalendarsFullAccessUsageDescription` |

Mutating a style in place through `calendarView.style.cellColorToday = ...` now
restyles the view, because ``CalendarView/Style`` is a value.

## Behaviour changes

- The default calendar is `Calendar.current` instead of Gregorian in UTC. "Today",
  `selectDate(_:)`, the selected dates and every date passed to the delegate use the
  same calendar, at the start of the day. To keep the 1.x behaviour set
  `style.calendar` to a Gregorian calendar with the UTC time zone.
- ``CalendarView/displayDate`` is the first day of the displayed month, and
  `didScrollToMonth` receives the same value once per month, including the first one
  shown.
- Selection follows one set of rules for taps and for `selectDate(_:)`: the day must be
  in range and allowed by `canSelectDate`; single selection replaces the previous day
  and reports its deselection. `deselectDate(_:)` on a day that is not selected does
  nothing. ``CalendarView/enableDeselection`` only affects taps.
- A start date after the end date shows no months instead of crashing.
- Events mark every day they cover, not only their first day.
- The default colours are dynamic system colours and the default fonts follow Dynamic
  Type. Explicit colours and fonts are used as given.
- `EventsManager` is a `@MainActor` enum with an `async` `load(from:to:)`;
  `loadEvents()` has an `async throws` form and the completion form calls its handler on
  the main actor. Full calendar access is requested, as iOS 17 requires.

## Distribution

Add the package with Swift Package Manager:

```
https://github.com/mmick66/CalendarView
```

The products are `KDCalendar` and, for system events, `KDCalendarEventKit`.
2.0.0 is also the final CocoaPods release. Carthage is no longer supported.
