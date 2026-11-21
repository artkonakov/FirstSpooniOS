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
    /// Продукты, содержащие известные аллергены активного ребёнка.
    public var blockedProducts: Set<String>
    /// Малыш готов к прикорму (`FeedingReadiness.canOfferNewFoods`) — иначе «Начнём прикорм?» не шлём.
    public var readyForNewFoods: Bool

    public init(now: LocalDateTime, enabled: Bool, onboardedAt: LocalDateTime?, childName: String,
                entries: [DiaryEntry], marks: [String: ProductMark], productNames: [String: String],
                readyForNewFoods: Bool = true, blockedProducts: Set<String> = []) {
        self.blockedProducts = blockedProducts
        self.now = now; self.enabled = enabled; self.onboardedAt = onboardedAt; self.childName = childName
        self.entries = entries; self.marks = marks; self.productNames = productNames
        self.readyForNewFoods = readyForNewFoods
    }
}

/// Запланированное напоминание. Тексты собираются по `kind` + `productNames`, поэтому правила — чистый Swift.
public struct PlannedReminder: Hashable, Sendable {
    public let kind: ReminderKind
    public let fireAt: LocalDateTime
    public let childName: String
    /// Для continueSeries: активная серия (один продукт — одна серия за раз).
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
        guard let onboarded = input.onboardedAt, input.entries.isEmpty, input.readyForNewFoods else { return nil }
        if onboarded.daysUntil(input.now) >= firstEntryGiveUpDays { return nil }
        let at = schedule(onboarded.plusHours(firstEntryDelayHours), now: input.now)
        return PlannedReminder(kind: .firstEntry, fireAt: at, childName: input.childName)
    }

    /// Напоминание продолжить активную серию — та же логика, что у рекомендаций: одна серия за раз (`Series`),
    /// во время паузы после реакции не напоминаем (напомним в день, когда пауза закончится).
    private static func continueSeries(_ input: ReminderInput) -> PlannedReminder? {
        let today = input.now.toLocalDate()
        guard let active = Series.split(input.entries, marks: input.marks, today: today, blocked: input.blockedProducts).active,
              let last = input.entries.filter({ $0.productId == active }).map(\.date).max(),
              last.daysUntil(today) < seriesGiveUpDays else { return nil }
        let pauseUntil = Series.pauseUntil(input.entries, today: today, pauseDays: Strategies.safety.reactionPauseDays)
        let day = max(last.plusDays(1), pauseUntil ?? last.plusDays(1))
        let at = schedule(day.atTime(morning), now: input.now)
        return PlannedReminder(kind: .continueSeries, fireAt: at, childName: input.childName,
                               productIds: [active], productNames: [input.productNames[active] ?? active])
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
