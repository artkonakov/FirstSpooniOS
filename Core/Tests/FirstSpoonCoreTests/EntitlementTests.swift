import XCTest
@testable import FirstSpoonCore

final class EntitlementTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-11-14T12:00:00Z")!
    private func days(_ n: Double) -> TimeInterval { n * 86400 }
    private func device(_ expires: Date?, product: String = Plus.monthly, trial: Bool = false) -> StoreSubscription {
        StoreSubscription(productId: product, expiresAt: expires, inTrial: trial)
    }
    private func server(_ expires: Date?, store: String = "rustore", product: String = Plus.monthly) -> StoreSubscription {
        StoreSubscription(productId: product, expiresAt: expires, source: store)
    }

    func testNoSubscriptionIsNotActive() {
        XCTAssertFalse(Entitlement.none.isActive(now))
        XCTAssertNil(Entitlement.none.current(now))
    }

    func testActiveBeforeExpiryAndWithinOfflineGraceAfterIt() {
        let e = Entitlement(device: [device(now + days(1))])
        XCTAssertTrue(e.isActive(now))
        XCTAssertTrue(e.isActive(now + days(1) + Plus.offlineGrace - 1))
        XCTAssertFalse(e.isActive(now + days(1) + Plus.offlineGrace))
    }

    func testSubscriptionWithoutExpiryDateIsActive() {
        XCTAssertTrue(Entitlement(server: [server(nil)]).isActive(now))
    }

    func testUnavailableSourcesKeepCachedData() {
        let cached = Entitlement(device: [device(now + days(5))], server: [server(nil)], checkedAt: now - days(2))
        XCTAssertEqual(Entitlement.resolve(cached: cached, fromDevice: nil, fromServer: nil, now: now), cached)
    }

    func testStoreSaysNoSubscriptionsRevokesOnlyDevicePart() {
        let cached = Entitlement(device: [device(now + days(5))], server: [server(nil)])
        let r = Entitlement.resolve(cached: cached, fromDevice: [], fromServer: nil, now: now)
        XCTAssertTrue(r.device.isEmpty)
        XCTAssertTrue(r.isActive(now))
        XCTAssertEqual(r.checkedAt, now)
    }

    func testServerSubscriptionGivesPlusWithoutStoreOnDevice() {
        let r = Entitlement.resolve(cached: .none, fromDevice: [], fromServer: [server(nil)], now: now)
        XCTAssertTrue(r.isActive(now))
        XCTAssertEqual(r.current(now)?.source, "rustore")
    }

    func testServerSaysNothingRevokesServerPart() {
        let cached = Entitlement(server: [server(nil)])
        XCTAssertFalse(Entitlement.resolve(cached: cached, fromDevice: nil, fromServer: [], now: now).isActive(now))
    }

    func testForeignProductsFromDeviceAreIgnoredServerOnesAreNot() {
        let r = Entitlement(device: [device(now + days(30), product: "other_app_sub")],
                            server: [server(now + days(30), store: "web", product: "plus_web_year")])
        XCTAssertEqual(r.subscriptions.map(\.productId), ["plus_web_year"])
        XCTAssertTrue(r.isActive(now))
    }

    func testTwoStoresAtOnceShowsTheOneThatLastsLongest() {
        let r = Entitlement(device: [device(now + days(3), trial: true), device(now + days(40))],
                            server: [server(now + days(200), store: "web")])
        XCTAssertEqual(r.current(now)?.source, "web")
        XCTAssertEqual(r.current(now)?.expiresAt, now + days(200))
    }

    func testPrefersKnownEndDateForDisplay() {
        let r = Entitlement(device: [device(now + days(10))], server: [server(nil)])
        XCTAssertEqual(r.current(now)?.source, StoreSubscription.sourceDevice)
    }

    func testExpiredDeviceSubscriptionDoesNotHideActiveServerOne() {
        let r = Entitlement(device: [device(now - days(10))], server: [server(nil)])
        XCTAssertTrue(r.isActive(now))
        XCTAssertEqual(r.current(now)?.source, "rustore")
    }

    func testDevicePurchaseUnknownToServerIsToBeClaimed() {
        let d = [StoreSubscription(productId: Plus.monthly, expiresAt: nil, purchaseId: "p1"),
                 StoreSubscription(productId: Plus.halfYear, expiresAt: nil, purchaseId: "p2")]
        let s = [StoreSubscription(productId: Plus.halfYear, expiresAt: nil, source: "rustore", purchaseId: "p2")]
        XCTAssertEqual(Entitlement.unclaimed(fromDevice: d, fromServer: s), ["p1"])
    }

    func testNothingToClaimWhenASourceIsUnavailableOrPurchaseIdUnknown() {
        let d = [StoreSubscription(productId: Plus.monthly, expiresAt: nil, purchaseId: "p1")]
        XCTAssertEqual(Entitlement.unclaimed(fromDevice: d, fromServer: nil), [])
        XCTAssertEqual(Entitlement.unclaimed(fromDevice: nil, fromServer: []), [])
        XCTAssertEqual(Entitlement.unclaimed(fromDevice: [device(nil)], fromServer: []), [])
    }

    func testHoldSubscriptionGivesNoPlusAndExplainsWhy() {
        let e = Entitlement(device: [StoreSubscription(productId: Plus.monthly, expiresAt: now + days(10), issue: .hold)])
        XCTAssertFalse(e.isActive(now))
        XCTAssertEqual(e.billingIssue(now), .hold)
    }

    func testGraceKeepsPlusWithAWarning() {
        let e = Entitlement(server: [StoreSubscription(productId: Plus.monthly, expiresAt: nil, source: "rustore", issue: .grace)])
        XCTAssertTrue(e.isActive(now))
        XCTAssertEqual(e.billingIssue(now), .grace)
    }

    func testNoWarningWhenAnotherSubscriptionIsFine() {
        let grace = StoreSubscription(productId: Plus.monthly, expiresAt: nil, source: "rustore", issue: .grace)
        let hold = StoreSubscription(productId: Plus.monthly, expiresAt: nil, issue: .hold)
        XCTAssertNil(Entitlement(device: [device(now + days(5))], server: [grace]).billingIssue(now))
        XCTAssertNil(Entitlement(device: [hold], server: [server(nil, store: "web")]).billingIssue(now))
        XCTAssertNil(Entitlement.none.billingIssue(now))
    }
}

