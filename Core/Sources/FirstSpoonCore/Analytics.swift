import Foundation

/// Каталог продуктовых событий — единственное место, где они объявлены. Имена и параметры **те же, что в Android**
/// (`core/analytics/AnalyticsEvent.kt`): ключ AppMetrica у приложений общий, отчёты строятся по имени события.
/// Описание каждого события — `docs/analytics.md`; `AnalyticsCatalogTests` проверяет, что код и документ совпадают.
///
/// Параметры — только коды действий и тарифов. Публичный ID передаётся только для продуктов каталога в разрешённых событиях.
/// Имена, реакции, аллергены, заметки и идентификаторы своих продуктов не передаются. Поэтому параметры типизированы, а не произвольный словарь в месте вызова.
/// Имя — snake_case, после выпуска не переименовывать.
public enum AnalyticsEvent: Hashable, Sendable {
    public enum Theme: String, CaseIterable, Sendable { case system, light, dark }
    public enum LegalDocument: String, Sendable { case privacy, terms }
    public enum FeedbackVote: String, Sendable { case like, dislike }

    public enum AssistantEntry: String, Sendable { case home, product, settings }
    public enum AssistantFailure: String, Sendable { case network, quota, auth, server, other }
    public enum DeviceOperation: String, Sendable { case list, revoke }

    public enum Food: Hashable, Sendable {
        case catalog(String), custom, unknown

        func fields(includeID: Bool = true) -> [String: AnalyticsValue] {
            switch self {
            case .catalog(let id):
                return includeID ? ["product_type": .string("catalog"), "product_id": .string(id)] : ["product_type": .string("catalog")]
            case .custom: return ["product_type": .string("custom")]
            case .unknown: return ["product_type": .string("unknown")]
            }
        }
    }

    public enum OnboardingOption: Hashable, Sendable {
        case sex(Sex)
        case milkFeeding(MilkFeeding)
        case knownFood(String)

        public enum MilkFeeding: String, Hashable, Sendable { case breast, formula, mixed }

        var codes: (String, String) {
            switch self {
            case .sex(let value): return ("sex", value.rawValue)
            case .milkFeeding(let value): return ("milk_feeding", value.rawValue)
            case .knownFood(let id): return ("known_foods", id)
            }
        }
    }

    case entryUpdated(food: Food)
    case entryDeleted(food: Food)
    case entryReactionChanged(food: Food)
    case productOpened(food: Food)
    case productFavoriteChanged(food: Food, liked: Bool)
    case productMarkRemoved(food: Food)
    case customProductDeleted
    case onboardingOptionChanged(option: OnboardingOption, selected: Bool)
    case assistantOpened(source: AssistantEntry)
    case assistantHistoryOpened
    case assistantChatCreated
    case assistantChatSelected
    case assistantChatDeleted
    case assistantMessageSent
    case assistantReplyReceived
    case assistantRequestFailed(reason: AssistantFailure)
    case assistantRequestStopped
    case assistantAnswerCopied
    case assistantShareOpened
    case deviceSessionsFailed(operation: DeviceOperation)
    case diarySyncEnabled
    case diarySyncDisabled
    case deviceSessionsOpened
    case deviceSessionRevoked
    case themeChanged(mode: Theme)
    case legalDocumentOpened(document: LegalDocument)
    case assistantSourceOpened
    case assistantRetried
    case assistantFeedbackTapped(vote: FeedbackVote)

