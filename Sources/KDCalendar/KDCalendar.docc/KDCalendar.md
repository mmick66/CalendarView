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

In SwiftUI, ``KDCalendarView`` wraps the same view with a two-way selection binding.

System calendar events come from the separate `KDCalendarEventKit` product, which adds
`loadEvents()` and `addEvent(_:date:duration:)` to ``CalendarView``. Apps that never
import it do not link EventKit.

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
