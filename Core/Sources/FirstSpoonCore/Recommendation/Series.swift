/// Одна серия за раз (Android `docs/product-rules.md` «Серия: одна за раз», решение А1). Порт Android `Series.kt`.
/// Общая логика для движка рекомендаций (`Facts`) и напоминаний (`ReminderRules`) — чтобы они не расходились.
public enum Series {
    public struct Split: Hashable, Sendable {
        public let active: String?
        public let queued: [String]
    }

    /// Активная — больше всего проб, при равенстве начатая раньше (затем id). Исключение: продукт давали два дня подряд
    /// (сегодня+вчера или вчера+позавчера) — родитель выбрал его сам, активен он.
    public static func split(_ entries: [DiaryEntry], marks: [String: ProductMark], today: LocalDate) -> Split {
        let progress = FeedingRules.progressByProduct(entries, marks: marks)
        // Порядок как у LinkedHashMap в Android: по первому появлению в пробах, затем отметки.
        var order: [String] = []
        var seen = Set<String>()
        for id in entries.map(\.productId) + marks.keys.sorted() where seen.insert(id).inserted { order.append(id) }
        let inSeries = order.filter { progress[$0]?.status == .inProgress }
        guard !inSeries.isEmpty else { return Split(active: nil, queued: []) }

        var days: [String: Set<LocalDate>] = [:]
        for e in entries { days[e.productId, default: []].insert(e.date) }
        func twoDaysInRow(_ id: String) -> Bool {
            let d = days[id] ?? []
            return (d.contains(today) && d.contains(today.minusDays(1))) || (d.contains(today.minusDays(1)) && d.contains(today.minusDays(2)))
        }
        func before(_ a: String, _ b: String) -> Bool {
            let ta = progress[a]?.tries ?? 0, tb = progress[b]?.tries ?? 0
            if ta != tb { return ta > tb }
            let fa = days[a]?.min() ?? today, fb = days[b]?.min() ?? today
            if fa != fb { return fa < fb }
            return a < b
        }
        // Как maxByOrNull в Kotlin: при равенстве — первый по порядку.
        var twoDays: String?
        for id in inSeries where twoDaysInRow(id) {
            if let cur = twoDays, (days[cur]?.max() ?? today) >= (days[id]?.max() ?? today) { continue }
            twoDays = id
        }
        let sorted = inSeries.sorted(by: before)
        let active = twoDays ?? sorted[0]
        return Split(active: active, queued: sorted.filter { $0 != active })
    }

    /// До какого дня (не включая) действует пауза после реакции «Плохо»/«Сомнительно»; nil — паузы нет.
    public static func pauseUntil(_ entries: [DiaryEntry], today: LocalDate, pauseDays: Int) -> LocalDate? {
        guard let last = entries.filter({ $0.reaction == .reaction || $0.reaction == .unsure }).map(\.date).max() else { return nil }
        let until = last.plusDays(pauseDays)
        return today.isBefore(until) ? until : nil
    }
}
