import Foundation

/// Календарная дата без часового пояса (аналог `java.time.LocalDate`).
/// Хранится как число дней от 1970-01-01, поэтому арифметика не зависит от часового пояса и DST.
public struct LocalDate: Hashable, Comparable, Sendable, CustomStringConvertible {
    public let epochDay: Int

    public init(epochDay: Int) { self.epochDay = epochDay }

    public init(_ year: Int, _ month: Int, _ day: Int) {
        epochDay = LocalDate.daysFromCivil(year, month, day)
    }

    public var year: Int { LocalDate.civilFromDays(epochDay).0 }
    public var month: Int { LocalDate.civilFromDays(epochDay).1 }
    public var day: Int { LocalDate.civilFromDays(epochDay).2 }

    public func plusDays(_ n: Int) -> LocalDate { LocalDate(epochDay: epochDay + n) }
    public func minusDays(_ n: Int) -> LocalDate { plusDays(-n) }

    /// День недели, где 0 — понедельник … 6 — воскресенье (1970-01-01 был четвергом, поэтому +3).
    public var weekdayMondayBased: Int { ((epochDay + 3) % 7 + 7) % 7 }

    /// Как `LocalDate.plusMonths`: день обрезается до последнего дня месяца (31 янв + 1 мес = 28/29 фев).
    public func plusMonths(_ n: Int) -> LocalDate {
        let (y, m, d) = LocalDate.civilFromDays(epochDay)
        let total = y * 12 + (m - 1) + n
        let ny = Int((Double(total) / 12).rounded(.down))
        let nm = total - ny * 12 + 1
        return LocalDate(ny, nm, min(d, LocalDate.daysInMonth(ny, nm)))
    }
    public func minusMonths(_ n: Int) -> LocalDate { plusMonths(-n) }

    public func atTime(_ time: LocalTime) -> LocalDateTime { LocalDateTime(date: self, time: time) }
    public func atTime(_ hour: Int, _ minute: Int) -> LocalDateTime { atTime(LocalTime(hour, minute)) }

    public func isBefore(_ other: LocalDate) -> Bool { self < other }
    public func isAfter(_ other: LocalDate) -> Bool { self > other }

    /// Как `ChronoUnit.DAYS.between(this, other)`.
    public func daysUntil(_ other: LocalDate) -> Int { other.epochDay - epochDay }

    /// Полных месяцев от `self` до `other` (как `Period.between(...).toTotalMonths()`).
    public func monthsUntil(_ other: LocalDate) -> Int {
        let a = LocalDate.civilFromDays(epochDay), b = LocalDate.civilFromDays(other.epochDay)
        var months = (b.0 * 12 + b.1) - (a.0 * 12 + a.1)
        let days = b.2 - a.2
        if months > 0 && days < 0 { months -= 1 } else if months < 0 && days > 0 { months += 1 }
        return months
    }

    public static func < (l: LocalDate, r: LocalDate) -> Bool { l.epochDay < r.epochDay }

    /// ISO `yyyy-MM-dd`.
    public var description: String {
        let (y, m, d) = LocalDate.civilFromDays(epochDay)
        return String(format: "%04d-%02d-%02d", y, m, d)
    }
    public var iso: String { description }

    public static func parse(_ s: String) -> LocalDate? {
        let p = s.split(separator: "-")
        guard p.count == 3, let y = Int(p[0]), let m = Int(p[1]), let d = Int(p[2]),
              (1...12).contains(m), (1...daysInMonth(y, m)).contains(d) else { return nil }
        return LocalDate(y, m, d)
    }

    /// Сегодня в часовом поясе устройства.
    public static func today(_ now: Date = Date(), calendar: Calendar = .current) -> LocalDate {
        let c = calendar.dateComponents([.year, .month, .day], from: now)
        return LocalDate(c.year!, c.month!, c.day!)
    }

    public static func isLeap(_ y: Int) -> Bool { (y % 4 == 0 && y % 100 != 0) || y % 400 == 0 }
    public static func daysInMonth(_ y: Int, _ m: Int) -> Int {
        switch m {
        case 2: return isLeap(y) ? 29 : 28
        case 4, 6, 9, 11: return 30
        default: return 31
        }
    }

