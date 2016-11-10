# Calendar View #

This is an implementation of a calendar component for iOS written in Swift.

![Calendar Screenshot](http://s15.postimg.org/b2hmailwr/Screen_Shot_2016_04_11_at_15_52_16_2.png)

### Installation

The files needed to be included are in the CalendarView subfolder.

The calendar is a UIView subview and can be added either programmatically or via a XIB/Storyboard. It needs a delegate and data source that comply with:

```Swift
@objc protocol CalendarViewDataSource {
    func startDate() -> NSDate? // UTC Date
    func endDate() -> NSDate?   // UTC Date
}
@objc protocol CalendarViewDelegate {
    optional func calendar(calendar : CalendarView, canSelectDate date : NSDate) -> Bool
    func calendar(calendar : CalendarView, didScrollToMonth date : NSDate) -> Void
    func calendar(calendar : CalendarView, didSelectDate date : NSDate, withEvents events: [EKEvent]) -> Void
    optional func calendar(calendar : CalendarView, didDeselectDate date : NSDate) -> Void
}
```

The delegate will provide the start date and the end date of the calendar. The data source responds to events such as scroll and selection of specific dates.

### Basic Usage

You would want to implement the delegate functions inside your view controller and as they appear in the example project.

Say you want to be able to scroll 3 months in the past, then:

```Swift
func startDate() -> Date? {

    var dateComponents = DateComponents()
    dateComponents.month = -3

    let today = Date()

    let threeMonthsAgo = (self.calendarView.calendar as NSCalendar).date(byAdding: dateComponents, to: today, options: NSCalendar.Options())

    return threeMonthsAgo
}
```

You probably still want the calendar to open in today's date, so in this case do:

```Swift
override func viewDidAppear(_ animated: Bool) {

    super.viewDidAppear(animated)

    self.loadEventsInCalendar() // optional

    let today = Date()
    self.calendarView.setDisplayDate(today, animated: false)        
}
```

Say you want tomorrow to be selected for some reason:

```Swift
// can be in the viewDidAppear
let today = Date()
if let tomorrow = (self.calendarView.calendar as NSCalendar).date(byAdding: tomorrowComponents, to: today, options: NSCalendar.Options()) {
  self.calendarView.selectDate(tomorrow)
}
```

### Selecting Dates

You can select dates either by clicking on a cell or by selecting a date programmatically

```Swift
self.calendarView.selectDate(date)
```

Similarly you can deselect

```Swift
self.calendarView.deselectDate(date)
```

You can get all the dates that where selected, either manually or programatically by

```Swift
self.calendarView.selectedDates
```

### About Dates

Calculating calendar dates can be pretty complicated. This is because time is an absolute scalar value while dates are a fluid human construct. Timezones are arbitrary geopolitical areas and daylight savings times can change according to government decision. The best way out of this is to calculate everything in UTC (which is the same as GTM for what we are concerned). So, the startDate and the endDatet comming from the delegate should all be in UTC (+0000) time.
