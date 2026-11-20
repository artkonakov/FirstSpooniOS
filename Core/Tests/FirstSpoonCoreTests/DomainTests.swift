import XCTest
@testable import FirstSpoonCore

final class LocalDateTests: XCTestCase {
    func testRoundTripAndArithmetic() {
        let d = LocalDate(2026, 11, 11)
        XCTAssertEqual(d.iso, "2026-11-11")
        XCTAssertEqual(LocalDate.parse("2026-11-11"), d)
        XCTAssertEqual(LocalDate(1970, 1, 1).epochDay, 0)
        XCTAssertEqual(LocalDate(2026, 1, 31).plusMonths(1), LocalDate(2026, 2, 28))
        XCTAssertEqual(LocalDate(2024, 3, 31).minusMonths(1), LocalDate(2024, 2, 29))
        XCTAssertEqual(LocalDate(2026, 3, 1).minusMonths(14), LocalDate(2025, 1, 1))
        XCTAssertNil(LocalDate.parse("2026-02-30"))
    }

    func testMonthsBetweenLikeJavaPeriod() {
        XCTAssertEqual(LocalDate(2026, 5, 8).monthsUntil(LocalDate(2026, 11, 11)), 6)
        XCTAssertEqual(LocalDate(2026, 5, 12).monthsUntil(LocalDate(2026, 11, 11)), 5)
        XCTAssertEqual(LocalDate(2026, 5, 11).monthsUntil(LocalDate(2026, 11, 11)), 6)
    }

    func testDateTimeDaysBetweenTruncates() {
        let a = LocalDateTime(2026, 11, 1, 15, 0)
        XCTAssertEqual(a.daysUntil(LocalDateTime(2026, 11, 15, 14, 59)), 13)
        XCTAssertEqual(a.daysUntil(LocalDateTime(2026, 11, 15, 15, 0)), 14)
        XCTAssertEqual(LocalDateTime(2026, 11, 11, 23, 0).plusHours(2), LocalDateTime(2026, 11, 12, 1, 0))
    }
}

final class ChildProfileTests: XCTestCase {
    func testMultiTogglesAndSerializesSorted() {
        let p = ChildProfile().toggleMulti(.knownAllergens, "milk").toggleMulti(.knownAllergens, "egg")
        XCTAssertEqual(p.toMap()["known_allergens"], "egg,milk")
        XCTAssertEqual(p.toggleMulti(.knownAllergens, "egg").knownAllergens, ["milk"])
        XCTAssertTrue(p.toggleMulti(.knownAllergens, "egg").toggleMulti(.knownAllergens, "milk").toMap().isEmpty)
    }

    func testSingleTogglesOffOnRepeat() {
        let p = ChildProfile().toggleSingle(.eczema, ProfileQuestion.Answer.yes)
        XCTAssertTrue(p.hasEczema)
        XCTAssertFalse(p.toggleSingle(.eczema, ProfileQuestion.Answer.yes).isAnswered(.eczema))
    }

    func testUnknownKeysSurviveRoundTrip() {
        let p = ChildProfile.fromMap(["future_question": "x"]).toggleSingle(.eczema, ProfileQuestion.Answer.no)
        XCTAssertEqual(ChildProfile.fromMap(p.toMap()).answers["future_question"], "x")
    }
}

final class FeedingRulesTests: XCTestCase {
    private var nextId = 1
    private func entry(_ product: String, _ reaction: Reaction = .unknown) -> DiaryEntry {
        defer { nextId += 1 }
        return DiaryEntry(id: "e\(nextId)", productId: product, date: LocalDate(2026, 11, 8), reaction: reaction)
    }
    private func status(_ entries: [DiaryEntry], _ mark: ProductMark? = nil) -> ProductStatus {
        FeedingRules.progressOf("x", entries, mark: mark).status
    }

    func testNoEntriesNotTried() { XCTAssertEqual(status([]), .notTried) }

    func testOneOrTwoTriesInProgress() {
        let p = FeedingRules.progressOf("x", [entry("x"), entry("x", .none)])
        XCTAssertEqual(p.status, .inProgress)
        XCTAssertEqual(p.tries, 2)
    }

