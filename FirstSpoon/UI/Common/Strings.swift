import Foundation
import FirstSpoonCore

/// Тексты интерфейса — только по ключам из String Catalog:
/// - `Resources/Localizable.xcstrings` — генерируется из Android `strings.xml` (ru) и `values-en/strings.xml` (en)
///   скриптом `tools/import_android_assets.py`, ключи те же, что в Android; руками не править;
/// - `Resources/IOS.xcstrings` — строки только для iOS, правится руками.
/// Хардкод текстов во View не допускается.
///
/// Язык — `AppLocale.current()` (ru для русского и языков СНГ, иначе en). Системный выбор iOS здесь не подходит,
/// поэтому строки читаем из `<язык>.lproj` явно.
enum L {
    private static let bundle: Bundle =
        Bundle.main.path(forResource: AppLocale.current().rawValue, ofType: "lproj").flatMap(Bundle.init(path:)) ?? .main
    private static let missing = "\u{0}__missing__"

    static func s(_ key: String) -> String {
        let v = bundle.localizedString(forKey: key, value: missing, table: nil)
        if v != missing { return v }
        let ios = bundle.localizedString(forKey: key, value: missing, table: "IOS")
        if ios != missing { return ios }
        assertionFailure("No string \(key)")
        return key
    }

    static func s(_ key: String, _ args: CVarArg...) -> String {
        String(format: s(key), locale: UiLocale.locale, arguments: args)
    }

    /// Plurals по правилам выбранного языка (ключи `<name>#one|few|many` в ru, `#one|other` в en),
    /// независимо от языка телефона.
    static func plural(_ key: String, _ count: Int, _ args: CVarArg...) -> String {
        String(format: s("\(key)#\(UiLocale.pluralCategory(count))"), locale: UiLocale.locale, arguments: args)
    }
}

/// Язык интерфейса для дат, чисел и склонений — `AppLocale.current()`, а не системная локаль.
enum UiLocale {
    static let language = AppLocale.current()
    static let locale = Locale(identifier: language == .ru ? "ru_RU" : "en_US")

    static func pluralCategory(_ n: Int) -> String {
        switch language {
        case .ru:
            let n10 = abs(n) % 10, n100 = abs(n) % 100
            if n10 == 1 && n100 != 11 { return "one" }
            if (2...4).contains(n10) && !(12...14).contains(n100) { return "few" }
            return "many"
        case .en:
            return n == 1 ? "one" : "other"
        }
    }

    /// Формат по шаблону: порядок частей и падеж — по правилам языка («14 ноября» / «November 14»).
    private static func formatter(_ template: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = locale
        f.timeZone = TimeZone(identifier: "UTC")
        f.setLocalizedDateFormatFromTemplate(template)
        return f
    }
    private static let dayMonth = formatter("dMMMM")
    private static let dayMonthYear = formatter("dMMMMyyyy")
    private static let dayMonthShort = formatter("dMMM")

    private static func date(_ d: LocalDate) -> Date { Date(timeIntervalSince1970: TimeInterval(d.epochDay) * 86400) }

    /// «14 ноября» / «November 14».
    static func dayMonth(_ d: LocalDate) -> String { dayMonth.string(from: date(d)) }
    /// «14 ноября 2025 г.» / «November 14, 2025».
    static func dayMonthYear(_ d: LocalDate) -> String { dayMonthYear.string(from: date(d)) }
    /// Время пробы: «13:00» / «1:00 PM».
    static func time(_ t: LocalTime) -> String {
        timeFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(t.minuteOfDay * 60)))
    }
    private static let timeFormatter = formatter("jmm")

    /// «14 нояб.» / «Nov 14».
    static func dayMonthShort(_ d: LocalDate) -> String { dayMonthShort.string(from: date(d)) }
}