    // Алгоритмы Howard Hinnant (days_from_civil / civil_from_days).
    static func daysFromCivil(_ y0: Int, _ m: Int, _ d: Int) -> Int {
        let y = m <= 2 ? y0 - 1 : y0
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let doy = (153 * (m + (m > 2 ? -3 : 9)) + 2) / 5 + d - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146097 + doe - 719468
    }

    static func civilFromDays(_ z0: Int) -> (Int, Int, Int) {
        let z = z0 + 719468
        let era = (z >= 0 ? z : z - 146096) / 146097
        let doe = z - era * 146097
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
        let y = yoe + era * 400
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        return (m <= 2 ? y + 1 : y, m, d)
    }
}

/// Время суток без даты (часы и минуты), `HH:mm`.
public struct LocalTime: Hashable, Comparable, Sendable, CustomStringConvertible {
    public let minuteOfDay: Int

    public init(_ hour: Int, _ minute: Int) { minuteOfDay = hour * 60 + minute }
    public init(minuteOfDay: Int) { self.minuteOfDay = minuteOfDay }

    public var hour: Int { minuteOfDay / 60 }
    public var minute: Int { minuteOfDay % 60 }

    public func isBefore(_ other: LocalTime) -> Bool { self < other }
    public static func < (l: LocalTime, r: LocalTime) -> Bool { l.minuteOfDay < r.minuteOfDay }
    public var description: String { String(format: "%02d:%02d", hour, minute) }

    public static func parse(_ s: String) -> LocalTime? {
        let p = s.split(separator: ":")
        guard p.count >= 2, let h = Int(p[0]), let m = Int(p[1]), (0..<24).contains(h), (0..<60).contains(m) else { return nil }
        return LocalTime(h, m)
    }
}

/// Дата и время без часового пояса (аналог `java.time.LocalDateTime`, с точностью до минуты).
public struct LocalDateTime: Hashable, Comparable, Sendable, CustomStringConvertible {
    public let date: LocalDate
    public let time: LocalTime

    public init(date: LocalDate, time: LocalTime) { self.date = date; self.time = time }
    public init(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) {
        self.init(date: LocalDate(y, mo, d), time: LocalTime(h, mi))
    }

    var totalMinutes: Int { date.epochDay * 1440 + time.minuteOfDay }
    init(totalMinutes: Int) {
        let day = Int((Double(totalMinutes) / 1440).rounded(.down))
        self.init(date: LocalDate(epochDay: day), time: LocalTime(minuteOfDay: totalMinutes - day * 1440))
    }

    public func toLocalDate() -> LocalDate { date }
    public func toLocalTime() -> LocalTime { time }
    public func plusMinutes(_ n: Int) -> LocalDateTime { LocalDateTime(totalMinutes: totalMinutes + n) }
    public func plusHours(_ n: Int) -> LocalDateTime { plusMinutes(n * 60) }
    public func minusHours(_ n: Int) -> LocalDateTime { plusHours(-n) }
    public func plusDays(_ n: Int) -> LocalDateTime { LocalDateTime(date: date.plusDays(n), time: time) }
    public func minusDays(_ n: Int) -> LocalDateTime { plusDays(-n) }
    public func isBefore(_ o: LocalDateTime) -> Bool { self < o }
    public func isAfter(_ o: LocalDateTime) -> Bool { self > o }

    /// Как `ChronoUnit.DAYS.between(this, other)`: полные сутки, с округлением к нулю.
    public func daysUntil(_ other: LocalDateTime) -> Int { (other.totalMinutes - totalMinutes) / 1440 }

    public static func < (l: LocalDateTime, r: LocalDateTime) -> Bool { l.totalMinutes < r.totalMinutes }
    public var description: String { "\(date)T\(time)" }

    public static func now(_ now: Date = Date(), calendar: Calendar = .current) -> LocalDateTime {
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: now)
        return LocalDateTime(c.year!, c.month!, c.day!, c.hour!, c.minute!)
    }

    /// Момент времени в часовом поясе устройства (для планировщика уведомлений).
    public func toDate(calendar: Calendar = .current) -> Date? {
        calendar.date(from: DateComponents(year: date.year, month: date.month, day: date.day, hour: time.hour, minute: time.minute))
    }
}
