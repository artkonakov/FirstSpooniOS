import XCTest
@testable import FirstSpoonCore

/// Каталог событий и docs/analytics.md совпадают; имена корректны и те же, что в Android; трекеры получают события.
final class AnalyticsCatalogTests: XCTestCase {
    private let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    override func tearDown() { Analytics.install([]) }

    func testNamesAreUniqueSnakeCase() {
        let names = AnalyticsEvent.allNames
        XCTAssertFalse(names.isEmpty)
        XCTAssertEqual(names.count, Set(names).count, "повторяющиеся имена")
        for n in names { XCTAssertNotNil(n.range(of: "^[a-z][a-z0-9_]{1,63}$", options: .regularExpression), n) }
    }

    func testEveryEventIsDocumentedAndEveryDocumentedEventExists() throws {
        let doc = try String(contentsOf: root.appendingPathComponent("docs/analytics.md"), encoding: .utf8)
        let re = try NSRegularExpression(pattern: "(?m)^\\| `([^`]+)` \\|")
        let docNames = re.matches(in: doc, range: NSRange(doc.startIndex..., in: doc))
            .map { String(doc[Range($0.range(at: 1), in: doc)!]) }
        XCTAssertEqual(AnalyticsEvent.allNames.sorted(), docNames.sorted(),
                       "docs/analytics.md и AnalyticsEvent расходятся — добавьте/уберите строку в таблице «События»")
    }

    /// Имена у каждого case совпадают со списком `allNames` (новый case не забыт в списке).
    func testAllNamesCoverCases() {
        let samples: [AnalyticsEvent] = [
            .guestStarted, .login(fromGuest: true), .emailLinked, .logout, .accountDeleted,
            .onboardingCompleted, .childAdded, .entryAdded, .productMarked(mark: .known), .customProductAdded,
            .recommendationRecord, .recommendationOther,
            .paywallOpened, .purchaseStarted(product: "p"), .purchaseCompleted(product: "p"), .purchaseFailed(product: "p"), .restoreTapped,
        ]
        XCTAssertEqual(samples.map(\.name), AnalyticsEvent.allNames)
    }

    /// Каталог совпадает с Android, если Android-проект лежит рядом (иначе тест пропускается).
    func testSameNamesAsAndroid() throws {
        let android = root.deletingLastPathComponent()
            .appendingPathComponent("FirstSpoon Android/app/src/main/java/com/firstspoon/app/core/analytics/AnalyticsEvent.kt")
        guard let source = try? String(contentsOf: android, encoding: .utf8) else { throw XCTSkip("нет Android-проекта рядом") }
        let re = try NSRegularExpression(pattern: "AnalyticsEvent\\(\"([^\"]+)\"")
        let names = re.matches(in: source, range: NSRange(source.startIndex..., in: source))
            .map { String(source[Range($0.range(at: 1), in: source)!]) }
        XCTAssertEqual(AnalyticsEvent.allNames.sorted(), names.sorted(), "каталог событий разошёлся с Android")
    }

    func testTrackReachesTrackersWithParams() {
        final class Fake: AnalyticsTracker, @unchecked Sendable { var seen: [AnalyticsEvent] = []; func track(_ e: AnalyticsEvent) { seen.append(e) } }
        let fake = Fake()
        Analytics.install([fake])
        Analytics.track(.login(fromGuest: true))
        XCTAssertEqual(fake.seen, [.login(fromGuest: true)])
        XCTAssertEqual(fake.seen.first?.params, ["from_guest": .bool(true)])
        XCTAssertEqual(AnalyticsEvent.productMarked(mark: .allergy).params, ["mark": .string("allergy")])
    }

    func testNoTrackersNothingHappens() { Analytics.track(.guestStarted) }
}
