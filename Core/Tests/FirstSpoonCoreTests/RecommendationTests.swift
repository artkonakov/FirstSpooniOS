import XCTest
@testable import FirstSpoonCore

/// Общие помощники тестов движка: настоящий каталог приложения и сборка контекста.
enum RecTestKit {
    static let resources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Resources")
    /// Настоящий catalog.json приложения — тесты ловят и изменения каталога.
    static let catalogURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("FirstSpoon/Resources/catalog.json")

    static let catalog: [Product] = {
        let payload = try! CatalogPayload.decode(Data(contentsOf: catalogURL))
        return payload.toCatalog().products.map {
            Product(id: $0.id, categoryId: $0.categoryId, name: $0.name, minAgeMonths: $0.minAgeMonths,
                    allergens: $0.allergenIds, description: "", firstServing: "", allergenIds: $0.allergenIds)
        }
    }()
    static let byId: [String: Product] = Dictionary(uniqueKeysWithValues: catalog.map { ($0.id, $0) })

    static let today = LocalDate(2026, 11, 11)

    static func child(_ ageMonths: Int?, _ profile: [String: String] = [:]) -> Child {
        Child(id: "c", name: "Тест", birthDate: ageMonths.map { today.minusMonths($0).minusDays(3) }, profile: ChildProfile(profile))
    }

    nonisolated(unsafe) private static var n = 0
    static func entry(_ product: String, _ daysAgo: Int, _ reaction: Reaction = .good) -> DiaryEntry {
        n += 1
        return DiaryEntry(id: "e\(n)", productId: product, date: today.minusDays(daysAgo), reaction: reaction)
    }

    /// Ввести продукт полностью: 3 пробы подряд, последняя — `daysAgo` дней назад.
    static func introduced(_ product: String, _ daysAgo: Int = 10) -> [DiaryEntry] {
        (0..<3).map { entry(product, daysAgo + 2 - $0) }
    }

    static func ctx(ageMonths: Int? = 7, profile: [String: String] = [:], entries: [DiaryEntry] = [],
                    marks: [String: ProductMark] = [:], favorites: Set<String> = [], today: LocalDate = today) -> RecommendationContext {
        RecommendationContext(today: today, child: child(ageMonths, profile), products: catalog, entries: entries,
                              marks: marks, favorites: favorites)
    }
}

/// По одному тесту на правило: каждое проверяется изолированно, через Facts.
final class RulesTests: XCTestCase {
    private let c = RecommendationConfig()
    private func p(_ id: String) -> Product { RecTestKit.byId[id]! }
    private let fiveBase = ["broccoli", "zucchini", "cauliflower", "carrot", "pumpkin"].flatMap { RecTestKit.introduced($0) }
    private typealias K = RecTestKit

    func testPauseAfterBadReactionBlocksNewProductsFor3Days() {
        let r = Rules.pauseAfterReaction.decide(Facts(K.ctx(entries: [K.entry("broccoli", 1, .reaction)])), c)
        guard case .wait(let until, _, _) = r else { return XCTFail("expected wait, got \(String(describing: r))") }
        XCTAssertEqual(until, K.today.plusDays(2))
        XCTAssertNil(Rules.pauseAfterReaction.decide(Facts(K.ctx(entries: [K.entry("broccoli", 3, .reaction)])), c))
    }

    func testOneSeriesAtATimeTieGoesToTheOneStartedEarlier() {
        let f = Facts(K.ctx(entries: [K.entry("zucchini", 1), K.entry("broccoli", 2)]))
        XCTAssertEqual(Rules.continueSeries.decide(f, c)?.productId, "broccoli")
        XCTAssertEqual(f.queued, ["zucchini"])
    }

    func testOneSeriesAtATimeTheOneCloserToIntroducedWins() {
        let f = Facts(K.ctx(entries: [K.entry("zucchini", 5), K.entry("broccoli", 4), K.entry("broccoli", 2)]))
        XCTAssertEqual(f.activeSeries, "broccoli")
        XCTAssertEqual(Rules.continueSeries.decide(f, c)?.productId, "broccoli")
    }

