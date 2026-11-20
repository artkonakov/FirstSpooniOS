public enum HighRiskPolicy: Sendable {
    /// При экземе / аллергии в семье аллергены не рекомендуем — советуем обсудить с врачом.
    case doctorFirst
    /// Рекомендуем как обычно.
    case asUsual
}

/// Настройки движка: набор правил, пороги и веса. Значения по умолчанию — разумная отправная точка,
/// **медицинскую часть нужно сверить с педиатрическими рекомендациями**. В приложении конфиг собирает `Strategies.config`
/// из `Resources/recommendation/` (слой безопасности + алгоритм); значения по умолчанию здесь = алгоритм `classic`
/// (`StrategiesTests` следит, чтобы они совпадали).
public struct RecommendationConfig: Sendable {
    /// Какой алгоритм собрал этот конфиг (`Strategies`); для аналитики и debug.
    public var strategyId = Strategies.classic
    public var reactionPauseDays = 3
    public var allergenGapDays = 3
    /// Сколько продуктов ввести до первого аллергена.
    public var allergensAfterIntroduced = 5
    public var assumedAgeMonths = 6
    /// Первые продукты — из одной стартовой категории (овощи), разнообразие — после этого числа.
    public var newCategoryAfterIntroduced = 3
    public var highRiskAllergens: HighRiskPolicy = .doctorFirst
    public var weightIntroOrder = 10.0
    public var weightNewCategory = 4.0
    public var weightAllergenDue = 6.0
    public var weightFavorite = 2.0
    public var weightAgeFits = 1.0
    /// Этапы алгоритма «шаг за шагом» (`Stage`); пусто — балл `stagePlan` не работает.
    public var stages: [Stage] = []
    public var weightStage = 0.0
    /// На сколько меньше баллов у каждого следующего незакрытого этапа.
    public var stageStepPenalty = 8.0
    public var rules: [Rule] = RecommendationConfig.defaultRules

    public init() {}

    /// Порядок важен для Gate (первый сработавший побеждает).
    public static let defaultRules: [Rule] = [
        .gate(Rules.pauseAfterReaction), .gate(Rules.oneTryPerDay), .gate(Rules.continueSeries),
        .filter(Rules.customProducts), .filter(Rules.marked), .filter(Rules.alreadyStarted), .filter(Rules.tooYoung),
        .filter(Rules.knownAllergen), .filter(Rules.doctorFirstForHighRisk), .filter(Rules.baseProductsFirst),
        .filter(Rules.allergenGap), .filter(Rules.skipped),
        .scorer(Rules.introOrder), .scorer(Rules.newCategory), .scorer(Rules.allergenDue), .scorer(Rules.favorite),
        .scorer(Rules.ageFits), .scorer(Rules.stagePlan),
    ]
}

/// Рекомендательный движок: чистая детерминированная функция контекст → одна рекомендация (+ полный разбор).
/// Gate → Filter → Scorer; при равенстве баллов — порядок каталога.
public enum RecommendationEngine {
    public static func recommend(_ ctx: RecommendationContext, config: RecommendationConfig = RecommendationConfig()) -> RecommendationResult {
        let facts = Facts(ctx)
        for rule in config.rules {
            if case .gate(let g) = rule, let r = g.decide(facts, config) {
                return RecommendationResult(r, activeSeries: facts.activeSeries, queued: facts.queued)
            }
        }

        let filters = config.rules.compactMap { if case .filter(let f) = $0 { return f } else { return nil } }
        var excluded: [Excluded] = []
        var candidates: [Product] = []
        for p in ctx.products {
            if let reason = filters.lazy.compactMap({ $0.exclude(p, facts, config) }).first {
                excluded.append(Excluded(product: p, reason: reason))
            } else {
                candidates.append(p)
            }
        }

        let scorers = config.rules.compactMap { if case .scorer(let s) = $0 { return s } else { return nil } }
        let ranking = candidates.enumerated().map { i, p -> (Int, Ranked) in
            let contributions = scorers.compactMap { $0.score(p, facts, config) }
            return (i, Ranked(product: p, total: contributions.reduce(0) { $0 + $1.score }, contributions: contributions))
        }
        .sorted { $0.1.total != $1.1.total ? $0.1.total > $1.1.total : $0.0 < $1.0 }
        .map(\.1)

        let recommendation: Recommendation
        if let best = ranking.first {
            // Причины для пользователя: правила с реальным вкладом, самые весомые сначала (порядок каталога — фон, не показываем).
            let reasons = best.contributions.enumerated()
                .filter { $0.element.reason.code != .INTRO_ORDER }
                .sorted { $0.element.score != $1.element.score ? $0.element.score > $1.element.score : $0.offset < $1.offset }
                .map(\.element.reason)
            recommendation = .tryNew(productId: best.product.id, reasons: reasons)
        } else {
            recommendation = .nothing(reasons: [Reason(.NOTHING_LEFT)])
        }
        return RecommendationResult(recommendation, ranking: ranking, excluded: excluded,
                                    activeSeries: facts.activeSeries, queued: facts.queued)
    }
}
