# ``KDCalendar``

A month calendar for UIKit and SwiftUI that scrolls one month per page and marks days with events.

## Overview

``CalendarView`` shows every month between the two dates its data source returns. Days
outside that range are greyed out and cannot be selected. Pages scroll horizontally or
vertically; a header shows the localized month and the weekday names.

```swift
let calendarView = CalendarView(frame: .zero)
calendarView.dataSource = self   // startDate() and endDate()
calendarView.delegate = self     // didSelectDate, didScrollToMonth, ...
calendarView.style.cellShape = .round
calendarView.setDisplayDate(Date())
```

Every date the view hands out is the start of a day in ``CalendarView/calendar``, which
defaults to the user's current calendar and time zone. Set ``CalendarView/Style/calendar``
for another calendar, time zone or first weekday.

The selected days and the displayed month are state that a reload keeps. After
``CalendarView/reloadData()``, a new style or a new data source, the same days stay selected
and the calendar stays on the month it displayed, wherever the new range puts them. Days that
left the range are deselected, and when the month left it the calendar moves to the nearest
one; the delegate hears of both.

The header grows with its fonts at the larger Dynamic Type sizes, and VoiceOver reads each
day in the language of ``CalendarView/Style/locale``, with the days that cannot be selected
as dimmed buttons. The grid mirrors in right-to-left layouts when ``CalendarView/forceLtr``
is `false`.

In SwiftUI, ``KDCalendarView`` wraps the same view with two-way bindings: one for the
selection and, with ``KDCalendarView/displayedMonth(_:)``, one for the month on screen.

System calendar events come from the separate `KDCalendarEventKit` product, which adds
`loadEvents()` and `addEvent(_:date:duration:)` to ``CalendarView``, and
`reloadsEventsWhenStoreChanges` to load them again when the user's calendar changes. Apps
that never import it do not link EventKit.

## Topics

### The calendar

- ``CalendarView``
- ``CalendarViewDataSource``
- ``CalendarViewDelegate``

### Appearance

- ``CalendarView/Style``

### Events

- ``CalendarEvent``

### SwiftUI

- ``KDCalendarView``

### Migrating

- <doc:MigratingFrom1>
