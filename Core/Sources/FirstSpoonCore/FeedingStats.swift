/// Статистика прикорма для экрана по тапу на карточку прогресса на главной.
/// Порт Android `domain/FeedingStats.kt`: чистая функция, статусы считаются по тем же `FeedingRules`,
/// поэтому цифры на двух экранах и на двух платформах не расходятся.
public enum FeedingStats {
    public struct DayBar: Hashable, Sendable {
        public let date: LocalDate
        public let tries: Int
        public let hasReaction: Bool
        /// Продукты, которые давали в этот день (в порядке проб); нужны для картинок на календаре.
        public let productIds: [String]

        public init(date: LocalDate, tries: Int, hasReaction: Bool, productIds: [String]) {
            self.date = date; self.tries = tries; self.hasReaction = hasReaction; self.productIds = productIds
        }
    }

    /// Клетка календаря месяца. `bar` — nil, когда в этот день проб не было (или день соседнего месяца / будущий).
    public struct CalendarCell: Hashable, Sendable {
        public let date: LocalDate
        public let bar: DayBar?
        /// День принадлежит выбранному месяцу (иначе — хвосты из соседних месяцев для заполнения недель).
        public let inMonth: Bool
        /// Позже сегодня (в текущем месяце) — приглушаем, ничего обещать на будущее нельзя.
        public let isFuture: Bool

        public init(date: LocalDate, bar: DayBar?, inMonth: Bool, isFuture: Bool) {
            self.date = date; self.bar = bar; self.inMonth = inMonth; self.isFuture = isFuture
        }
    }

    /// Один месяц: сетка по неделям с понедельника + сводка за настоящие дни месяца.
    public struct MonthGrid: Hashable, Sendable {
        public let year: Int
        public let month: Int
        public let cells: [CalendarCell]
        public let totalTries: Int
        public let activeDays: Int

        /// «2026-11» — стабильный идентификатор месяца.
        public var key: String { String(format: "%04d-%02d", year, month) }

        public init(year: Int, month: Int, cells: [CalendarCell], totalTries: Int, activeDays: Int) {
            self.year = year; self.month = month; self.cells = cells
            self.totalTries = totalTries; self.activeDays = activeDays
        }
    }

    public struct Stats: Sendable {
        /// id продуктов со статусом «введён».
        public let introduced: [String]
        /// id продуктов с реакцией или отметкой «Аллергия» — «Осторожно».
        public let attention: [String]
        /// id продуктов с отметкой «Исключить».
        public let excluded: [String]
        /// Месяцы от первой пробы до текущего, новые сверху (переключение чипами на экране).
        public let months: [MonthGrid]

        public let isEmpty: Bool
    }

    public static func build(entries: [DiaryEntry], marks: [String: ProductMark], today: LocalDate) -> Stats {
        let progress = FeedingRules.progressByProduct(entries, marks: marks)
        // Порядок детерминирован: по первому появлению продукта в пробах, затем отметки по алфавиту (как в Android).
        var order: [String] = []
        var seen = Set<String>()
        for id in entries.map(\.productId) + marks.keys.sorted() where seen.insert(id).inserted { order.append(id) }
        let statuses = order.compactMap { progress[$0] }
        func ids(_ status: ProductStatus) -> [String] { statuses.filter { $0.status == status }.map(\.productId) }

        // Группируем пробы по дням — как в Android.
        let grouped = Dictionary(grouping: entries.filter { $0.date <= today }, by: \.date)
        let dayBars = grouped.mapValues { dayEntries in
            DayBar(
                date: dayEntries[0].date,
                tries: dayEntries.count,
                hasReaction: dayEntries.contains { $0.hasReaction },
                productIds: dayEntries.map(\.productId)
            )
        }

        // Месяцы от первой пробы (или текущего, если проб нет) до сегодня, новые — первыми.
        let start = dayBars.keys.min() ?? today
        var months: [(year: Int, month: Int)] = []
        var y = start.year, m = start.month
        while y * 12 + m <= today.year * 12 + today.month {
            months.append((y, m))
            m += 1
            if m == 13 { m = 1; y += 1 }
        }
        let grids = months.reversed().map { monthGrid(year: $0.year, month: $0.month, dayBars: dayBars, today: today) }

        return Stats(
            introduced: ids(.introduced),
            attention: ids(.reaction) + ids(.allergy),
            excluded: ids(.excluded),
            months: grids,
            isEmpty: entries.isEmpty && marks.isEmpty
        )
    }

    private static func monthGrid(year: Int, month: Int, dayBars: [LocalDate: DayBar], today: LocalDate) -> MonthGrid {
        let daysInMonth = LocalDate.daysInMonth(year, month)
        let first = LocalDate(year, month, 1)
        let last = LocalDate(year, month, daysInMonth)
        let leading = first.weekdayMondayBased
        let cellCount = (leading + daysInMonth + 6) / 7 * 7
        let start = first.minusDays(leading)
        let cells = (0..<cellCount).map { i in
            let d = start.plusDays(i)
            let inMonth = !(d < first || d > last)
            return CalendarCell(date: d, bar: inMonth ? dayBars[d] : nil, inMonth: inMonth, isFuture: d > today)
        }
        return MonthGrid(
            year: year, month: month,
            cells: cells,
            totalTries: cells.reduce(0) { $0 + ($1.bar?.tries ?? 0) },
            activeDays: cells.filter { $0.bar != nil }.count
        )
    }
}
