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
    /// A custom title for the header of `month`.
    ///
    /// - Parameter month: The first day of the month the header shows, in ``CalendarView/calendar``.
    /// - Returns: The title, or `nil` for the default localized month and year.
    func title(forMonth month: Date) -> String?
    /// A custom title for the header of the month containing `date`.
    @available(*, deprecated, renamed: "title(forMonth:)")
    func headerString(_ date: Date) -> String?
}

extension CalendarViewDataSource {
    /// Today.
    public func startDate() -> Date { Date() }
    /// Today.
    public func endDate() -> Date { Date() }
    /// Returns the conformer's ``CalendarViewDataSource/headerString(_:)``.
    ///
    /// Data sources written for 2.1 keep their titles this way until they implement this method.
    public func title(forMonth month: Date) -> String? {
        (LegacyHeaderTitle() as any LegacyTitling).title(of: self, forMonth: month)
    }
    /// `nil`, for the localized month and year.
    @available(*, deprecated, renamed: "title(forMonth:)")
    public func headerString(_ date: Date) -> String? { nil }
}

/// Calls the deprecated ``CalendarViewDataSource/headerString(_:)``.
///
/// Reached through a protocol whose requirement is not deprecated, so that the default
/// `title(forMonth:)` compiles without a deprecation warning.
@MainActor
private protocol LegacyTitling {
    func title(of dataSource: any CalendarViewDataSource, forMonth month: Date) -> String?
}

private struct LegacyHeaderTitle: LegacyTitling {
    @available(*, deprecated)
    func title(of dataSource: any CalendarViewDataSource, forMonth month: Date) -> String? {
        dataSource.headerString(month)
    }
}