    func testThreeTriesWithoutReactionIntroduced() {
        XCTAssertEqual(status((0..<3).map { _ in entry("x", .none) }), .introduced)
        XCTAssertEqual(status((0..<3).map { _ in entry("x", .good) }), .introduced)
    }

    func testExtraTriesCappedBySeriesTarget() {
        XCTAssertEqual(FeedingRules.progressOf("x", (0..<5).map { _ in entry("x") }).tries, FeedingRules.seriesTarget)
    }

    func testBadOrUnsureReactionNeedsAttentionAndWinsOverSeries() {
        XCTAssertEqual(status((0..<3).map { _ in entry("x", .none) } + [entry("x", .reaction)]), .reaction)
        XCTAssertEqual(status([entry("x", .unsure)]), .reaction)
    }

    func testKnownMarkCountsAsIntroducedWithoutTries() { XCTAssertEqual(status([], .known), .introduced) }

    func testReactionAfterKnownMarkStillNeedsAttention() { XCTAssertEqual(status([entry("x", .reaction)], .known), .reaction) }

    func testAllergyAndExcludedMarksWinOverEverything() {
        let tries = (0..<3).map { _ in entry("x", .good) }
        XCTAssertEqual(status(tries, .allergy), .allergy)
        XCTAssertEqual(status(tries, .excluded), .excluded)
    }

    func testMarkedProductsWithoutEntriesAreIncludedInProgressMap() {
        let map = FeedingRules.progressByProduct([entry("a"), entry("a")], marks: ["b": .known])
        XCTAssertEqual(map["a"]?.tries, 2)
        XCTAssertEqual(map["b"]?.status, .introduced)
    }

    func testAttentionCoversReactionAndAllergyOnly() {
        XCTAssertTrue(ProductStatus.reaction.needsAttention)
        XCTAssertTrue(ProductStatus.allergy.needsAttention)
        XCTAssertFalse(ProductStatus.excluded.needsAttention)
        XCTAssertFalse(ProductStatus.inProgress.needsAttention)
    }
}

final class ReminderRulesTests: XCTestCase {
    private let now = LocalDateTime(2026, 11, 11, 15, 0)
    private var n = 0
    private func entry(_ product: String, _ date: LocalDate) -> DiaryEntry {
        defer { n += 1 }
        return DiaryEntry(id: "e\(n)", productId: product, date: date)
    }
    private func input(_ entries: [DiaryEntry] = [], onboardedAt: LocalDateTime?? = .none, enabled: Bool = true,
                       marks: [String: ProductMark] = [:]) -> ReminderInput {
        let onboarded: LocalDateTime? = onboardedAt ?? now.minusHours(1)
        return ReminderInput(now: now, enabled: enabled, onboardedAt: onboarded, childName: "Миша", entries: entries,
                             marks: marks, productNames: ["broccoli": "Брокколи", "pumpkin": "Тыква"])
    }
    private func kinds(_ i: ReminderInput) -> [ReminderKind] { ReminderRules.plan(i).map(\.kind) }

    func testNothingWhenDisabled() { XCTAssertTrue(ReminderRules.plan(input(enabled: false)).isEmpty) }

    func testWithoutOnboardingTimeOnlyFirstEntryIsSkipped() {
        XCTAssertTrue(ReminderRules.plan(input(onboardedAt: .some(nil))).isEmpty)
        XCTAssertEqual(kinds(input([entry("broccoli", now.toLocalDate())], onboardedAt: .some(nil))), [.continueSeries])
    }

    func testFirstEntryReminder24hAfterOnboarding() {
        let plan = ReminderRules.plan(input())
        XCTAssertEqual(plan.count, 1)
        XCTAssertEqual(plan[0].kind, .firstEntry)
        XCTAssertEqual(plan[0].fireAt, now.minusHours(1).plusHours(24))
    }

    func testFirstEntryDisappearsAfterAnyEntry() {
        XCTAssertEqual(kinds(input([entry("broccoli", now.toLocalDate())])), [.continueSeries])
    }

