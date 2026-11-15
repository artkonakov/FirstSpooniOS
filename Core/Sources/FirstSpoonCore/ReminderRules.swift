/// Вид напоминания = правило. Новое правило: значение здесь + ветка в `ReminderRules.plan` + тексты.
public enum ReminderKind: String, CaseIterable, Sendable {
    /// Онбординг пройден, а проб ещё нет.
    case firstEntry = "FIRST_ENTRY"
    /// Есть продукты в серии (1–2 пробы из 3) — пора дать ещё раз.
    case continueSeries = "CONTINUE_SERIES"
}

/// Что известно правилам. Только данные активного ребёнка.
public struct ReminderInput: Sendable {
    public var now: LocalDateTime
    public var enabled: Bool
    /// Когда пройден онбординг; nil — не пройден.
    public var onboardedAt: LocalDateTime?
    public var childName: String
    public var entries: [DiaryEntry]
    public var marks: [String: ProductMark]
    public var productNames: [String: String]

    public init(now: LocalDateTime, enabled: Bool, onboardedAt: LocalDateTime?, childName: String,
                entries: [DiaryEntry], marks: [String: ProductMark], productNames: [String: String]) {
        self.now = now; self.enabled = enabled; self.onboardedAt = onboardedAt; self.childName = childName
        self.entries = entries; self.marks = marks; self.productNames = productNames
    }
}

/// Запланированное напоминание. Тексты собираются по `kind` + `productNames`, поэтому правила — чистый Swift.
public struct PlannedReminder: Hashable, Sendable {
    public let kind: ReminderKind
    public let fireAt: LocalDateTime
    public let childName: String
    /// Для continueSeries: продукты в серии (первый — самый «просроченный»).
    public let productIds: [String]
    public let productNames: [String]

    public init(kind: ReminderKind, fireAt: LocalDateTime, childName: String, productIds: [String] = [], productNames: [String] = []) {
        self.kind = kind; self.fireAt = fireAt; self.childName = childName
        self.productIds = productIds; self.productNames = productNames
    }

    /// Одно напоминание на вид: идентификатор запроса в UNUserNotificationCenter.
    public var id: String { kind.rawValue }
}

/// Правила напоминаний — чистая функция «состояние → какие напоминания должны стоять».
/// Пересчитываются при каждом изменении данных, поэтому не устаревают.
public enum ReminderRules {
    /// Тихие часы: напоминаем только с 9:00 до 20:00.
    public static let dayStart = LocalTime(9, 0)
    public static let dayEnd = LocalTime(20, 0)
    /// Удобное время для «на следующий день».
    public static let morning = LocalTime(10, 0)

    public static let firstEntryDelayHours = 24
    /// Через сколько дней перестаём напоминать.
    public static let firstEntryGiveUpDays = 14
    public static let seriesGiveUpDays = 7

    public static func plan(_ input: ReminderInput) -> [PlannedReminder] {
        guard input.enabled else { return [] }
        return [firstEntry(input), continueSeries(input)].compactMap { $0 }
    }

    private static func firstEntry(_ input: ReminderInput) -> PlannedReminder? {
        guard let onboarded = input.onboardedAt, input.entries.isEmpty else { return nil }
        if onboarded.daysUntil(input.now) >= firstEntryGiveUpDays { return nil }
        let at = schedule(onboarded.plusHours(firstEntryDelayHours), now: input.now)
        return PlannedReminder(kind: .firstEntry, fireAt: at, childName: input.childName)
    }

    private static func continueSeries(_ input: ReminderInput) -> PlannedReminder? {
        let progress = FeedingRules.progressByProduct(input.entries, marks: input.marks)
        var lastTry: [String: LocalDate] = [:]
        for e in input.entries { lastTry[e.productId] = max(lastTry[e.productId] ?? e.date, e.date) }
        let today = input.now.toLocalDate()
        // Порядок словаря в Swift случайный: как в Android, идём по первому появлению продукта в пробах
        // и сортируем по дате устойчиво (при равенстве — порядок появления).
        var order: [String] = []
        var seen = Set<String>()
        for e in input.entries where seen.insert(e.productId).inserted { order.append(e.productId) }
        var candidates: [(id: String, last: LocalDate, order: Int)] = []
        for (i, id) in order.enumerated() where progress[id]?.status == .inProgress {
            guard let last = lastTry[id], last.daysUntil(today) < seriesGiveUpDays else { continue }
            candidates.append((id, last, i))
        }
        candidates.sort { a, b in a.last != b.last ? a.last < b.last : a.order < b.order }
        let inSeries: [(String, LocalDate)] = candidates.map { ($0.id, $0.last) }
        guard let first = inSeries.first else { return nil }
        // Следующий день после самой ранней последней пробы, утром.
        let at = schedule(first.1.plusDays(1).atTime(morning), now: input.now)
        return PlannedReminder(
            kind: .continueSeries, fireAt: at, childName: input.childName,
            productIds: inSeries.map(\.0),
            productNames: inSeries.map { input.productNames[$0.0] ?? $0.0 }
        )
    }

    /// Желаемое время → не в прошлом и не в тихие часы. Просроченное — ближайшее утро.
    public static func schedule(_ wanted: LocalDateTime, now: LocalDateTime) -> LocalDateTime {
        let t = wanted.isAfter(now) ? wanted : nextMorning(now)
        if t.toLocalTime().isBefore(dayStart) { return t.toLocalDate().atTime(morning) }
        if !t.toLocalTime().isBefore(dayEnd) { return t.toLocalDate().plusDays(1).atTime(morning) }
        return t
    }

    private static func nextMorning(_ now: LocalDateTime) -> LocalDateTime {
        let todayMorning = now.toLocalDate().atTime(morning)
        return now.isBefore(todayMorning) ? todayMorning : todayMorning.plusDays(1)
    }
}
