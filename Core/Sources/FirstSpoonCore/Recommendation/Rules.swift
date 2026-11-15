/// Три вида правил. Новое правило = значение `Gate`/`Filter`/`Scorer` в `Rules` + строка в
/// `RecommendationConfig.defaultRules` + тест.
///
/// - `Gate`: приоритетная ситуация, которая решает всё сама (серия, пауза). Первая сработавшая побеждает.
/// - `Filter`: убирает продукт из кандидатов с причиной.
/// - `Scorer`: добавляет баллы (с причиной) — продукт с максимумом побеждает.
public enum Rule: Sendable {
    case gate(Gate)
    case filter(Filter)
    case scorer(Scorer)

    public var name: String {
        switch self {
        case .gate(let g): return g.name
        case .filter(let f): return f.name
        case .scorer(let s): return s.name
        }
    }
}

public struct Gate: Sendable {
    public let name: String
    let body: @Sendable (Facts, RecommendationConfig) -> Recommendation?
    public init(_ name: String, _ body: @escaping @Sendable (Facts, RecommendationConfig) -> Recommendation?) { self.name = name; self.body = body }
    public func decide(_ f: Facts, _ c: RecommendationConfig) -> Recommendation? { body(f, c) }
}

public struct Filter: Sendable {
    public let name: String
    let body: @Sendable (Product, Facts, RecommendationConfig) -> Reason?
    public init(_ name: String, _ body: @escaping @Sendable (Product, Facts, RecommendationConfig) -> Reason?) { self.name = name; self.body = body }
    public func exclude(_ p: Product, _ f: Facts, _ c: RecommendationConfig) -> Reason? { body(p, f, c) }
}

public struct Scorer: Sendable {
    public let name: String
    let body: @Sendable (Product, Facts, RecommendationConfig) -> Contribution?
    public init(_ name: String, _ body: @escaping @Sendable (Product, Facts, RecommendationConfig) -> Contribution?) { self.name = name; self.body = body }
    public func score(_ p: Product, _ f: Facts, _ c: RecommendationConfig) -> Contribution? { body(p, f, c) }
}

public enum Rules {
    // ---------- Gates ----------

    /// После «Плохо»/«Сомнительно» новые продукты не вводим N дней.
    public static let pauseAfterReaction = Gate("PauseAfterReaction") { f, c in
        guard let r = f.lastReaction else { return nil }
        let until = r.date.plusDays(c.reactionPauseDays)
        guard f.ctx.today.isBefore(until) else { return nil }
        return .wait(until: until, productId: r.productId, reasons: [Reason(.PAUSE_AFTER_REACTION, [r.productId, until.iso])])
    }

    /// Есть незаконченная серия — сначала её. Самая «старая» (давнее всего пробовали) — первой.
    public static let continueSeries = Gate("ContinueSeries") { f, _ in
        var best: (String, LocalDate)?
        for id in f.inSeries {
            let d = f.lastTry[id] ?? f.ctx.today
            if best == nil || d < best!.1 { best = (id, d) }
        }
        guard let id = best?.0 else { return nil }
        let tries = f.progress[id]?.tries ?? 0
        return .continueSeries(productId: id, tries: tries, reasons: [Reason(.CONTINUE_SERIES, [String(tries)])])
    }

    // ---------- Filters ----------

    public static let customProducts = Filter("CustomProducts") { p, _, _ in p.isCustom ? Reason(.CUSTOM_PRODUCT) : nil }

    /// Уже начатые / введённые / с реакцией — не новые.
    public static let alreadyStarted = Filter("AlreadyStarted") { p, f, _ in
        f.progress[p.id] != nil && f.ctx.marks[p.id] == nil ? Reason(.ALREADY_STARTED) : nil
    }

    public static let marked = Filter("Marked") { p, f, _ in f.ctx.marks[p.id].map { Reason(.MARKED, [$0.rawValue]) } }

    /// Возраст ребёнка меньше минимального для продукта. Без даты рождения считаем, что 6 мес.
    public static let tooYoung = Filter("TooYoung") { p, f, c in
        let age = f.ageMonths ?? c.assumedAgeMonths
        return age < p.minAgeMonths ? Reason(.TOO_YOUNG, [String(p.minAgeMonths)]) : nil
    }

    /// Содержит аллерген, на который у ребёнка известна аллергия (из профиля).
    public static let knownAllergen = Filter("KnownAllergen") { p, f, _ in
        p.allergenIds.first { f.knownAllergens.contains($0) }.map { Reason(.KNOWN_ALLERGEN, [$0]) }
    }

    /// Аллергены — после того, как освоена база.
    public static let baseProductsFirst = Filter("BaseProductsFirst") { p, f, c in
        !p.allergenIds.isEmpty && f.introducedCount < c.allergensAfterIntroduced
            ? Reason(.BASE_PRODUCTS_FIRST, [String(c.allergensAfterIntroduced)]) : nil
    }

    /// Между началом двух аллергенов — пауза.
    public static let allergenGap = Filter("AllergenGap") { p, f, c in
        guard let last = f.lastAllergenStart else { return nil }
        guard !p.allergenIds.isEmpty, last.daysUntil(f.ctx.today) < c.allergenGapDays else { return nil }
        return Reason(.ALLERGEN_GAP, [last.plusDays(c.allergenGapDays).iso])
    }

    /// Повышенный риск (экзема / аллергия в семье): аллергены — только после консультации врача (политика в конфиге).
    public static let doctorFirstForHighRisk = Filter("DoctorFirstForHighRisk") { p, f, c in
        c.highRiskAllergens == .doctorFirst && f.highRisk && !p.allergenIds.isEmpty ? Reason(.DOCTOR_FIRST) : nil
    }

    public static let skipped = Filter("Skipped") { p, f, _ in f.ctx.skipped.contains(p.id) ? Reason(.SKIPPED) : nil }

    // ---------- Scorers ----------

    /// Порядок каталога — базовая педиатрическая последовательность: раньше в списке — больше баллов.
    public static let introOrder = Scorer("IntroOrder") { p, f, c in
        let index = f.productIndex[p.id] ?? 0
        return Contribution(reason: Reason(.INTRO_ORDER),
                            score: c.weightIntroOrder * (1.0 - Double(index) / Double(max(f.ctx.products.count, 1))))
    }

    /// Категория, из которой ещё ничего не введено — разнообразие (после первых базовых продуктов).
    public static let newCategory = Scorer("NewCategory") { p, f, c in
        f.introducedCount >= c.newCategoryAfterIntroduced && !f.introducedCategories.contains(p.categoryId)
            ? Contribution(reason: Reason(.NEW_CATEGORY, [p.categoryId]), score: c.weightNewCategory) : nil
    }

    /// База освоена, а аллергенов ещё мало — пора (раннее введение аллергенов).
    public static let allergenDue = Scorer("AllergenDue") { p, _, c in
        p.allergenIds.isEmpty ? nil : Contribution(reason: Reason(.ALLERGEN_DUE), score: c.weightAllergenDue)
    }

    public static let favorite = Scorer("Favorite") { p, f, c in
        f.ctx.favorites.contains(p.id) ? Contribution(reason: Reason(.FAVORITE), score: c.weightFavorite) : nil
    }

    /// Продукт как раз для текущего возраста (а не «давно можно»).
    public static let ageFits = Scorer("AgeFits") { p, f, c in
        guard let age = f.ageMonths else { return nil }
        return p.minAgeMonths >= age - 1 ? Contribution(reason: Reason(.AGE_FITS), score: c.weightAgeFits) : nil
    }
}