    func testQueuedProductGivenTwoDaysInARowBecomesActive() {
        // Брокколи ближе к введению, но родитель два дня подряд давал кабачок — продолжаем кабачок.
        let f = Facts(K.ctx(entries: [K.entry("broccoli", 6), K.entry("broccoli", 5), K.entry("zucchini", 2), K.entry("zucchini", 1)]))
        XCTAssertEqual(f.activeSeries, "zucchini")
        XCTAssertEqual(f.queued, ["broccoli"])
    }

    func testOneTryPerDayAfterATryOfANewProductTodayNothingElseIsOffered() {
        let f = Facts(K.ctx(entries: [K.entry("broccoli", 0)]))
        guard case .done(let next, _) = Rules.oneTryPerDay.decide(f, c) else { return XCTFail("expected done") }
        XCTAssertEqual(next, "broccoli")
        // Весь движок: «на сегодня всё», а не «дайте ещё раз» брокколи.
        guard case .done = RecommendationEngine.recommend(K.ctx(entries: [K.entry("broccoli", 0)])).recommendation else {
            return XCTFail("expected done")
        }
    }

    func testOneTryPerDayIntroducedFoodTodayDoesNotTakeTheDay() {
        let f = Facts(K.ctx(entries: K.introduced("zucchini", 10) + [K.entry("zucchini", 0)]))
        XCTAssertNil(Rules.oneTryPerDay.decide(f, c))
    }

    func testOneTryPerDayThirdTryTodayStillTakesTheDay() {
        let f = Facts(K.ctx(entries: [K.entry("broccoli", 2), K.entry("broccoli", 1), K.entry("broccoli", 0)]))
        guard case .done(let next, _) = Rules.oneTryPerDay.decide(f, c) else { return XCTFail("expected done") }
        XCTAssertNil(next, "введён — завтра нечего продолжать")
    }

    func testSeriesIsNotContinuedWhenTheAllergenWasAddedToTheProfileLater() {
        // Яичный желток начали, потом в профиль добавили аллергию на яйцо — «Дайте ещё раз» желток не предлагаем.
        let entries = K.introduced("zucchini", 20) + K.introduced("broccoli", 15) + K.introduced("cauliflower", 12)
            + K.introduced("pumpkin", 9) + K.introduced("carrot", 6) + [K.entry("egg-yolk", 2)]
        let r = RecommendationEngine.recommend(K.ctx(ageMonths: 9, profile: ["known_allergens": "egg"], entries: entries))
        XCTAssertNotEqual(r.recommendation.productId, "egg-yolk", "\(r.recommendation)")
        XCTAssertNotEqual(r.activeSeries, "egg-yolk")
        XCTAssertFalse(r.queued.contains("egg-yolk"))
    }

    func testStepsPlanGoesStageByStageAndSkipsWhatIsBlocked() {
        let steps = Strategies.config(Strategies.byId("steps"))
        func rec(_ entries: [DiaryEntry], age: Int = 7) -> Recommendation {
            RecommendationEngine.recommend(K.ctx(ageMonths: age, entries: entries), config: steps).recommendation
        }
        XCTAssertEqual(rec([]).productId, "zucchini")
        XCTAssertEqual(rec(K.introduced("zucchini", 10)).productId, "cauliflower")
        let veg = K.introduced("zucchini", 20) + K.introduced("cauliflower", 15) + K.introduced("broccoli", 10)
        XCTAssertEqual(rec(veg).productId, "buckwheat-groats")
        XCTAssertEqual(rec(veg + K.introduced("buckwheat-groats", 5)).productId, "rabbit")
        // Старт в 8 месяцев без истории — тоже кабачок, а не «самый взрослый» продукт.
        XCTAssertEqual(rec([], age: 8).productId, "zucchini")
        // Причина — текст этапа.
        XCTAssertEqual(rec([]).reasons.first?.code, .STAGE)
    }

