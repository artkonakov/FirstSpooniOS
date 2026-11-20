import Foundation

/// Слой безопасности рекомендаций — общий для всех алгоритмов (`Resources/recommendation/safety.json`, копия Android
/// `shared/recommendation/`). Android `docs/product-rules.md` «Алгоритмы рекомендаций». Порт `Strategies.kt`.
public struct Safety: Sendable {
    public let reactionPauseDays: Int
    public let allergenGapDays: Int
    public let assumedAgeMonths: Int
    public let highRiskAllergens: HighRiskPolicy
    /// Нижняя граница «введено продуктов до первого аллергена»: алгоритм может только поднять.
    public let minIntroducedBeforeAllergens: Int
}

/// Параметры одного вида балла из JSON алгоритма.
public struct ScorerParams: Sendable {
    public let weight: Double
    public let afterIntroduced: Int?
    /// Только для `stages`.
    public var stepPenalty: Double?
    public var stages: [Stage] = []
}

/// Алгоритм подбора нового продукта (`Resources/recommendation/strategies/<id>.json`).
public struct Strategy: Sendable {
    public let id: String
    public let title: [String: String]
    public let description: [String: String]
    /// default / experiment / available.
    public let status: String
    public let scorers: [String: ScorerParams]
}

/// Загрузка алгоритмов и сборка `RecommendationConfig`. Те же файлы читает Android.
public enum Strategies {
    public static let classic = "classic"

    /// Виды баллов, которые умеет движок. Неизвестный вид в JSON — ошибка (ловит `StrategiesTests`).
    public static let scorerKinds: Set<String> = ["introOrder", "newCategory", "allergenDue", "favorite", "ageFits", "stages"]

    public static let safety: Safety = {
        let o = read("safety")
        return Safety(
            reactionPauseDays: int(o, "reactionPauseDays"),
            allergenGapDays: int(o, "allergenGapDays"),
            assumedAgeMonths: int(o, "assumedAgeMonths"),
            highRiskAllergens: (o["highRiskAllergens"] as? String) == "as_usual" ? .asUsual : .doctorFirst,
            minIntroducedBeforeAllergens: int(o, "minIntroducedBeforeAllergens")
        )
    }()

    public static let all: [Strategy] = {
        let ids = read("strategies/index")["strategies"] as? [String] ?? []
        return ids.map { parse(read("strategies/\($0)")) }
    }()

    /// Алгоритм по id; неизвестный (удалён в новой версии) — классический.
    public static func byId(_ id: String?) -> Strategy {
        all.first { $0.id == id } ?? all.first { $0.id == classic }!
    }

    public static func config(_ strategy: Strategy = byId(classic), safety: Safety = safety) -> RecommendationConfig {
        func w(_ kind: String) -> Double { strategy.scorers[kind]?.weight ?? 0 }
        let defaults = RecommendationConfig()
        var c = defaults
        c.strategyId = strategy.id
        c.reactionPauseDays = safety.reactionPauseDays
        c.allergenGapDays = safety.allergenGapDays
        c.assumedAgeMonths = safety.assumedAgeMonths
        c.highRiskAllergens = safety.highRiskAllergens
        c.allergensAfterIntroduced = max(safety.minIntroducedBeforeAllergens,
                                         strategy.scorers["allergenDue"]?.afterIntroduced ?? defaults.allergensAfterIntroduced)
        c.newCategoryAfterIntroduced = strategy.scorers["newCategory"]?.afterIntroduced ?? defaults.newCategoryAfterIntroduced
        c.weightIntroOrder = w("introOrder")
        c.weightNewCategory = w("newCategory")
        c.weightAllergenDue = w("allergenDue")
        c.weightFavorite = w("favorite")
        c.weightAgeFits = w("ageFits")
        c.stages = strategy.scorers["stages"]?.stages ?? []
        c.weightStage = w("stages")
        c.stageStepPenalty = strategy.scorers["stages"]?.stepPenalty ?? defaults.stageStepPenalty
        return c
    }

    /// Текст причины этапа для родителя (ищем по всем алгоритмам; id этапов уникальны в пределах алгоритма).
    public static func stageReason(_ stageId: String, lang: String) -> String? {
        for s in all {
            if let st = s.scorers["stages"]?.stages.first(where: { $0.id == stageId }) { return st.reason[lang] ?? st.reason["ru"] }
        }
        return nil
    }

    private static func parse(_ o: [String: Any]) -> Strategy {
        func texts(_ key: String) -> [String: String] { o[key] as? [String: String] ?? [:] }
        let scorers = (o["scorers"] as? [String: [String: Any]] ?? [:]).mapValues { p in
            ScorerParams(
                weight: (p["weight"] as? NSNumber)?.doubleValue ?? 0,
                afterIntroduced: (p["afterIntroduced"] as? NSNumber)?.intValue,
                stepPenalty: (p["stepPenalty"] as? NSNumber)?.doubleValue,
                stages: (p["list"] as? [[String: Any]] ?? []).map { st in
                    Stage(id: st["id"] as? String ?? "", products: st["products"] as? [String] ?? [],
                          need: (st["need"] as? NSNumber)?.intValue ?? 1, reason: st["reason"] as? [String: String] ?? [:])
                }
            )
        }
        return Strategy(id: o["id"] as! String, title: texts("title"), description: texts("description"),
                        status: o["status"] as? String ?? "experiment", scorers: scorers)
    }

    private static func int(_ o: [String: Any], _ key: String) -> Int {
        guard let n = o[key] as? NSNumber else { fatalError("\(key): не число") }
        return n.intValue
    }

    private static func read(_ path: String) -> [String: Any] {
        guard let url = Bundle.module.url(forResource: "recommendation/\(path)", withExtension: "json")
                ?? Bundle.module.resourceURL?.appendingPathComponent("recommendation/\(path).json"),
              let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { fatalError("Нет ресурса recommendation/\(path).json (shared/recommendation)") }
        return obj
    }
}
