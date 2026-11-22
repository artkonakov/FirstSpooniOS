import XCTest
@testable import FirstSpoonCore

/// Порт Android `FeedingStatsTest`: статусы, месяцы от первой пробы до текущего, сетка месяца и пустые состояния.
final class FeedingStatsTests: XCTestCase {
    private let today = LocalDate(2026, 11, 22)

    private func entry(_ id: String, _ product: String, _ date: LocalDate, _ reaction: Reaction = .good) -> DiaryEntry {
        DiaryEntry(id: id, productId: product, date: date, reaction: reaction)
    }

    func testIntroducedReactionAndExcludedFollowFeedingRules() {
        let entries = [
            entry("1", "broccoli", today.minusDays(10)),
            entry("2", "broccoli", today.minusDays(8)),
            entry("3", "broccoli", today.minusDays(6)),
            entry("4", "peach", today.minusDays(5), .reaction),
            entry("5", "pear", today),
        ]
        let stats = FeedingStats.build(entries: entries,
                                       marks: ["yogurt": .allergy, "cream": .excluded], today: today)
        XCTAssertEqual(stats.introduced, ["broccoli"])
        XCTAssertEqual(Set(stats.attention), Set(["peach", "yogurt"]))
        XCTAssertEqual(stats.excluded, ["cream"])
        // Пробы 10 дней назад — уже в ноябре: один месяц.
        XCTAssertEqual(stats.months.map(\.key), ["2026-11"])
    }

    func testMonthsSpanFromFirstTryToCurrentNewestFirst() {
        let entries = [
            entry("1", "zucchini", LocalDate(2026, 8, 3)),
            entry("2", "broccoli", LocalDate(2026, 9, 10)),
            entry("3", "pear", LocalDate(2026, 11, 2)),
        ]
        let stats = FeedingStats.build(entries: entries, marks: [:], today: today)
        XCTAssertEqual(stats.months.map(\.key), ["2026-11", "2026-10", "2026-09", "2026-08"])
        // Сводки по месяцам считаются по настоящим дням месяца.
        XCTAssertEqual(stats.months[0].totalTries, 1)
        XCTAssertEqual(stats.months[0].activeDays, 1)
        XCTAssertEqual(stats.months[2].totalTries, 1)
        XCTAssertTrue(stats.months[1].cells.allSatisfy { $0.bar == nil })
    }

    func testFirstMonthGridStartsMondayAndShowsOnlyRealDays() throws {
        let stats = FeedingStats.build(
            entries: [entry("1", "zucchini", LocalDate(2026, 9, 3))],
            marks: [:], today: today,
        )
        // Сентябрь 2026 начинается со вторника → понедельник 31.08 заполняет первую неделю.
        let september = try XCTUnwrap(stats.months.first { $0.key == "2026-09" })
        XCTAssertEqual(september.key, "2026-09")
        XCTAssertEqual(september.cells.first?.date, LocalDate(2026, 8, 31))
        XCTAssertEqual(september.cells[0].inMonth, false)
        XCTAssertEqual(september.cells[1].date, LocalDate(2026, 9, 1))
        XCTAssertEqual(september.cells[1].inMonth, true)
        XCTAssertEqual(september.cells.first { $0.date == LocalDate(2026, 9, 3) }?.bar?.productIds, ["zucchini"])
        XCTAssertEqual(september.cells.count % 7, 0)
    }

    func testCurrentMonthMarksFutureDaysAsFuture() {
        let stats = FeedingStats.build(entries: [entry("1", "pear", today)], marks: [:], today: today)
        let november = stats.months[0]
        XCTAssertEqual(november.key, "2026-11")
        // Сегодня и раньше — не будущие; 23 ноября и дальше — будущие.
        XCTAssertTrue(november.cells.first { $0.date == today }?.inMonth == true)
        XCTAssertTrue(november.cells.first { $0.date == today }?.isFuture == false)
        XCTAssertTrue(november.cells.first { $0.date == LocalDate(2026, 11, 23) }?.isFuture == true)
        // Сводка считает только прошедшие дни месяца.
        XCTAssertEqual(november.totalTries, 1)
        XCTAssertEqual(november.activeDays, 1)
    }

    func testMonthPaddingDoesNotRepeatTriesFromNeighboringMonths() throws {
        let august = LocalDate(2026, 8, 31)
        let october = LocalDate(2026, 10, 1)
        let stats = FeedingStats.build(entries: [entry("1", "pear", august), entry("2", "peach", october, .reaction)],
                                       marks: [:], today: today)
        let september = try XCTUnwrap(stats.months.first { $0.key == "2026-09" })
        XCTAssertEqual(september.totalTries, 0)
        XCTAssertNil(september.cells.first { $0.date == august }?.bar)
        XCTAssertNil(september.cells.first { $0.date == october }?.bar)
        XCTAssertEqual(stats.months.first { $0.key == "2026-10" }?.totalTries, 1)
    }

    func testFutureOnlyHistoryDoesNotMakeTheDiaryLookEmpty() {
        let stats = FeedingStats.build(entries: [entry("1", "pear", today.plusDays(1))], marks: [:], today: today)
        XCTAssertFalse(stats.isEmpty)
        XCTAssertEqual(stats.months.map(\.key), ["2026-11"])
        XCTAssertTrue(stats.months[0].cells.allSatisfy { $0.bar == nil })
    }

    func testEmptyDiaryHasOneEmptyMonth() {
        let stats = FeedingStats.build(entries: [], marks: [:], today: today)
        XCTAssertTrue(stats.isEmpty)
        XCTAssertEqual(stats.months.map(\.key), ["2026-11"])
        XCTAssertTrue(stats.months[0].cells.allSatisfy { $0.bar == nil })
        XCTAssertEqual(stats.months[0].totalTries, 0)
    }

    func testMarksWithoutTriesAreNotEmpty() {
        let stats = FeedingStats.build(entries: [], marks: ["egg": .known], today: today)
        XCTAssertFalse(stats.isEmpty)
        XCTAssertEqual(stats.introduced, ["egg"])
        XCTAssertEqual(stats.months.map(\.key), ["2026-11"])
    }
}
