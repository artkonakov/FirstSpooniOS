import Foundation

/// Подписка «Ложку за маму Плюс» — чистая логика без StoreKit.
/// На первом этапе iOS-версии покупки нет (StoreKit — позже); логика перенесена, чтобы права работали так же, как в Android.
///
/// Права доступа (`Entitlement`) — единственный источник правды «есть ли Плюс». Платные функции спрашивают
/// только его, а не магазин или сервер напрямую.
public enum Plus {
    /// Месяц: пробный период 3 дня, далее 299 ₽ в месяц.
    public static let monthly = "plus_monthly"
    /// Полгода: первый месяц за 49 ₽ (стартовый период), далее 1049 ₽ за 6 месяцев.
    public static let halfYear = "plus_6months"
    /// Порядок показа на пейволе.
    public static let all = [halfYear, monthly]
    /// Тариф, выбранный на пейволе по умолчанию.
    public static let `default` = halfYear
    /// Сколько доверяем сохранённому статусу без связи с магазином после окончания оплаченного периода.
    public static let offlineGrace: TimeInterval = 3 * 24 * 3600
}

/// Тариф, как его вернул магазин. Цены — строки магазина (уже с валютой), в коде их не хардкодим.
public struct SubscriptionOffer: Hashable, Sendable {
    public var productId: String
    public var title: String
    /// Обычная цена за `periodMonths`, как её показывает магазин.
    public var price: String
    public var periodMonths: Int
    /// Та же цена числом (в копейках); nil, если магазин не дал.
    public var priceKopecks: Int64?
    public var trialDays: Int?
    /// Стартовый период: одна оплата за весь срок.
    public var starter: StarterOffer?

    public init(productId: String, title: String, price: String, periodMonths: Int, priceKopecks: Int64? = nil,
                trialDays: Int? = nil, starter: StarterOffer? = nil) {
        self.productId = productId; self.title = title; self.price = price; self.periodMonths = periodMonths
        self.priceKopecks = priceKopecks; self.trialDays = trialDays; self.starter = starter
    }

    /// Цена в месяц в рублях (округлено вниз); nil — магазин не дал цену числом.
    public func monthlyRubles() -> Int64? { priceKopecks.map { $0 / Int64(periodMonths) / 100 } }

    /// На сколько процентов выгоднее помесячной оплаты `monthly` (по обычной цене). nil — сравнивать нечего или выгоды нет.
    public func savingsPercent(vs monthly: SubscriptionOffer) -> Int? {
        guard let mine = priceKopecks, let base = monthly.priceKopecks, periodMonths > monthly.periodMonths else { return nil }
        let full = base * Int64(periodMonths) / Int64(monthly.periodMonths)
        let pct = Int((full - mine) * 100 / full)
        return pct > 0 ? pct : nil
    }
}

public struct StarterOffer: Hashable, Sendable {
    public let price: String
    public let months: Int
    public init(price: String, months: Int) { self.price = price; self.months = months }
}

/// Магазин не смог списать оплату: `grace` — доступ ещё есть; `hold` — подписка приостановлена, доступа нет.
public enum BillingIssue: String, Sendable { case grace, hold }

/// Подписка по данным одного источника. `expiresAt == nil` — источник срок не сообщил (считаем действующей).
public struct StoreSubscription: Hashable, Sendable {
    public static let sourceDevice = "device"

    public var productId: String
    public var expiresAt: Date?
    public var inTrial: Bool
    public var source: String
    public var purchaseId: String?
    public var issue: BillingIssue?

    public init(productId: String, expiresAt: Date?, inTrial: Bool = false, source: String = StoreSubscription.sourceDevice,
                purchaseId: String? = nil, issue: BillingIssue? = nil) {
        self.productId = productId; self.expiresAt = expiresAt; self.inTrial = inTrial; self.source = source
        self.purchaseId = purchaseId; self.issue = issue
    }

    /// Без связи с источником — ещё `Plus.offlineGrace` после `expiresAt`. Приостановленная доступа не даёт.
    public func isActive(_ now: Date) -> Bool {
        issue != .hold && (expiresAt == nil || now < expiresAt!.addingTimeInterval(Plus.offlineGrace))
    }
}

