import Foundation
import Observation
import FirstSpoonCore

enum LoginStep { case codeSent, loggedIn }

/// Аккаунт пользователя (сервер auth-function). Логика та же, что в Android `AuthRepository`:
/// - **Анонимно** (по умолчанию): «Продолжить» → `startAnonymous`. Флаг гостя ставится сразу, приложение открывается
///   без сети; `POST /auth/anonymous` выполняется в фоне (`ensureAnonymous`) и повторяется при старте, пока не получится.
/// - **Привязка email** к анонимному: `linkEmail` → `verifyLink`, user_id тот же.
/// - **Вход по email**: `requestCode` → `verifyCode`. Дневник анонимного владельца переходит к аккаунту, чужой — стирается.
@MainActor @Observable
final class AuthRepository {
    /// Пользователь выбрал «Продолжить» без входа; держится до выхода/удаления.
    private(set) var guest: Bool

    @ObservationIgnored private let api: ApiClient
    @ObservationIgnored private let tokens: TokenStore
    @ObservationIgnored private let session: SessionManager
    @ObservationIgnored private let db: AppDatabase
    @ObservationIgnored private let defaults: UserDefaults
    /// Вызывается после стирания данных пользователя — репозитории перечитывают состояние.
    @ObservationIgnored var onUserDataCleared: () -> Void = {}
    @ObservationIgnored private var anonymousTask: Task<ApiResult<Void>, Never>?

    private enum Key {
        static let owner = "local_data/owner_user_id"
        static let ownerAnonymous = "local_data/owner_anonymous"
        static let guest = "local_data/guest_started"
    }

    init(api: ApiClient, tokens: TokenStore, session: SessionManager, db: AppDatabase, defaults: UserDefaults = .standard) {
        self.api = api
        self.tokens = tokens
        self.session = session
        self.db = db
        self.defaults = defaults
        guest = defaults.bool(forKey: Key.guest)
    }

    /// Анонимный: нет email (в т.ч. пока анонимный аккаунт ещё не создан на сервере).
    var isAnonymous: Bool { tokens.email == nil }

    /// «Продолжить» без регистрации: сразу пускаем в приложение, аккаунт создаём в фоне.
    func startAnonymous() {
        defaults.set(true, forKey: Key.guest)
        guest = true
        Analytics.track(.guestStarted)
        Task { await ensureAnonymous() }
    }

    /// Создаёт анонимный аккаунт, если пользователь — гость без сессии. Без сети — тихо выходит до следующего раза.
    @discardableResult
    func ensureAnonymous() async -> ApiResult<Void> {
        if let anonymousTask { return await anonymousTask.value }
        if tokens.hasSession || !guest { return .success(()) }
        let task = Task<ApiResult<Void>, Never> {
            let r = await api.call("POST", "auth/anonymous", authorized: false, as: TokenResponse.self)
            if case .success(let t) = r { completeLogin(access: t.token, refresh: t.refreshToken, userId: t.userId, email: t.email) }
            return r.map { _ in () }
        }
        anonymousTask = task
        let result = await task.value
        anonymousTask = nil
        return result
    }

    func requestCode(_ email: String) async -> ApiResult<LoginStep> {
        let mail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let r = await api.call("POST", "auth/email", body: AuthEmailRequest(email: mail), authorized: false, as: AuthEmailResponse.self)
        guard case .success(let body) = r else { return r.map { _ in .codeSent } }
        if body.otpRequired == false, let token = body.token {
            completeLogin(access: token, refresh: body.refreshToken, userId: body.userId, email: body.email ?? mail)
            return .success(.loggedIn)
        }
        return .success(.codeSent)
    }

    func resendCode(_ email: String) async -> ApiResult<Void> {
        await api.call("POST", "auth/email/resend", body: AuthEmailRequest(email: email.trimmingCharacters(in: .whitespacesAndNewlines)),
                       authorized: false, as: StatusResponse.self).map { _ in () }
    }