    func testNotReadyNoProductsUntil6MonthsWithHeadControlAndSitting() {
        func rec(_ age: Int, _ head: String?, _ sits: String?, _ entries: [DiaryEntry] = []) -> Recommendation {
            var p: [String: String] = [:]
            p["head_control"] = head; p["sits_with_support"] = sits
            return RecommendationEngine.recommend(K.ctx(ageMonths: age, profile: p, entries: entries)).recommendation
        }
        func isNotReady(_ r: Recommendation) -> Bool { if case .notReady = r { return true }; return false }
        func isTry(_ r: Recommendation) -> Bool { if case .tryNew = r { return true }; return false }
        XCTAssertTrue(isNotReady(rec(5, "yes", "yes")), "младше 6 месяцев")
        XCTAssertTrue(isNotReady(rec(7, "yes", "no")), "не сидит")
        XCTAssertTrue(isNotReady(rec(7, "not_sure", "yes")), "не уверены")
        XCTAssertTrue(isTry(rec(6, "yes", "yes")), "6 мес и навыки есть — первые продукты")
        XCTAssertTrue(isTry(rec(7, nil, nil)), "старый онбординг без вопросов готовности")
        XCTAssertFalse(isNotReady(rec(7, "no", "no", [K.entry("zucchini", 1)])), "уже ест — не блокируем")
    }

    func testPauseWinsOverDone() {
        let r = RecommendationEngine.recommend(K.ctx(entries: [K.entry("broccoli", 0, .reaction)])).recommendation
        guard case .wait = r else { return XCTFail("expected wait, got \(r)") }
    }

    func testTooYoungFilterUsesAgeAndDefaultAge() {
        XCTAssertNotNil(Rules.tooYoung.exclude(p("milk"), Facts(K.ctx(ageMonths: 8)), c))
        XCTAssertNil(Rules.tooYoung.exclude(p("broccoli"), Facts(K.ctx(ageMonths: nil)), c))
        XCTAssertNotNil(Rules.tooYoung.exclude(p("pasta"), Facts(K.ctx(ageMonths: nil)), c))
    }

    func testKnownAllergenFromProfileExcludesProduct() {
        let f = Facts(K.ctx(profile: ["known_allergens": "egg"]))
        XCTAssertEqual(Rules.knownAllergen.exclude(p("egg-yolk"), f, c)?.code, .KNOWN_ALLERGEN)
        XCTAssertNil(Rules.knownAllergen.exclude(p("yogurt"), f, c))
    }

    func testAllergensOnlyAfterBaseProducts() {
        XCTAssertNotNil(Rules.baseProductsFirst.exclude(p("egg-yolk"), Facts(K.ctx()), c))
        XCTAssertNil(Rules.baseProductsFirst.exclude(p("egg-yolk"), Facts(K.ctx(entries: fiveBase)), c))
        XCTAssertNil(Rules.baseProductsFirst.exclude(p("broccoli"), Facts(K.ctx()), c))
    }

    func testGapBetweenAllergenStarts() {
        XCTAssertNotNil(Rules.allergenGap.exclude(p("egg-yolk"), Facts(K.ctx(entries: fiveBase + [K.entry("yogurt", 1)])), c))
        XCTAssertNil(Rules.allergenGap.exclude(p("egg-yolk"), Facts(K.ctx(entries: fiveBase + [K.entry("yogurt", 3)])), c))
    }

    func testHighRiskSendsAllergensToDoctorUnlessPolicySaysOtherwise() {
        let f = Facts(K.ctx(profile: ["eczema": "yes"]))
        XCTAssertNotNil(Rules.doctorFirstForHighRisk.exclude(p("egg-yolk"), f, c))
        var asUsual = c
        asUsual.highRiskAllergens = .asUsual
        XCTAssertNil(Rules.doctorFirstForHighRisk.exclude(p("egg-yolk"), f, asUsual))
        XCTAssertNotNil(Rules.doctorFirstForHighRisk.exclude(p("peanut"), Facts(K.ctx(profile: ["family_allergy": "yes"])), c))
    }

    func testMarksAndStartedProductsAreFiltered() {
        let f = Facts(K.ctx(entries: [K.entry("zucchini", 1)], marks: ["broccoli": .known]))
        XCTAssertNotNil(Rules.marked.exclude(p("broccoli"), f, c))
        XCTAssertNotNil(Rules.alreadyStarted.exclude(p("zucchini"), f, c))
    }