    func testFirstEntryGivesUpAfterTwoWeeks() {
        XCTAssertTrue(ReminderRules.plan(input(onboardedAt: .some(now.minusDays(15)))).isEmpty)
    }

    func testSeriesReminderNextMorningOnlyForTheActiveSeries() {
        let today = now.toLocalDate()
        // Одна серия за раз: брокколи ближе к введению (2 пробы) — напоминаем только о ней.
        let plan = ReminderRules.plan(input([entry("pumpkin", today), entry("broccoli", today.minusDays(1)), entry("broccoli", today)]))
        XCTAssertEqual(plan.count, 1)
        XCTAssertEqual(plan[0].fireAt, today.plusDays(1).atTime(10, 0))
        XCTAssertEqual(plan[0].productNames, ["Брокколи"])
    }

    func testNoSeriesReminderDuringThePauseAfterAReaction() {
        let today = now.toLocalDate()
        let entries = [entry("broccoli", today.minusDays(1)), DiaryEntry(id: "r", productId: "pumpkin", date: today, reaction: .reaction)]
        let plan = ReminderRules.plan(input(entries))
        XCTAssertEqual(plan.count, 1)
        // Пауза 3 дня от реакции: напомним утром в день, когда она закончится.
        XCTAssertEqual(plan[0].fireAt, today.plusDays(3).atTime(10, 0))
    }

    func testNoSeriesReminderForIntroducedOrMarkedProducts() {
        let d = now.toLocalDate()
        XCTAssertTrue(kinds(input((0..<3).map { _ in entry("broccoli", d) })).isEmpty)
        XCTAssertTrue(kinds(input([entry("broccoli", d)], marks: ["broccoli": .excluded])).isEmpty)
    }

    func testOverdueSeriesFiresNextMorningStaleSeriesIsDropped() {
        let plan = ReminderRules.plan(input([entry("broccoli", now.toLocalDate().minusDays(3))]))
        XCTAssertEqual(plan.count, 1)
        XCTAssertEqual(plan[0].fireAt, now.toLocalDate().plusDays(1).atTime(10, 0))
        XCTAssertTrue(ReminderRules.plan(input([entry("broccoli", now.toLocalDate().minusDays(8))])).isEmpty)
    }

    func testQuietHoursMoveTheTimeToTheMorning() {
        XCTAssertEqual(ReminderRules.schedule(LocalDateTime(2026, 11, 11, 21, 30), now: now), LocalDateTime(2026, 11, 12, 10, 0))
        XCTAssertEqual(ReminderRules.schedule(LocalDateTime(2026, 11, 12, 6, 0), now: now), LocalDateTime(2026, 11, 12, 10, 0))
        let day = LocalDateTime(2026, 11, 12, 13, 0)
        XCTAssertEqual(ReminderRules.schedule(day, now: now), day)
    }
}

final class AppLocaleTests: XCTestCase {
    func testRussianAndCisLanguagesGetRussian() {
        for lang in ["ru-RU", "ru", "be-BY", "uk-UA", "kk-KZ", "ky", "uz-Cyrl-UZ", "uz-Latn", "tg", "tk", "hy-AM", "az-AZ", "ka-GE"] {
            XCTAssertEqual(AppLocale.resolve(preferredLanguages: [lang, "en-US"]), .ru, lang)
        }
    }

    func testEverythingElseGetsEnglish() {
        for lang in ["en-US", "en-GB", "de-DE", "fr", "zh-Hans-CN", "pl-PL", "lv", "et"] {
            XCTAssertEqual(AppLocale.resolve(preferredLanguages: [lang, "ru-RU"]), .en, lang)
        }
        XCTAssertEqual(AppLocale.resolve(preferredLanguages: []), .en)
    }

    /// Решает первый язык телефона, а не «есть ли русский где-то в списке».
    func testOnlyFirstLanguageCounts() {
        XCTAssertEqual(AppLocale.resolve(preferredLanguages: ["kk-KZ", "en-US"]), .ru)
        XCTAssertEqual(AppLocale.resolve(preferredLanguages: ["en-US", "kk-KZ"]), .en)
    }
}
