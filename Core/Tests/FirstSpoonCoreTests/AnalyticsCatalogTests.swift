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
            .entryUpdated(food: .custom), .entryDeleted(food: .custom), .entryReactionChanged(food: .custom),
            .productOpened(food: .custom), .productFavoriteChanged(food: .custom, liked: true),
            .productMarkRemoved(food: .custom), .customProductDeleted, .onboardingOptionChanged(option: .sex(.female), selected: true),
            .assistantOpened(source: .home), .assistantHistoryOpened, .assistantChatCreated, .assistantChatSelected, .assistantChatDeleted,
            .assistantMessageSent, .assistantReplyReceived, .assistantRequestFailed(reason: .network), .assistantRequestStopped,
            .assistantAnswerCopied, .assistantShareOpened, .deviceSessionsFailed(operation: .list),
            .diarySyncEnabled, .diarySyncDisabled, .deviceSessionsOpened, .deviceSessionRevoked,
            .themeChanged(mode: .dark), .legalDocumentOpened(document: .privacy), .assistantSourceOpened, .assistantRetried,
            .assistantFeedbackTapped(vote: .like),
            .welcomeShown, .guestStarted, .login(fromGuest: true), .emailLinked, .logout, .accountDeleted,
            .onboardingStep(step: "name"), .onboardingBackToWelcome, .onboardingCompleted(readiness: .ready, knownFoods: 0), .readyMarked, .childAdded, .entryAdded(food: .custom), .productMarked(mark: .known), .customProductAdded,
            .recommendationRecord, .recommendationOther, .statsOpened,
            .diaryExported(photos: "none"), .entryPhotoAdded, .childPhotoSet, .customProductPhotoSet, .networkBlockedShown,
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
        XCTAssertEqual(AnalyticsEvent.onboardingCompleted(readiness: .notYet, knownFoods: 3).params,
                       ["readiness": .string("not_yet"), "known_foods": .int(3)])
    }

    func testNoTrackersNothingHappens() { Analytics.track(.guestStarted) }
}
