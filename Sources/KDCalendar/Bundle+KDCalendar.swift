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

    /// The locale of the language ``kdCalendar`` answers in: the app's language where the library
    /// is localized in it, and the library's development language otherwise.
    ///
    /// A count looked up in ``kdCalendar`` takes its plural form by the rules of this locale, so
    /// that the form matches the words. The device's own locale can be in another language, as on
    /// a Croatian device running an app that is in English only, where Croatian rules would pick
    /// "21 event".
    static var kdCalendarLocale: Locale {
        Locale(identifier: kdCalendar.preferredLocalizations.first ?? "en")
    }

    /// The library's strings in the language of `locale`, or `nil` when the library is not
    /// localized in that language.
    ///
    /// ``kdCalendar`` answers in the language of the app. This one answers in the language of a
    /// calendar's own locale, so that the words read out beside a date are in the language the
    /// date is formatted in. Look a count up with `locale` as well: the plural rules come from
    /// the locale, not from the bundle.
    static func kdCalendarStrings(for locale: Locale) -> Bundle? {
        let library = Bundle.kdCalendar
        let preferred = Bundle.preferredLocalizations(from: library.localizations, forPreferences: [locale.identifier])
        // Without a match the first choice is the library's development language, so check that
        // what came back is the locale's language, in its script: Traditional Chinese is not
        // an answer to Simplified.
        guard let name = preferred.first else { return nil }
        let language = Locale.Language(identifier: name)
        guard
            language.languageCode == locale.language.languageCode, language.script == locale.language.script,
            let path = library.path(forResource: name, ofType: "lproj")
        else {
            return nil
        }
        return Bundle(path: path)
    }
}
