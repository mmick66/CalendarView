# Calendar View #

This is an implementation of a calendar component for iOS written in Swift 4.0. It features both vertical and horizontal layout (and scrolling) and the display of native calendar events.

![Calendar Screenshot](https://github.com/mmick66/CalendarView/blob/master/Assets/screenshot.png)

## Installation and Setup

The files needed to be included are in the CalendarView subfolder.

#### Basic Setup

The calendar is a `UIView` and can be added **either programmatically or via a XIB/Storyboard**. It needs a delegate and data source that comply with:

```Swift
protocol CalendarViewDataSource {
    func startDate() -> NSDate // UTC Date
    func endDate() -> NSDate   // UTC Date
}
protocol CalendarViewDelegate {
    func calendar(_ calendar : CalendarView, canSelectDate date : Date) -> Bool /* default implementation */ 
    func calendar(_ calendar : CalendarView, didScrollToMonth date : Date) -> Void
    func calendar(_ calendar : CalendarView, didSelectDate date : Date, withEvents events: [CalendarEvent]) -> Void
    func calendar(_ calendar : CalendarView, didDeselectDate date : Date) -> Void /* default implementation */ 
}
```

The data source will provide the **start date** and the **end date** of the calendar. The methods have a default implementation that will return `Date()` resulting in a single-page calendar displaying the current month. 

The delegate responds to events such as scroll and selection of specific dates.

## How to Use

You would want to implement the delegate functions inside your view controller and as they appear in the example project.

Say you want to be able to scroll 3 months in the past, then:

```Swift
func startDate() -> Date {
    var dateComponents = DateComponents()
    dateComponents.month = -3
    let today = Date()
    let threeMonthsAgo = self.calendarView.calendar.date(byAdding: dateComponents, to: today)
    return threeMonthsAgo
}
```

You probably still want the calendar to open in today's date, so in this case do:

```Swift
override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    let today = Date()
    self.calendarView.setDisplayDate(today, animated: false)        
}
```

Say you want tomorrow to be selected for some reason:

```Swift
// can be in the viewDidAppear
let today = Date()
if let tomorrow = self.calendarView.calendar.date(byAdding: tomorrowComponents, to: today) {
  self.calendarView.selectDate(tomorrow)
}
```

### Selecting and Deselecting Dates

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

### Layout

The calendar supports the two basic layouts set inside the `direction` property as `.horizontal` or `.vertical`.

```Swift
calendarView.direction = .horizontal
```


### Styling

The look of this calendar component is based on a small set of variables set in `CalanderView.Style`.

```Swift
struct Style {
    static var BackgroundColor  : UIColor 
    static var CellColorDefault : UIColor   
    static var CellColorToday   : UIColor 
    static var CellBorderColor  : UIColor 
    static var CellBorderWidth  : CGFloat
    static var HeaderFontName   : String  
    static var HeaderTextColor  : UIColor        
}
```

### Loading Events

This component has the ability to fetch events from the system's `EKEventStore` which is syncronised with the native calendar provided in iOS. 

```Swift
EventsLoader.load(from: self.startDate(), to: self.endDate()) { (granted:Bool, events:[CalendarEvent]) in
    if granted {
        self.calendarView.events = events
    } else {
        // notify that access was not granted
    }
}
```

The code will pop an alert view to ask the user if he will grant access to this app to access the calendar, if it is granted we can pass the events to the `CalendarView`.

## About Dates

Calculating calendar dates can be pretty complicated. This is because time is an absolute scalar value while dates are a fluid human construct. Timezones are arbitrary geopolitical areas and daylight savings times can change according to government decision. The best way out of this is to calculate everything in UTC (which is the same as GTM for what we are concerned). So, the startDate and the endDatet comming from the delegate should all be in UTC (+0000) time.

## Licence 

Copyright (c) 02/04/2015 Michael Michailidis

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
