import Foundation

/// Каталог продуктовых событий — единственное место, где они объявлены. Имена и параметры **те же, что в Android**
/// (`core/analytics/AnalyticsEvent.kt`): ключ AppMetrica у приложений общий, отчёты строятся по имени события.
/// Описание каждого события — `docs/analytics.md`; `AnalyticsCatalogTests` проверяет, что код и документ совпадают.
///
/// Параметры — только коды действий и тарифов. Никаких личных данных и содержимого дневника: имён, почты, продуктов,
/// реакций, аллергенов, заметок. Поэтому параметры типизированы, а не произвольный словарь в месте вызова.
/// Имя — snake_case, после выпуска не переименовывать.
public enum AnalyticsEvent: Hashable, Sendable {
    // Аккаунт
    case guestStarted
    case login(fromGuest: Bool)
    case emailLinked
    case logout
    case accountDeleted
    // Дневник
    case onboardingCompleted
    case childAdded
    case entryAdded
    /// Код отметки (`known` / `excluded` / `allergy`), без продукта.
    case productMarked(mark: ProductMark)
    case customProductAdded
    // Рекомендации
    case recommendationRecord
    case recommendationOther
    // Профиль и фото
    /// `photos`: `none` | `reactions` | `all` — какие фото проб попали в PDF (`none` и когда фото у ребёнка нет).
    case diaryExported(photos: String)
    /// Фото прикреплено к пробе (из галереи). По событию на фото, при сохранении пробы.
    case entryPhotoAdded
    case childPhotoSet
    case customProductPhotoSet
    // Сеть
    case networkBlockedShown
    // Плюс (на iOS пейвола пока нет — события объявлены для единого каталога с Android)
    case paywallOpened
    case purchaseStarted(product: String)
    case purchaseCompleted(product: String)
    case purchaseFailed(product: String)
    case restoreTapped

    /// Все имена каталога (для теста сверки с документом). Новое событие — добавить и сюда.
    public static let allNames: [String] = [
        "guest_started", "login", "email_linked", "logout", "account_deleted",
        "onboarding_completed", "child_added", "entry_added", "product_marked", "custom_product_added",
        "recommendation_record", "recommendation_other",
        "diary_exported", "entry_photo_added", "child_photo_set", "custom_product_photo_set", "network_blocked_shown",
        "paywall_opened", "purchase_started", "purchase_completed", "purchase_failed", "restore_tapped",
    ]

    public var name: String {
        switch self {
        case .guestStarted: return "guest_started"
        case .login: return "login"
        case .emailLinked: return "email_linked"
        case .logout: return "logout"
        case .accountDeleted: return "account_deleted"
        case .onboardingCompleted: return "onboarding_completed"
        case .childAdded: return "child_added"
        case .entryAdded: return "entry_added"
        case .productMarked: return "product_marked"
        case .customProductAdded: return "custom_product_added"
        case .recommendationRecord: return "recommendation_record"
        case .recommendationOther: return "recommendation_other"
        case .diaryExported: return "diary_exported"
        case .entryPhotoAdded: return "entry_photo_added"
        case .childPhotoSet: return "child_photo_set"
        case .customProductPhotoSet: return "custom_product_photo_set"
        case .networkBlockedShown: return "network_blocked_shown"
        case .paywallOpened: return "paywall_opened"
        case .purchaseStarted: return "purchase_started"
        case .purchaseCompleted: return "purchase_completed"
        case .purchaseFailed: return "purchase_failed"
        case .restoreTapped: return "restore_tapped"
        }
    }

    public var params: [String: AnalyticsValue] {
        switch self {
        case .login(let fromGuest): return ["from_guest": .bool(fromGuest)]
        case .productMarked(let mark): return ["mark": .string(mark.rawValue)]
        case .diaryExported(let photos): return ["photos": .string(photos)]
        case .purchaseStarted(let p), .purchaseCompleted(let p), .purchaseFailed(let p): return ["product": .string(p)]
        default: return [:]
        }
    }
}

public enum AnalyticsValue: Hashable, Sendable, CustomStringConvertible {
    case string(String), bool(Bool)
    public var any: Any { switch self { case .string(let s): return s; case .bool(let b): return b } }
    public var description: String { switch self { case .string(let s): return s; case .bool(let b): return String(b) } }
}

/// Получатель событий: система аналитики, лог, фейк в тестах.
public protocol AnalyticsTracker: Sendable {
    func track(_ event: AnalyticsEvent)
}

/// Точка входа: код вызывает только `Analytics.track(.x)`. Куда уходят события, решают трекеры, подключённые
/// один раз при старте (`Analytics.install`). Сменить систему аналитики = новый трекер, места вызова не меняются.
/// Без install события никуда не уходят (unit-тесты, превью).
public enum Analytics {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var trackers: [AnalyticsTracker] = []

    public static func install(_ list: [AnalyticsTracker]) {
        lock.lock(); trackers = list; lock.unlock()
    }

    /// Трекеры не бросают ошибок; падение внутри SDK — его ответственность, действие пользователя не ломается.
    public static func track(_ event: AnalyticsEvent) {
        lock.lock(); let list = trackers; lock.unlock()
        for t in list { t.track(event) }
    }
}