final class OfferMathTests: XCTestCase {
    private let monthly = SubscriptionOffer(productId: Plus.monthly, title: "", price: "299 ₽", periodMonths: 1, priceKopecks: 29_900, trialDays: 3)
    private let halfYear = SubscriptionOffer(productId: Plus.halfYear, title: "", price: "1 049 ₽", periodMonths: 6, priceKopecks: 104_900,
                                             starter: StarterOffer(price: "49 ₽", months: 1))

    func testMonthlyPriceOfHalfYear() { XCTAssertEqual(halfYear.monthlyRubles(), 174) }
    func testHalfYearSaves41PercentVsMonthly() { XCTAssertEqual(halfYear.savingsPercent(vs: monthly), 41) }
    func testNoSavingsForTheSameOrShorterPeriod() {
        XCTAssertNil(monthly.savingsPercent(vs: halfYear))
        XCTAssertNil(monthly.savingsPercent(vs: monthly))
    }
    func testNoSavingsWithoutNumericPrice() {
        var h = halfYear; h.priceKopecks = nil
        XCTAssertNil(h.savingsPercent(vs: monthly))
    }
}

final class StoreFormatTests: XCTestCase {
    func testFormatsRubles() {
        XCTAssertEqual(formatRubles(4_900), "49\u{00A0}₽")
        XCTAssertEqual(formatRubles(104_900), "1\u{00A0}049\u{00A0}₽")
        XCTAssertEqual(formatRubles(29_950), "299,50\u{00A0}₽")
    }

    func testParsesStorePeriods() {
        XCTAssertEqual(StorePeriod.parse("P1M"), StorePeriod(months: 1, days: 0))
        XCTAssertEqual(StorePeriod.parse("P6M"), StorePeriod(months: 6, days: 0))
        XCTAssertEqual(StorePeriod.parse("P1Y"), StorePeriod(months: 12, days: 0))
        XCTAssertEqual(StorePeriod.parse("P3D"), StorePeriod(months: 0, days: 3))
        XCTAssertNil(StorePeriod.parse("garbage"))
    }
}
