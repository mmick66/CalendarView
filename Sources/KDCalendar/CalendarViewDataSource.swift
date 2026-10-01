import Foundation

/// Provides the range of dates a ``CalendarView`` displays.
///
/// Every month touched by the range is shown in full; days before `startDate()` or after
/// `endDate()` are styled as out of range and cannot be selected.
@MainActor
public protocol CalendarViewDataSource: AnyObject {
    /// The first selectable day. Defaults to today.
    func startDate() -> Date
    /// The last selectable day. Defaults to today.
    func endDate() -> Date
    /// A custom title for the header of the month containing `date`, or `nil` for the default
    /// localized month and year.
    func headerString(_ date: Date) -> String?
}

extension CalendarViewDataSource {
    public func startDate() -> Date { Date() }
    public func endDate() -> Date { Date() }
    public func headerString(_ date: Date) -> String? { nil }
}
