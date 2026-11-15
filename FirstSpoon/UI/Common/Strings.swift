import Foundation

/// Тексты интерфейса. Источник — `Resources/ru.lproj/Localizable.strings` (генерируется из Android strings.xml
/// скриптом `tools/import_android_assets.py`, ключи те же) и `IOS.strings` (только для iOS, правится руками).
/// Хардкод текстов во View не допускается.
///
/// Интерфейс пока только русский: строки читаем из ru.lproj напрямую, независимо от языка телефона.
enum L {
    private static let bundle: Bundle = Bundle.main.path(forResource: "ru", ofType: "lproj").flatMap(Bundle.init(path:)) ?? .main
    private static let missing = "\u{0}__missing__"

    static func s(_ key: String) -> String {
        let v = bundle.localizedString(forKey: key, value: missing, table: nil)
        if v != missing { return v }
        let ios = bundle.localizedString(forKey: key, value: missing, table: "IOS")
        if ios != missing { return ios }
        assertionFailure("Нет строки \(key)")
        return key
    }

    static func s(_ key: String, _ args: CVarArg...) -> String {
        String(format: s(key), locale: UiLocale.locale, arguments: args)
    }

    /// Plurals по русским правилам (ключи `<name>#one|few|many|other`), независимо от языка телефона.
    static func plural(_ key: String, _ count: Int, _ args: CVarArg...) -> String {
        String(format: s("\(key)#\(UiLocale.pluralCategory(count))"), locale: UiLocale.locale, arguments: args)
    }
}

/// Язык интерфейса для дат и склонений — русский, а не язык телефона.
enum UiLocale {
    static let locale = Locale(identifier: "ru_RU")

    static func pluralCategory(_ n: Int) -> String {
        let n10 = abs(n) % 10, n100 = abs(n) % 100
        if n10 == 1 && n100 != 11 { return "one" }
        if (2...4).contains(n10) && !(12...14).contains(n100) { return "few" }
        return "many"
    }

    private static func formatter(_ pattern: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = locale
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = pattern
        return f
    }
    private static let dayMonth = formatter("d MMMM")
    private static let dayMonthYear = formatter("d MMMM yyyy")
    private static let dayMonthShort = formatter("d MMM")

    private static func date(_ d: FirstSpoonCoreDate) -> Date { Date(timeIntervalSince1970: TimeInterval(d.epochDay) * 86400) }

    /// «14 ноября».
    static func dayMonth(_ d: FirstSpoonCoreDate) -> String { dayMonth.string(from: date(d)) }
    /// «14 ноября 2025».
    static func dayMonthYear(_ d: FirstSpoonCoreDate) -> String { dayMonthYear.string(from: date(d)) }
    /// «14 нояб.».
    static func dayMonthShort(_ d: FirstSpoonCoreDate) -> String { dayMonthShort.string(from: date(d)) }
}

import FirstSpoonCore
typealias FirstSpoonCoreDate = FirstSpoonCore.LocalDate
