import Foundation
import Observation
import FirstSpoonCore

enum RootGraph { case auth, onboarding, main }

/// Ручной DI: один граф зависимостей на процесс (как `AppContainer` в Android).
@MainActor @Observable
final class AppContainer {
    @ObservationIgnored let tokens: TokenStore
    let session: SessionManager
    @ObservationIgnored let db: AppDatabase
    @ObservationIgnored let photos: PhotoStore
    @ObservationIgnored let api: ApiClient
    let auth: AuthRepository
    let catalog: CatalogRepository
    let activeChildStore: ActiveChildStore
    let diary: DiaryRepository
    let onboarding: OnboardingStore
    let recommendations: RecommendationRepository
    let reminderSettings: ReminderSettings
    /// Запрещён ли приложению доступ к сети (блокирующий экран).
    let networkAccess = NetworkAccessMonitor()
    @ObservationIgnored private(set) var reminders: ReminderScheduler!

    init(db: AppDatabase? = nil, defaults: UserDefaults = .standard, tokens: TokenStore = TokenStore()) {
        // Keychain переживает удаление приложения, UserDefaults — нет: на свежей установке старую сессию забываем.
        if !defaults.bool(forKey: "installed") {
            tokens.clear()
            defaults.set(true, forKey: "installed")
        }
        self.tokens = tokens
        self.db = db ?? (try! AppDatabase.makeShared())
        photos = PhotoStore()
        // Файлы фото без ссылки в БД — брошенные черновики (приложение закрыли посреди редактирования).
        photos.retainOnly(self.db.referencedPhotos())
        session = SessionManager(tokens: tokens)
        api = ApiClient(tokens: tokens)
        auth = AuthRepository(api: api, tokens: tokens, session: session, db: self.db, photos: photos, defaults: defaults)
        catalog = CatalogRepository(db: self.db, photos: photos)
        activeChildStore = ActiveChildStore(defaults: defaults)
        diary = DiaryRepository(db: self.db, activeStore: activeChildStore, photos: photos)
        onboarding = OnboardingStore(defaults: defaults)
        recommendations = RecommendationRepository(diary: diary, catalog: catalog)
        reminderSettings = ReminderSettings(defaults: defaults)
        reminders = ReminderScheduler(settings: reminderSettings, onboarding: onboarding, diary: diary, catalog: catalog,
                                      accountStarted: { [unowned self] in self.accountStarted })

        auth.onUserDataCleared = { [unowned self] in
            catalog.reload()
            diary.reload()
        }
        api.onSessionInvalid = { [unowned self] reason in
            switch reason {
            case .accountDeleted: auth.logout()
            // Данные остаются: гостю — новый анонимный аккаунт, с email — экран входа.
            case .refreshFailed: Task { await self.auth.onRefreshFailed() }
            }
        }
        // Гость, у которого при «Продолжить» не было сети: создаём анонимный аккаунт сейчас.
        #if DEBUG
        // Демо-данные для скриншотов: `-demo_data YES -debug_offline YES` на чистой установке.
        DemoData.seedIfRequested(self, defaults: defaults)
        #endif
        Task { await auth.ensureAnonymous() }
    }

    /// Пользователь начал пользоваться приложением: вошёл по email или нажал «Продолжить» (гость).
    var accountStarted: Bool {
        if case .loggedIn = session.state { return true }
        return auth.guest
    }

    /// Какой корневой граф показывать: вход → онбординг ребёнка → приложение.
    /// Экраны не делают переходов после входа/выхода/онбординга — граф выбирается только здесь.
    var rootGraph: RootGraph {
        if !accountStarted { return .auth }
        if !onboarding.done || diary.children.isEmpty { return .onboarding }
        return .main
    }
}