    // Аккаунт
    case welcomeShown
    case guestStarted
    case login(fromGuest: Bool)
    case emailLinked
    case logout
    case accountDeleted
    // Дневник
    /// `step` — ключ шага онбординга (`OnboardingStep.key`): воронка онбординга.
    case onboardingStep(step: String)
    case onboardingBackToWelcome
    /// `readiness` — итог (`FeedingReadiness.Result.rawValue`); `knownFoods` — сколько основных продуктов отметили.
    case onboardingCompleted(readiness: FeedingReadiness.Result, knownFoods: Int)
    /// На главной «Малыш уже держит голову и сидит».
    case readyMarked
    case childAdded
    case entryAdded(food: Food)
    /// Код отметки (`known` / `excluded` / `allergy`), без продукта.
    case productMarked(mark: ProductMark, food: Food? = nil)
    case customProductAdded
    // Рекомендации
    case recommendationRecord
    case recommendationOther
    /// Тап по карточке прогресса на главной — открыт экран статистики.
    case statsOpened
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
        "entry_updated",
        "entry_deleted",
        "entry_reaction_changed",
        "product_opened",
        "product_favorite_changed",
        "product_mark_removed",
        "custom_product_deleted",
        "onboarding_option_changed",
        "assistant_opened",
        "assistant_history_opened",
        "assistant_chat_created",
        "assistant_chat_selected",
        "assistant_chat_deleted",
        "assistant_message_sent",
        "assistant_reply_received",
        "assistant_request_failed",
        "assistant_request_stopped",
        "assistant_answer_copied",
        "assistant_share_opened",
        "device_sessions_failed",
        "diary_sync_enabled",
        "diary_sync_disabled",
        "device_sessions_opened",
        "device_session_revoked",
        "theme_changed",
        "legal_document_opened",
        "assistant_source_opened",
        "assistant_retried",
        "assistant_feedback_tapped",
        "welcome_shown", "guest_started", "login", "email_linked", "logout", "account_deleted",
        "onboarding_step", "onboarding_back_to_welcome", "onboarding_completed", "ready_marked", "child_added", "entry_added", "product_marked", "custom_product_added",
        "recommendation_record", "recommendation_other", "stats_opened",
        "diary_exported", "entry_photo_added", "child_photo_set", "custom_product_photo_set", "network_blocked_shown",
        "paywall_opened", "purchase_started", "purchase_completed", "purchase_failed", "restore_tapped",
    ]

    public var name: String {
        switch self {
        case .entryUpdated: return "entry_updated"
        case .entryDeleted: return "entry_deleted"
        case .entryReactionChanged: return "entry_reaction_changed"
        case .productOpened: return "product_opened"
        case .productFavoriteChanged: return "product_favorite_changed"
        case .productMarkRemoved: return "product_mark_removed"
        case .customProductDeleted: return "custom_product_deleted"
        case .onboardingOptionChanged: return "onboarding_option_changed"
        case .assistantOpened: return "assistant_opened"
        case .assistantHistoryOpened: return "assistant_history_opened"
        case .assistantChatCreated: return "assistant_chat_created"
        case .assistantChatSelected: return "assistant_chat_selected"
        case .assistantChatDeleted: return "assistant_chat_deleted"
        case .assistantMessageSent: return "assistant_message_sent"
        case .assistantReplyReceived: return "assistant_reply_received"
        case .assistantRequestFailed: return "assistant_request_failed"
        case .assistantRequestStopped: return "assistant_request_stopped"
        case .assistantAnswerCopied: return "assistant_answer_copied"
        case .assistantShareOpened: return "assistant_share_opened"
        case .deviceSessionsFailed: return "device_sessions_failed"
        case .diarySyncEnabled: return "diary_sync_enabled"
        case .diarySyncDisabled: return "diary_sync_disabled"
        case .deviceSessionsOpened: return "device_sessions_opened"
        case .deviceSessionRevoked: return "device_session_revoked"
        case .themeChanged: return "theme_changed"
        case .legalDocumentOpened: return "legal_document_opened"
        case .assistantSourceOpened: return "assistant_source_opened"
        case .assistantRetried: return "assistant_retried"
        case .assistantFeedbackTapped: return "assistant_feedback_tapped"
        case .welcomeShown: return "welcome_shown"
        case .guestStarted: return "guest_started"
        case .login: return "login"
        case .emailLinked: return "email_linked"
        case .logout: return "logout"
        case .accountDeleted: return "account_deleted"
        case .onboardingStep: return "onboarding_step"
        case .onboardingBackToWelcome: return "onboarding_back_to_welcome"
        case .onboardingCompleted: return "onboarding_completed"
        case .readyMarked: return "ready_marked"
        case .childAdded: return "child_added"
        case .entryAdded: return "entry_added"
        case .productMarked: return "product_marked"
        case .customProductAdded: return "custom_product_added"
        case .recommendationRecord: return "recommendation_record"
        case .recommendationOther: return "recommendation_other"
        case .statsOpened: return "stats_opened"
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
        case .assistantOpened(let source): return ["source": .string(source.rawValue)]
        case .assistantRequestFailed(let reason): return ["reason": .string(reason.rawValue)]
        case .deviceSessionsFailed(let operation): return ["operation": .string(operation.rawValue)]
        case .themeChanged(let mode): return ["mode": .string(mode.rawValue)]
        case .legalDocumentOpened(let document): return ["document": .string(document.rawValue)]
        case .assistantFeedbackTapped(let vote): return ["vote": .string(vote.rawValue)]
        case .login(let fromGuest): return ["from_guest": .bool(fromGuest)]
        case .onboardingStep(let step): return ["step": .string(step)]
        case .onboardingCompleted(let r, let n): return ["readiness": .string(r.rawValue), "known_foods": .int(n)]
        case .entryAdded(let food), .entryUpdated(let food), .entryDeleted(let food), .productOpened(let food):
            return food.fields()
        case .entryReactionChanged(let food), .productMarkRemoved(let food):
            return food.fields(includeID: false)
        case .productFavoriteChanged(let food, let liked):
            return food.fields().merging(["liked": .bool(liked)]) { _, next in next }
        case .productMarked(let mark, let food):
            return (food?.fields(includeID: mark == .known) ?? [:]).merging(["mark": .string(mark.rawValue)]) { _, next in next }
        case .customProductAdded, .customProductDeleted, .customProductPhotoSet:
            return Food.custom.fields()
        case .onboardingOptionChanged(let option, let selected):
            let (step, code) = option.codes
            return ["step": .string(step), "option": .string(code), "selected": .bool(selected)]
        case .diaryExported(let photos): return ["photos": .string(photos)]
        case .purchaseStarted(let p), .purchaseCompleted(let p), .purchaseFailed(let p): return ["product": .string(p)]
        default: return [:]
        }
    }
}

public enum AnalyticsValue: Hashable, Sendable, CustomStringConvertible {
    case string(String), bool(Bool), int(Int)
    public var any: Any { switch self { case .string(let s): return s; case .bool(let b): return b; case .int(let n): return n } }
    public var description: String {
        switch self { case .string(let s): return s; case .bool(let b): return String(b); case .int(let n): return String(n) }
    }
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
