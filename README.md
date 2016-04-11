# KDCalendar #

This is an implementation of a calendar component for iOS written in Swift.

![Calendar Screenshot](http://s15.postimg.org/b2hmailwr/Screen_Shot_2016_04_11_at_15_52_16_2.png)

### Basci Usage

The files needed to be included are in the CalendarView subfolder. 

The calendar is a UIView subview and can be added either programmatically or via a XIB/Storyboard. It needs a delegate and data source that comply with: 

```Swift
@objc protocol CalendarViewDataSource {
    func startDate() -> NSDate?
    func endDate() -> NSDate?
}
@objc protocol CalendarViewDelegate {
    optional func calendar(calendar : CalendarView, canSelectDate date : NSDate) -> Bool
    func calendar(calendar : CalendarView, didScrollToMonth date : NSDate) -> Void
    func calendar(calendar : CalendarView, didSelectDate date : NSDate, withEvents events: [EKEvent]) -> Void
    optional func calendar(calendar : CalendarView, didDeselectDate date : NSDate) -> Void
}
```

The delegate will provide the start date and the end date of the calendar. The data source responds to events such as scroll and selection of specific dates.
