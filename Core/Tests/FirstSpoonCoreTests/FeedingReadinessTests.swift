import XCTest
@testable import FirstSpoonCore

/// Итог онбординга — Android docs/product-rules.md «Онбординг» (те же кейсы, что `FeedingReadinessTest`).
final class FeedingReadinessTests: XCTestCase {
    private let today = LocalDate(2026, 11, 20)
    private typealias A = ProfileQuestion.Answer
    private func born(_ months: Int) -> LocalDate { today.minusMonths(months).minusDays(3) }
    private func eval(_ months: Int?, _ head: String? = nil, _ sits: String? = nil, known: Set<String> = []) -> FeedingReadiness.Result {
        var p: [String: String] = [:]
        p[ProfileQuestion.headControl.key] = head; p[ProfileQuestion.sits.key] = sits
        return FeedingReadiness.evaluate(birthDate: months.map(born), profile: ChildProfile(p), knownFoods: known, today: today)
    }

    func testAlreadyEatingWinsOverEverything() {
        XCTAssertEqual(eval(3, A.no, A.no, known: ["zucchini"]), .alreadyStarted)
    }

    func testYoungerThan6MonthsIsTooEarly() {
        XCTAssertEqual(eval(3, A.yes, A.yes), .tooEarly)
        XCTAssertEqual(eval(5, A.yes, A.yes), .tooEarly)
    }

    func testNoHeadControlOrNoSittingIsNotYet() {
        XCTAssertEqual(eval(7, A.no, A.yes), .notYet)
        XCTAssertEqual(eval(7, A.yes, A.no), .notYet)
    }

    func testNotSureOrUnansweredMeansCheckWithDoctor() {
        XCTAssertEqual(eval(7, A.notSure, A.yes), .checkWithDoctor)
        XCTAssertEqual(eval(7), .checkWithDoctor)
    }

    func testSixMonthsAndSkillsPresentReady() {
        XCTAssertEqual(eval(6, A.yes, A.yes), .ready)
        XCTAssertEqual(eval(nil, A.yes, A.yes), .ready, "без даты рождения — по навыкам")
    }

    func testCurrentTreatsLegacyChildrenAsReady() {
        XCTAssertNil(FeedingReadiness.current(birthDate: born(5), profile: ChildProfile(), started: false, today: today))
        XCTAssertTrue(FeedingReadiness.canOfferNewFoods(nil))
        XCTAssertEqual(FeedingReadiness.current(birthDate: born(5), profile: ChildProfile(["head_control": "no"]), started: true, today: today),
                       .alreadyStarted)
    }

    func testCodesMatchAndroid() {
        XCTAssertEqual(FeedingReadiness.Result.allCases.map(\.rawValue), ["started", "too_early", "not_yet", "check", "ready"])
    }

    func testKnownFoodChoicesAreUniqueAndInCatalog() throws {
        XCTAssertEqual(Set(FeedingReadiness.knownFoodsChoices).count, 19)
        let ids = Set(RecTestKit.catalog.map(\.id))
        for id in FeedingReadiness.knownFoodsChoices { XCTAssertTrue(ids.contains(id), id) }
    }
}
