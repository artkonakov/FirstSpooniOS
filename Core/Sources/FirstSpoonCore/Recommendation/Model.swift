/// Всё, что движок знает. Только данные; вычисления — в `Facts`.
public struct RecommendationContext: Sendable {
    public var today: LocalDate
    public var child: Child
    /// Каталог в порядке введения (глобальный sort). Свои продукты движок не рекомендует.
    public var products: [Product]
    public var entries: [DiaryEntry]
    public var marks: [String: ProductMark]
    public var favorites: Set<String>
    /// Продукты, которые пользователь пролистал кнопкой «Другой».
    public var skipped: Set<String>

    public init(today: LocalDate, child: Child, products: [Product], entries: [DiaryEntry],
                marks: [String: ProductMark] = [:], favorites: Set<String> = [], skipped: Set<String> = []) {
        self.today = today; self.child = child; self.products = products; self.entries = entries
        self.marks = marks; self.favorites = favorites; self.skipped = skipped
    }
}

/// Почему продукт рекомендован / исключён / пауза. UI превращает код в текст.
public struct Reason: Hashable, Sendable, CustomStringConvertible {
    public let code: ReasonCode
    public let args: [String]
    public init(_ code: ReasonCode, _ args: [String] = []) { self.code = code; self.args = args }
    public var description: String { "Reason(code=\(code.rawValue), args=\(args))" }
}

public enum ReasonCode: String, CaseIterable, Sendable {
    // Приоритетные ситуации
    case CONTINUE_SERIES, PAUSE_AFTER_REACTION, DONE_TODAY
    // Фильтры
    case CUSTOM_PRODUCT, ALREADY_STARTED, MARKED, TOO_YOUNG, KNOWN_ALLERGEN
    case BASE_PRODUCTS_FIRST, ALLERGEN_GAP, DOCTOR_FIRST, SKIPPED
    // Оценки
    case INTRO_ORDER, NEW_CATEGORY, ALLERGEN_DUE, FAVORITE, AGE_FITS
    // Нечего рекомендовать
    case NOTHING_LEFT
}

public enum Recommendation: Hashable, Sendable {
    /// Новый продукт.
    case tryNew(productId: String, reasons: [Reason])
    /// Продолжить начатую серию.
    case continueSeries(productId: String, tries: Int, reasons: [Reason])
    /// Новых продуктов пока не вводим (например, после реакции).
    case wait(until: LocalDate, productId: String, reasons: [Reason])
    /// Сегодня уже была проба вводимого продукта — больше ничего вводимого не предлагаем (одна проба в день).
    /// `nextProductId` — активная серия, её продолжим завтра (nil — серии нет).
    case done(nextProductId: String?, reasons: [Reason])
    case nothing(reasons: [Reason])

    public var productId: String? {
        switch self {
        case .tryNew(let id, _), .continueSeries(let id, _, _), .wait(_, let id, _): return id
        case .done, .nothing: return nil
        }
    }

    public var reasons: [Reason] {
        switch self {
        case .tryNew(_, let r), .continueSeries(_, _, let r), .wait(_, _, let r), .done(_, let r), .nothing(let r): return r
        }
    }

    /// Имя вида, как `simpleName` класса в Android (для golden-файлов и отладки).
    public var kindName: String {
        switch self {
        case .tryNew: return "Try"
        case .continueSeries: return "Continue"
        case .wait: return "Wait"
        case .done: return "Done"
        case .nothing: return "Nothing"
        }
    }
}

/// Полный разбор для debug-экрана и тестов: рейтинг с вкладом каждого правила и исключённые с причинами.
public struct RecommendationResult: Hashable, Sendable {
    public let recommendation: Recommendation
    public let ranking: [Ranked]
    public let excluded: [Excluded]
    /// Активная серия — продукт, который вводим сейчас (одна серия за раз).
    public let activeSeries: String?
    /// Остальные начатые продукты — ждут, пока закончится активная серия.
    public let queued: [String]

    public init(_ recommendation: Recommendation, ranking: [Ranked] = [], excluded: [Excluded] = [],
                activeSeries: String? = nil, queued: [String] = []) {
        self.recommendation = recommendation; self.ranking = ranking; self.excluded = excluded
        self.activeSeries = activeSeries; self.queued = queued
    }
}