    func testNewCategoryScoresOnlyAfterFirstBaseProducts() {
        XCTAssertNil(Rules.newCategory.score(p("apple"), Facts(K.ctx()), c))
        XCTAssertNil(Rules.newCategory.score(p("apple"), Facts(K.ctx(entries: K.introduced("broccoli"))), c))
        let f = Facts(K.ctx(entries: fiveBase))
        XCTAssertNotNil(Rules.newCategory.score(p("apple"), f, c))
        XCTAssertNil(Rules.newCategory.score(p("beetroot"), f, c))
    }

    func testEngineIsDeterministicAndExplainsItself() {
        let x = K.ctx(entries: fiveBase)
        let a = RecommendationEngine.recommend(x)
        XCTAssertEqual(a, RecommendationEngine.recommend(x))
        guard case .tryNew = a.recommendation else { return XCTFail("expected try") }
        XCTAssertFalse(a.excluded.isEmpty)
        XCTAssertFalse(a.ranking.isEmpty)
    }
}

/// Сценарии из `Resources/scenarios.json` (копия Android `src/test/resources/recommendation/scenarios.json`)
/// на настоящем каталоге. Добавить кейс = дописать объект в JSON, код не нужен.
final class ScenarioTests: XCTestCase {
    struct History: Decodable { let product: String; let daysAgo: Int; let times: Int?; let reaction: String? }
    struct Expect: Decodable {
        let type: String
        let product: String?
        let notProducts: [String]?
        let reasonsContain: [String]?
        let excludedReason: [String: String]?
    }
    struct Scenario: Decodable {
        let name: String
        let ageMonths: Int?
        let profile: [String: String]?
        let introduced: [String]?
        let history: [History]?
        let marks: [String: String]?
        let favorites: Set<String>?
        let expect: Expect
    }

    func testAllScenarios() throws {
        let scenarios = try JSONDecoder().decode([Scenario].self, from: Data(contentsOf: RecTestKit.resources.appendingPathComponent("scenarios.json")))
        XCTAssertFalse(scenarios.isEmpty)
        let failures = scenarios.compactMap { s in check(s).map { "• \(s.name): \($0)" } }
        if !failures.isEmpty {
            XCTFail("Сценарии не прошли (\(failures.count)/\(scenarios.count)):\n" + failures.joined(separator: "\n"))
        }
    }

    private func check(_ s: Scenario) -> String? {
        let entries = (s.introduced ?? []).flatMap { RecTestKit.introduced($0) } + (s.history ?? []).flatMap { h -> [DiaryEntry] in
            let times = h.times ?? 1
            return (0..<times).map { RecTestKit.entry(h.product, h.daysAgo + (times - 1 - $0), Reaction(rawValue: h.reaction ?? "good") ?? .good) }
        }
        var marks: [String: ProductMark] = [:]
        for (k, v) in s.marks ?? [:] {
            guard let m = ProductMark(rawValue: v) else { return "unknown mark \(v)" }
            marks[k] = m
        }
        let result = RecommendationEngine.recommend(RecTestKit.ctx(ageMonths: s.ageMonths, profile: s.profile ?? [:], entries: entries,
                                                                  marks: marks, favorites: s.favorites ?? []))
        let rec = result.recommendation
        let dump = "\n  got: \(rec)\n  top: " + result.ranking.prefix(5).map { "\($0.product.id)=\(String(format: "%.1f", $0.total))" }.joined(separator: ", ")

        let type: String
        switch rec {
        case .tryNew: type = "try"
        case .continueSeries: type = "continue"
        case .wait: type = "wait"
        case .done: type = "done"
        case .nothing: type = "nothing"
        case .notReady: type = "not_ready"
        }
        if type != s.expect.type { return "type \(s.expect.type) ≠ \(type)\(dump)" }
        if let p = s.expect.product, p != rec.productId { return "product \(p)\(dump)" }
        for p in s.expect.notProducts ?? [] where rec.productId == p { return "must not recommend \(p)\(dump)" }
        for code in s.expect.reasonsContain ?? [] where !rec.reasons.contains(where: { $0.code.rawValue == code }) {
            return "reason \(code)\(dump)"
        }
        for (id, code) in s.expect.excludedReason ?? [:] {
            let reason = result.excluded.first { $0.product.id == id }?.reason.code.rawValue
            if reason != code { return "excluded reason for \(id): \(reason ?? "nil") ≠ \(code)\(dump)" }
        }
        return nil
    }
}

