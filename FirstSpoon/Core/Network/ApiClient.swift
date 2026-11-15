import Foundation

/// Результат сетевого вызова. Экраны никогда не видят исключений URLSession.
enum ApiResult<T> {
    case success(T)
    case failure(ApiError)

    func map<R>(_ f: (T) -> R) -> ApiResult<R> {
        switch self {
        case .success(let v): return .success(f(v))
        case .failure(let e): return .failure(e)
        }
    }

    var error: ApiError? { if case .failure(let e) = self { return e } else { return nil } }
}

/// Ошибка API. `status` == nil — сеть недоступна / таймаут. `code` — машинный код сервера.
struct ApiError: Error, Equatable {
    let status: Int?
    let message: String
    let code: String?

    var isNetwork: Bool { status == nil }
    var isAccountDeleted: Bool { status == 410 && code == ApiCodes.accountDeleted }
}

enum ApiCodes {
    static let accountDeleted = "ACCOUNT_DELETED"
    static let emailAlreadyInUse = "EMAIL_ALREADY_IN_USE"
}

/// Почему сессия закончилась по инициативе сервера.
enum SessionEndReason { case refreshFailed, accountDeleted }

/// Клиент `auth-function` (`https://api.littlebite.app/`, отдельного staging нет).
/// - публичные вызовы (`authorized: false`) — без токена;
/// - авторизованные: Bearer, на 401 — `/auth/refresh` (один на все параллельные запросы) и повтор, не больше двух раз;
///   refresh отклонён (4xx) → `refreshFailed`; нет сети → ошибка наверх, сессия жива;
/// - любой `410 ACCOUNT_DELETED` → `accountDeleted`.
final class ApiClient: @unchecked Sendable {
    static let baseURL = URL(string: "https://api.littlebite.app/")!

    private let tokens: TokenStore
    private let session: URLSession
    private let refresher: Refresher
    /// Вызывается на главном потоке.
    var onSessionInvalid: (@MainActor (SessionEndReason) -> Void)?

    init(tokens: TokenStore, session: URLSession = .shared) {
        self.tokens = tokens
        self.session = session
        refresher = Refresher(tokens: tokens)
    }

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()
    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        return e
    }()

    func call<Res: Decodable>(_ method: String, _ path: String, body: (any Encodable)? = nil, authorized: Bool,
                              as: Res.Type = Res.self) async -> ApiResult<Res> {
        var attempt = 0
        while true {
            let sentToken = authorized ? tokens.accessToken : nil
            let result = await send(method, path, body: body, token: sentToken)
            switch result {
            case .failure(let e):
                return .failure(e)
            case .success(let (status, data)):
                if status == 410, Self.parseError(410, data).isAccountDeleted, authorized {
                    await notify(.accountDeleted)
                }
                if status == 401 && authorized && attempt < 2 {
                    attempt += 1
                    switch await refresher.refresh(failedToken: sentToken, using: self) {
                    case .refreshed: continue
                    case .rejected(let reason): await notify(reason)
                    case .network: break
                    }
                }
                guard (200..<300).contains(status) else { return .failure(Self.parseError(status, data)) }
                do {
                    return .success(try Self.decoder.decode(Res.self, from: data.isEmpty ? Data("{}".utf8) : data))
                } catch {
                    return .failure(ApiError(status: status, message: "Bad response: \(error)", code: nil))
                }
            }
        }
    }

    /// Только debug: без сети (сервер не трогаем — например, чтобы проверять гостевой поток, не создавая аккаунт на боевом API).
    /// Включается аргументом запуска `-debug_offline YES` или `defaults write app.littlebite.dev debug_offline -bool YES`.
    static var offline: Bool {
        #if DEBUG
        return UserDefaults.standard.bool(forKey: "debug_offline")
        #else
        return false
        #endif
    }

    fileprivate func send(_ method: String, _ path: String, body: (any Encodable)?, token: String?) async -> ApiResult<(Int, Data)> {
        if Self.offline { return .failure(ApiError(status: nil, message: "debug_offline", code: nil)) }
        var request = URLRequest(url: Self.baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? Self.encoder.encode(AnyEncodable(body))
        }
        do {
            let (data, response) = try await session.data(for: request)
            return .success(((response as? HTTPURLResponse)?.statusCode ?? 0, data))
        } catch {
            return .failure(ApiError(status: nil, message: error.localizedDescription, code: nil))
        }
    }

    @MainActor private func notify(_ reason: SessionEndReason) { onSessionInvalid?(reason) }

    /// Тело ошибки сервера: `{error, code}`.
    static func parseError(_ status: Int, _ data: Data) -> ApiError {
        struct Body: Decodable { let error: String?; let message: String?; let code: String? }
        let body = try? JSONDecoder().decode(Body.self, from: data)
        return ApiError(status: status, message: body?.error ?? body?.message ?? "HTTP \(status)", code: body?.code)
    }
}

private struct AnyEncodable: Encodable {
    let value: any Encodable
    init(_ value: any Encodable) { self.value = value }
    func encode(to encoder: Encoder) throws { try value.encode(to: encoder) }
}

/// Один refresh за раз: остальные ждут и переиспользуют свежий токен.
private actor Refresher {
    enum Outcome { case refreshed, rejected(SessionEndReason), network }
    private let tokens: TokenStore
    private var running: Task<Outcome, Never>?

    init(tokens: TokenStore) { self.tokens = tokens }

    func refresh(failedToken: String?, using client: ApiClient) async -> Outcome {
        if let current = tokens.accessToken, current != failedToken { return .refreshed }
        if let running { return await running.value }
        let task = Task<Outcome, Never> { [tokens] in
            guard let refresh = tokens.refreshToken else { return .rejected(.refreshFailed) }
            switch await client.send("POST", "auth/refresh", body: RefreshRequest(refreshToken: refresh), token: nil) {
            case .failure: return .network
            case .success(let (status, data)):
                if status == 410 { return .rejected(.accountDeleted) }
                guard (200..<300).contains(status), let body = try? ApiClient.decoder.decode(TokenResponse.self, from: data) else {
                    return (400..<500).contains(status) ? .rejected(.refreshFailed) : .network
                }
                tokens.save(access: body.token, refresh: body.refreshToken, userId: body.userId, email: body.email)
                return .refreshed
            }
        }
        running = task
        let outcome = await task.value
        running = nil
        return outcome
    }
}
