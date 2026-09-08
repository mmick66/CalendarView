import Foundation

extension Bundle {
    /// The bundle holding the library's localized strings: the package resource bundle under
    /// Swift Package Manager, the `KDCalendar` resource bundle under CocoaPods.
    static let kdCalendar: Bundle = {
        #if SWIFT_PACKAGE
        return Bundle.module
        #else
        let host = Bundle(for: CalendarView.self)
        if let url = host.url(forResource: "KDCalendar", withExtension: "bundle"), let bundle = Bundle(url: url) {
            return bundle
        }
        return host
        #endif
    }()
}
