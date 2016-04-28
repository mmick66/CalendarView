# Calendar View #

This is an implementation of a calendar component for iOS written in Swift.

![Calendar Screenshot](http://s15.postimg.org/b2hmailwr/Screen_Shot_2016_04_11_at_15_52_16_2.png)

### Basic Usage

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

### About Dates

Calculating calendar dates can be pretty complicated. This is because time is an absolute scalar value while dates are a fluid human construct. Timezones are arbitrary geopolitical areas and daylight savings times can change according to government decision. The best way out of this is to calculate everything in UTC (which is the same as GTM for what we are concerned). So, the startDate and the endDatet comming from the delegate should all be in UTC (+0000) time.