public struct Excluded: Hashable, Sendable {
    public let product: Product
    public let reason: Reason
}

public struct Contribution: Hashable, Sendable {
    public let reason: Reason
    public let score: Double
}

public struct Ranked: Hashable, Sendable {
    public let product: Product
    public let total: Double
    public let contributions: [Contribution]
}

/// Производные факты — считаются один раз и доступны всем правилам.
public final class Facts: @unchecked Sendable {
    public let ctx: RecommendationContext
    public let ageMonths: Int?
    public let progress: [String: ProductProgress]
    public let productsById: [String: Product]
    public let productIndex: [String: Int]
    public let introduced: [Product]
    public let introducedCount: Int
    public let introducedCategories: Set<String>
    public let knownAllergens: Set<String>
    /// Повышенный риск аллергии: экзема или аллергия в семье.
    public let highRisk: Bool
    /// Первая проба каждого продукта — день его «начала».
    public let firstTry: [String: LocalDate]
    public let lastTry: [String: LocalDate]
    /// Когда последний раз начинали продукт-аллерген (для паузы между аллергенами).
    public let lastAllergenStart: LocalDate?
    /// Последняя проба с реакцией «Плохо» / «Сомнительно» (при равенстве дат — первая в списке).
    public let lastReaction: DiaryEntry?
    public let inSeries: [String]
    /// Активная серия — одна за раз (`Series.split`).
    public let activeSeries: String?
    /// Начатые, но не активные — ждут очереди.
    public let queued: [String]
    /// Сегодня уже была проба вводимого продукта — продукта, который до сегодня не был введён
    /// (новый, в серии или с реакцией). Пробы введённых продуктов день не занимают.
    public let todayBusy: Bool

    public init(_ ctx: RecommendationContext) {
        self.ctx = ctx
        ageMonths = ctx.child.ageMonths(ctx.today)
        progress = FeedingRules.progressByProduct(ctx.entries, marks: ctx.marks)
        productsById = Dictionary(ctx.products.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var index: [String: Int] = [:]
        for (i, p) in ctx.products.enumerated() where index[p.id] == nil { index[p.id] = i }
        productIndex = index
        let progress = self.progress
        introduced = ctx.products.filter { progress[$0.id]?.status == .introduced }
        introducedCount = progress.values.filter { $0.status == .introduced }.count
        introducedCategories = Set(introduced.map(\.categoryId))
        knownAllergens = ctx.child.profile.knownAllergens
        highRisk = ctx.child.profile.hasEczema || ctx.child.profile.familyAllergy

        var first: [String: LocalDate] = [:], last: [String: LocalDate] = [:]
        for e in ctx.entries {
            first[e.productId] = min(first[e.productId] ?? e.date, e.date)
            last[e.productId] = max(last[e.productId] ?? e.date, e.date)
        }
        firstTry = first
        lastTry = last
        let byId = productsById
        lastAllergenStart = first.filter { byId[$0.key].map { !$0.allergenIds.isEmpty } ?? false }.values.max()

        var reaction: DiaryEntry?
        for e in ctx.entries where e.reaction == .reaction || e.reaction == .unsure {
            if reaction == nil || e.date > reaction!.date { reaction = e }
        }
        lastReaction = reaction

        // Порядок как у LinkedHashMap в Android: по первому появлению продукта в пробах, затем отметки.
        var order: [String] = []
        var seen = Set<String>()
        for id in ctx.entries.map(\.productId) + ctx.marks.keys.sorted() where seen.insert(id).inserted { order.append(id) }
        inSeries = order.filter { progress[$0]?.status == .inProgress }

        let split = Series.split(ctx.entries, marks: ctx.marks, today: ctx.today)
        activeSeries = split.active
        queued = split.queued
        let todayIds = Set(ctx.entries.filter { $0.date == ctx.today }.map(\.productId))
        if todayIds.isEmpty {
            todayBusy = false
        } else {
            let before = FeedingRules.progressByProduct(ctx.entries.filter { $0.date.isBefore(ctx.today) }, marks: ctx.marks)
            todayBusy = todayIds.contains { before[$0]?.status != .introduced }
        }
    }
}