/// Права доступа к Плюсу из двух источников (магазин на устройстве и наш сервер), каждый хранится локально.
public struct Entitlement: Hashable, Sendable {
    public var device: [StoreSubscription]
    public var server: [StoreSubscription]
    /// Когда последний раз ответил хоть один источник; nil — ни разу.
    public var checkedAt: Date?

    public init(device: [StoreSubscription] = [], server: [StoreSubscription] = [], checkedAt: Date? = nil) {
        self.device = device; self.server = server; self.checkedAt = checkedAt
    }

    public static let none = Entitlement()

    /// С устройства — только наши тарифы (`Plus.all`); с сервера — все.
    public var subscriptions: [StoreSubscription] { device.filter { Plus.all.contains($0.productId) } + server }
    public var hasSubscription: Bool { !subscriptions.isEmpty }
    public func isActive(_ now: Date) -> Bool { subscriptions.contains { $0.isActive(now) } }

    public func billingIssue(_ now: Date) -> BillingIssue? {
        let active = subscriptions.filter { $0.isActive(now) }
        if !active.isEmpty { return active.allSatisfy { $0.issue == .grace } ? .grace : nil }
        return subscriptions.contains { $0.issue == .hold } ? .hold : nil
    }

    /// Подписка для показа: из действующих — с самой поздней известной датой окончания, иначе любая действующая.
    public func current(_ now: Date) -> StoreSubscription? {
        let active = subscriptions.filter { $0.isActive(now) }
        var best: StoreSubscription?
        for s in active where s.expiresAt != nil {
            if best == nil || s.expiresAt! > best!.expiresAt! { best = s }
        }
        return best ?? active.first
    }

    /// Новые права после опроса источников. nil — источник недоступен: его данные остаются из `cached`.
    public static func resolve(cached: Entitlement, fromDevice: [StoreSubscription]?, fromServer: [StoreSubscription]?, now: Date) -> Entitlement {
        Entitlement(
            device: fromDevice ?? cached.device,
            server: fromServer ?? cached.server,
            checkedAt: fromDevice != nil || fromServer != nil ? now : cached.checkedAt
        )
    }

    /// Покупки, которые магазин на устройстве видит, а сервер у нашего аккаунта — нет.
    public static func unclaimed(fromDevice: [StoreSubscription]?, fromServer: [StoreSubscription]?) -> [String] {
        guard let fromDevice, let fromServer else { return [] }
        let known = Set(fromServer.compactMap(\.purchaseId))
        var seen = Set<String>()
        return fromDevice.compactMap(\.purchaseId).filter { !known.contains($0) && seen.insert($0).inserted }
    }
}

/// «1 049 ₽» из копеек: без копеек, если сумма целая; разделитель тысяч — неразрывный пробел.
public func formatRubles(_ kopecks: Int64) -> String {
    let rub = kopecks / 100, rest = kopecks % 100
    let digits = Array(String(rub).reversed())
    let grouped = stride(from: 0, to: digits.count, by: 3)
        .map { String(digits[$0..<min($0 + 3, digits.count)]) }
        .joined(separator: "\u{00A0}")
    let g = String(grouped.reversed())
    return rest == 0 ? "\(g)\u{00A0}₽" : "\(g),\(String(format: "%02d", rest))\u{00A0}₽"
}

/// Длительность периода магазина в ISO 8601 («P1M», «P6M», «P3D», «P1Y», «P1W»).
public struct StorePeriod: Hashable, Sendable {
    public let months: Int
    public let days: Int
    public init(months: Int, days: Int) { self.months = months; self.days = days }

    public static func parse(_ iso: String) -> StorePeriod? {
        let s = iso.uppercased()
        guard s.hasPrefix("P"), s.count > 1 else { return nil }
        var years = 0, months = 0, weeks = 0, days = 0
        var number = ""
        var sign = 1
        for ch in s.dropFirst() {
            if ch == "-" && number.isEmpty { sign = -1; continue }
            if ch.isNumber { number.append(ch); continue }
            guard let n = Int(number) else { return nil }
            switch ch {
            case "Y": years = sign * n
            case "M": months = sign * n
            case "W": weeks = sign * n
            case "D": days = sign * n
            default: return nil
            }
            number = ""; sign = 1
        }
        guard number.isEmpty else { return nil }
        return StorePeriod(months: years * 12 + months, days: weeks * 7 + days)
    }
}
