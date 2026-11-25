import XCTest
@testable import FirstSpoonCore

/// Research simulation. Run from a scratch copy of FirstSpoonCore, as described in recommendation-draft.md.
final class ResearchRankingTests: XCTestCase {
    private static let iron = ["beef", "turkey", "rabbit", "veal"]
    private static let checkpoints = [
        ["zucchini", "broccoli", "cauliflower"],
        ["buckwheat-groats", "corn-grits", "rice"],
        iron,
        ["egg-white"],
        ["pear", "apple"],
        ["peanut"],
    ]

    private static func categoryCovered(_ choices: [String], _ facts: Facts) -> Bool {
        if choices == iron || choices == ["egg-white"] || choices == ["peanut"] {
            return facts.introduced.contains { choices.contains($0.id) }
        }
        return choices.compactMap { facts.productsById[$0]?.categoryId }
            .contains { facts.introducedCategories.contains($0) }
    }

    private func config(_ id: String) -> RecommendationConfig {
        if id != "guided" && id != "adaptive" {
            return Strategies.config(Strategies.byId(id))
        }
        let isGuided = id == "guided"
        var config = Strategies.config(Strategies.byId(Strategies.classic))
        config.allergensAfterIntroduced = Strategies.safety.minIntroducedBeforeAllergens
        config.rules = config.rules.filter { rule in
            !["AllergenDue", "NewCategory", "IntroOrder", "AgeFits"].contains(rule.name)
        }
        config.rules.append(.scorer(Scorer("ResearchPriority") { product, facts, _ in
            let id = product.id
            let score: Double
            let isOtherEarlyAllergen = !product.allergenIds.isEmpty
                && !["egg-white", "peanut"].contains(id) && facts.introducedCount < 6
            if id == "egg-yolk" || isOtherEarlyAllergen {
                score = -25
            } else if facts.introducedCount == 0 {
                let order = ["zucchini", "buckwheat-groats", "broccoli", "cauliflower", "corn-grits", "rice"]
                score = order.firstIndex(of: id).map { 60 - Double($0) * 5 } ?? 0
            } else if isGuided {
                score = Self.checkpoints.enumerated().reduce(0.0) { best, checkpoint in
                    guard !Self.categoryCovered(checkpoint.element, facts),
                          let productIndex = checkpoint.element.firstIndex(of: id) else { return best }
                    return max(best, 60 - Double(checkpoint.offset) * 8 - Double(productIndex))
                }
            } else {
                let withinIron = Self.iron.firstIndex(of: id)
                let hasIron = facts.introduced.contains { Self.iron.contains($0.id) }
                let eggDue = id == "egg-white" && facts.firstTry[id] == nil
                let peanutDue = id == "peanut" && facts.firstTry[id] == nil
                let missingGroup = !facts.introducedCategories.contains(product.categoryId)
                let practicalGroups = ["vegetables", "grains-cereals-sides", "meat-poultry", "fruits-berries", "legumes", "dairy", "fish-seafood"]
                let base = practicalGroups.firstIndex(of: product.categoryId).map { 22 - Double($0) * 2 } ?? 0
                let previous = facts.ctx.entries.filter { $0.date.daysUntil(facts.ctx.today) <= 7 }
                let recent = Set(previous.map(\.productId)).compactMap { facts.productsById[$0] }
                    .filter { $0.categoryId == product.categoryId }.count
                let ironBonus = hasIron ? 0 : withinIron.map { 55 - Double($0) } ?? 0
                if eggDue || peanutDue {
                    score = eggDue ? 48 : 36
                } else {
                    score = (missingGroup ? base : 0) + ironBonus - Double(recent) * 3
                }
            }
            return Contribution(reason: Reason(.NEW_CATEGORY), score: score)
        }))
        return config
    }

    func testCompare() {
        let ids = ["classic", "variety", "early-allergens", "guided", "adaptive"]
        let profiles: [(String, Int, [String: String], Set<String>)] = [
            ("ordinary", 6, [:], []),
            ("eczema", 6, ["eczema": "yes"], []),
            ("carrot reaction", 6, [:], ["carrot"]),
            ("start at 8m", 8, [:], []),
        ]
        for (name, age, profile, reactionProducts) in profiles {
            for id in ids {
                let config = config(id)
                let start = RecTestKit.today
                let child = Child(id: "c", name: "Тест", birthDate: start.minusMonths(age), profile: ChildProfile(profile))
                var entries: [DiaryEntry] = []
                var starts: [(String, Int)] = []
                var groups = 0
                var wait = 0
                for day in 0..<42 {
                    let today = start.plusDays(day)
                    let ctx = RecTestKit.ctx(entries: entries, today: today)
                    let result = RecommendationEngine.recommend(
                        RecommendationContext(today: today, child: child, products: ctx.products, entries: entries),
                        config: config
                    ).recommendation
                    if result.kindName == "Wait" { wait += 1 }
                    if ["Try", "Continue"].contains(result.kindName), let p = result.productId {
                        let isNew = !entries.contains { $0.productId == p }
                        if isNew { starts.append((p, day)) }
                        entries.append(DiaryEntry(id: "d\(day)", productId: p, date: today, reaction: isNew && reactionProducts.contains(p) ? .reaction : .good))
                    }
                    if day == 29 {
                        let introduced = FeedingRules.progressByProduct(entries, marks: [:]).filter { $0.value.status == .introduced }
                        groups = Set(introduced.keys.compactMap { RecTestKit.byId[$0]?.categoryId }).count
                    }
                }
                func first(_ matches: (String) -> Bool) -> String {
                    starts.first { matches($0.0) }.map { "\($0.0)@\($0.1)" } ?? "—"
                }
                let picks = starts.prefix(7).map { "\($0.0)@\($0.1)" }.joined(separator: ", ")
                print("RESEARCH | \(name) | \(id) | \(picks) | iron: \(first { Self.iron.contains($0) }) | egg: \(first { $0 == "egg-white" }) | peanut: \(first { $0 == "peanut" }) | groups: \(groups) | wait: \(wait)")
            }
        }
    }
}