    func verifyCode(email: String, code: String) async -> ApiResult<Void> {
        let mail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        // Входим из анонимного аккаунта — сервер перенесёт его подписки в аккаунт, в который входим.
        let anonymousToken = tokens.email == nil ? tokens.refreshToken : nil
        let r = await api.call("POST", "auth/email/verify",
                               body: VerifyRequest(email: mail, code: code.trimmingCharacters(in: .whitespacesAndNewlines),
                                                   anonymousRefreshToken: anonymousToken),
                               authorized: false, as: TokenResponse.self)
        if case .success(let t) = r {
            completeLogin(access: t.token, refresh: t.refreshToken, userId: t.userId, email: t.email ?? mail)
            Analytics.track(.login(fromGuest: anonymousToken != nil))
        }
        return r.map { _ in () }
    }

    /// Привязка email к текущему (анонимному) аккаунту: код уходит на адрес. Повтор — тем же вызовом.
    func linkEmail(_ email: String) async -> ApiResult<Void> {
        if case .failure(let e) = await ensureAnonymous() { return .failure(e) }
        return await api.call("POST", "auth/email/change",
                              body: ChangeEmailRequest(newEmail: email.trimmingCharacters(in: .whitespacesAndNewlines)),
                              authorized: true, as: StatusResponse.self).map { _ in () }
    }

    func verifyLink(_ code: String) async -> ApiResult<Void> {
        let r = await api.call("POST", "auth/email/change/verify",
                               body: CodeRequest(code: code.trimmingCharacters(in: .whitespacesAndNewlines)),
                               authorized: true, as: EmailChangedResponse.self)
        if case .success(let b) = r {
            tokens.save(access: b.token, refresh: nil, userId: b.userId, email: b.email)
            defaults.set(false, forKey: Key.ownerAnonymous)
            session.onLoggedIn()
            Analytics.track(.emailLinked)
        }
        return r.map { _ in () }
    }

    /// Проверка сессии при старте; гостю без аккаунта сначала создаём его. 401/410 обработает ApiClient.
    func refreshProfile() async {
        await ensureAnonymous()
        guard tokens.hasSession else { return }
        if case .success(let me) = await api.call("GET", "user/me", authorized: true, as: UserMeResponse.self),
           let access = tokens.accessToken {
            tokens.save(access: access, refresh: nil, userId: me.userId, email: me.email)
            if me.email != nil { session.onLoggedIn() }
        }
    }

    func logout() {
        Analytics.track(.logout)
        signOutLocally()
    }

    /// Стереть дневник, флаги и токены (выход, удаление аккаунта).
    private func signOutLocally() {
        try? db.clearUserData()
        for key in [Key.owner, Key.ownerAnonymous, Key.guest] { defaults.removeObject(forKey: key) }
        guest = false
        session.onLoggedOut()
        onUserDataCleared()
    }

    /// Сервер отклонил refresh token. Анонимному — новый анонимный аккаунт, дневник остаётся.
    /// С email — на экран входа, дневник тоже остаётся.
    func onRefreshFailed() async {
        let anonymous = isAnonymous
        session.onLoggedOut()
        if anonymous && guest {
            await ensureAnonymous()
        } else {
            defaults.removeObject(forKey: Key.guest)
            guest = false
        }
    }

    func deleteAccount() async -> ApiResult<Void> {
        // Гость, чей аккаунт ещё не создан на сервере: удалять там нечего.
        guard tokens.hasSession else { accountDeleted(); return .success(()) }
        let r = await api.call("DELETE", "user/me", authorized: true, as: DeleteAccountResponse.self)
        let alreadyDeleted = r.error?.status == 410
        if case .success = r { accountDeleted(); return .success(()) }
        if alreadyDeleted { accountDeleted(); return .success(()) }
        return r.map { _ in () }
    }

    private func accountDeleted() {
        Analytics.track(.accountDeleted)
        signOutLocally()
    }

    private func completeLogin(access: String, refresh: String?, userId: String?, email: String?) {
        let previousOwner = defaults.string(forKey: Key.owner)
        let previousAnonymous = defaults.bool(forKey: Key.ownerAnonymous)
        // Дневник анонимного пользователя переходит к аккаунту, в который вошли; чужой (с email) — стираем.
        if let userId, let previousOwner, previousOwner != userId, !previousAnonymous {
            try? db.clearUserData()
            onUserDataCleared()
        }
        tokens.save(access: access, refresh: refresh, userId: userId, email: email)
        if let userId {
            defaults.set(userId, forKey: Key.owner)
            defaults.set(email == nil, forKey: Key.ownerAnonymous)
        }
        session.onLoggedIn()
    }
}