/// Детерминированный генератор (SplitMix64): падение воспроизводимо.
struct SeededRandom: RandomNumberGenerator {
    var state: UInt64
    init(_ seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

/// Свойства, которые должны выполняться ВСЕГДА — на 2000 случайных детей и историй.
final class InvariantsTests: XCTestCase {
    func testNeverRecommendsWhatMustNotBeRecommended() {
        var rnd = SeededRandom(42)
        var allergens: [String] = []
        for id in RecTestKit.catalog.flatMap(\.allergenIds) where !allergens.contains(id) { allergens.append(id) }
        let config = RecommendationConfig()
        for i in 0..<2000 {
            let age = Int.random(in: 4..<15, using: &rnd)
            var profile: [String: String] = [:]
            if Bool.random(using: &rnd) {
                profile["known_allergens"] = allergens.shuffled(using: &rnd).prefix(Int.random(in: 1..<3, using: &rnd)).joined(separator: ",")
            }
            if Int.random(in: 0..<4, using: &rnd) == 0 { profile["eczema"] = "yes" }
            if Int.random(in: 0..<4, using: &rnd) == 0 { profile["family_allergy"] = "yes" }
            let tried = RecTestKit.catalog.shuffled(using: &rnd).prefix(Int.random(in: 0..<40, using: &rnd))
            var entries: [DiaryEntry] = []
            for p in tried {
                for _ in 0..<Int.random(in: 1..<4, using: &rnd) {
                    let days = Int.random(in: 0..<30, using: &rnd)
                    let reaction: Reaction = Int.random(in: 0..<10, using: &rnd) == 0 ? .reaction : .good
                    entries.append(RecTestKit.entry(p.id, days, reaction))
                }
            }
            var marks: [String: ProductMark] = [:]
            for p in RecTestKit.catalog.shuffled(using: &rnd).prefix(Int.random(in: 0..<5, using: &rnd)) {
                marks[p.id] = ProductMark.allCases.randomElement(using: &rnd)!
            }
            let ctx = RecTestKit.ctx(ageMonths: age, profile: profile, entries: entries, marks: marks)
            let result = RecommendationEngine.recommend(ctx)
            let f = Facts(ctx)
            let msg = "case #\(i): \(result.recommendation)"

            XCTAssertEqual(result, RecommendationEngine.recommend(ctx), "deterministic \(msg)")
            switch result.recommendation {
            case .tryNew(let id, _):
                let p = RecTestKit.byId[id]!
                XCTAssertLessThanOrEqual(p.minAgeMonths, age, "age \(msg)")
                XCTAssertNil(f.progress[id], "not started \(msg)")
                XCTAssertNil(marks[id], "no mark \(msg)")
                XCTAssertFalse(p.allergenIds.contains { f.knownAllergens.contains($0) }, "no known allergen \(msg)")
                if !p.allergenIds.isEmpty {
                    XCTAssertGreaterThanOrEqual(f.introducedCount, config.allergensAfterIntroduced, "allergen only after base \(msg)")
                    XCTAssertFalse(f.highRisk, "high risk -> no allergens \(msg)")
                }
                XCTAssertNil(Rules.pauseAfterReaction.decide(f, config), "no pause active \(msg)")
                // Одна серия за раз: новый продукт — только когда ничего не начато.
                XCTAssertTrue(f.inSeries.isEmpty, "no new product while a series is open \(msg)")
                XCTAssertFalse(f.todayBusy, "one try per day \(msg)")
            case .continueSeries(let id, _, _):
                XCTAssertEqual(f.progress[id]?.status, .inProgress, msg)
                XCTAssertEqual(f.activeSeries, id, "continue only the active series \(msg)")
                XCTAssertFalse(f.todayBusy, "one try per day \(msg)")
            case .done(let next, _):
                XCTAssertTrue(f.todayBusy, "done only when today is busy \(msg)")
                XCTAssertEqual(f.activeSeries, next, "next = active series \(msg)")
            case .wait(let until, _, _):
                XCTAssertTrue(until.isAfter(ctx.today), msg)
            case .nothing:
                break
            case .notReady:
                XCTAssertFalse(FeedingReadiness.canOfferNewFoods(f.readiness), "not ready only when readiness says so \(msg)")
            }
            // Очередь и активная серия не пересекаются и вместе — все начатые.
            XCTAssertEqual(Set(f.inSeries), Set([result.activeSeries].compactMap { $0 } + result.queued), "series split \(msg)")
            XCTAssertEqual([result.activeSeries].compactMap { $0 }.count + result.queued.count, f.inSeries.count, "no overlap \(msg)")
        }
    }
}

/// Симуляция: «родитель» 120 дней подряд делает то, что советует движок. Траектория сравнивается с golden-файлами
/// Android (`Resources/*.golden.txt`) — поведение двух платформ совпадает символ в символ.
/// Принять новое поведение: `UPDATE_GOLDEN=1 swift test` (и перенести изменение в Android).
final class SimulationTests: XCTestCase {
    private struct Run { let log: [String]; let entries: [DiaryEntry]; let introduced: Int }

    private func pad(_ s: String, _ width: Int) -> String { s.count >= width ? s : s + String(repeating: " ", count: width - s.count) }

    private func simulate(profile: [String: String] = [:], badOn: Set<String> = [], days: Int = 120) -> Run {
        let start = RecTestKit.today
        var entries: [DiaryEntry] = []
        var log: [String] = []
        var n = 0
        var introduced = 0
        for day in 0..<days {
            let today = start.plusDays(day)
            var ctx = RecTestKit.ctx(ageMonths: 6, profile: profile, entries: entries, today: today)
            var child = RecTestKit.child(nil, profile)
            child.birthDate = start.minusMonths(6)
            ctx.child = child
            let r = RecommendationEngine.recommend(ctx).recommendation
            introduced = Facts(ctx).introducedCount
            let dayStr = String(day)
            log.append("day " + String(repeating: " ", count: max(0, 3 - dayStr.count)) + dayStr + "  "
                       + pad(r.kindName, 8) + " " + pad(r.productId ?? "-", 18) + " "
                       + r.reasons.map(\.code.rawValue).joined(separator: ", "))
            switch r {
            case .tryNew(let id, _), .continueSeries(let id, _, _):
                let reaction: Reaction = badOn.contains(id) && !entries.contains { $0.productId == id } ? .reaction : .good
                entries.append(DiaryEntry(id: "s\(n)", productId: id, date: today, reaction: reaction))
                n += 1
            default: break
            }
        }
        return Run(log: log, entries: entries, introduced: introduced)
    }

    private func golden(_ name: String, _ run: Run) throws {
        let url = RecTestKit.resources.appendingPathComponent("\(name).golden.txt")
        let actual = run.log.joined(separator: "\n") + "\n"
        if ProcessInfo.processInfo.environment["UPDATE_GOLDEN"] == "1" || !FileManager.default.fileExists(atPath: url.path) {
            try actual.write(to: url, atomically: true, encoding: .utf8)
            return
        }
        let expected = try String(contentsOf: url, encoding: .utf8)
        if expected != actual {
            let e = expected.split(separator: "\n"), a = actual.split(separator: "\n")
            let i = zip(e, a).enumerated().first { $0.element.0 != $0.element.1 }?.offset ?? min(e.count, a.count)
            XCTFail("Траектория \(name) изменилась (строка \(i + 1)). Если так и задумано: UPDATE_GOLDEN=1\n"
                    + "expected: \(i < e.count ? String(e[i]) : "<end>")\nactual:   \(i < a.count ? String(a[i]) : "<end>")")
        }
    }

    func testDefaultChild() throws {
        let run = simulate()
        try golden("simulation_default", run)
        XCTAssertGreaterThanOrEqual(run.introduced, 30, "за 120 дней вводим много продуктов")
        var starts: [String: LocalDate] = [:]
        for e in run.entries where !(RecTestKit.byId[e.productId]!.allergenIds.isEmpty) {
            starts[e.productId] = min(starts[e.productId] ?? e.date, e.date)
        }
        let sorted = starts.values.sorted()
        for (a, b) in zip(sorted, sorted.dropFirst()) {
            XCTAssertGreaterThanOrEqual(a.daysUntil(b), RecommendationConfig().allergenGapDays, "allergen gap \(a) → \(b)")
        }
        XCTAssertFalse(sorted.isEmpty, "аллергены были")
    }

    func testEczemaChildGetsNoAllergens() throws {
        let run = simulate(profile: ["eczema": "yes"])
        try golden("simulation_eczema", run)
        XCTAssertTrue(run.entries.allSatisfy { RecTestKit.byId[$0.productId]!.allergenIds.isEmpty })
    }

    func testReactionCausesAPause() throws {
        let run = simulate(badOn: ["carrot"], days: 40)
        try golden("simulation_reaction", run)
        XCTAssertTrue(run.log.contains { $0.contains("Wait") })
    }
}

/// Алгоритмы из `Resources/recommendation/` (копия Android `shared/recommendation/`). Порт `StrategiesTest`.
final class StrategiesTests: XCTestCase {
    func testClassicJsonEqualsEngineDefaults() {
        // Значения по умолчанию в RecommendationConfig — это classic: эталон симуляции не должен поменяться.
        let d = RecommendationConfig(), c = Strategies.config(Strategies.byId(Strategies.classic))
        XCTAssertEqual(c.strategyId, d.strategyId)
        XCTAssertEqual(c.reactionPauseDays, d.reactionPauseDays)
        XCTAssertEqual(c.allergenGapDays, d.allergenGapDays)
        XCTAssertEqual(c.allergensAfterIntroduced, d.allergensAfterIntroduced)
        XCTAssertEqual(c.assumedAgeMonths, d.assumedAgeMonths)
        XCTAssertEqual(c.newCategoryAfterIntroduced, d.newCategoryAfterIntroduced)
        XCTAssertEqual(c.highRiskAllergens, d.highRiskAllergens)
        XCTAssertEqual(c.weightIntroOrder, d.weightIntroOrder)
        XCTAssertEqual(c.weightNewCategory, d.weightNewCategory)
        XCTAssertEqual(c.weightAllergenDue, d.weightAllergenDue)
        XCTAssertEqual(c.weightFavorite, d.weightFavorite)
        XCTAssertEqual(c.weightAgeFits, d.weightAgeFits)
        XCTAssertEqual(c.stages, d.stages)
        XCTAssertEqual(c.weightStage, d.weightStage)
        XCTAssertEqual(c.stageStepPenalty, d.stageStepPenalty)
        XCTAssertEqual(c.rules.map(\.name), d.rules.map(\.name))
    }

    func testAllStrategiesAreValid() {
        let ids = Strategies.all.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "id уникальны")
        XCTAssertTrue(ids.contains(Strategies.classic), "есть classic")
        for s in Strategies.all {
            let unknown = Set(s.scorers.keys).subtracting(Strategies.scorerKinds)
            XCTAssertTrue(unknown.isEmpty, "\(s.id): неизвестные виды баллов \(unknown) — сначала код на обеих платформах")
            XCTAssertTrue([s.title, s.description].allSatisfy { $0["ru"] != nil && $0["en"] != nil }, "\(s.id): нужны title/description ru и en")
            XCTAssertTrue(["default", "experiment", "available"].contains(s.status), "\(s.id): статус")
            for st in s.scorers["stages"]?.stages ?? [] {
                XCTAssertTrue(st.reason["ru"] != nil && st.reason["en"] != nil, "\(s.id)/\(st.id): причина ru и en")
                for id in st.products { XCTAssertNotNil(RecTestKit.byId[id], "\(s.id)/\(st.id): нет продукта \(id) в каталоге") }
                XCTAssertTrue((1...max(st.products.count, 1)).contains(st.need) && !st.products.isEmpty, "\(s.id)/\(st.id): need в пределах списка")
            }
            XCTAssertGreaterThanOrEqual(Strategies.config(s).allergensAfterIntroduced, Strategies.safety.minIntroducedBeforeAllergens,
                                        "\(s.id): слой безопасности не опускается")
        }
        XCTAssertEqual(Strategies.all.filter { $0.status == "default" }.count, 1, "ровно один default")
    }

    func testUnknownIdFallsBackToClassic() {
        XCTAssertEqual(Strategies.byId("removed-in-new-version").id, Strategies.classic)
    }
}
