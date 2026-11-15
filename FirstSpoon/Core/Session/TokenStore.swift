import Foundation
import Security
import Observation

/// Токены и почта. Хранятся в Keychain (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`): шифрование делает система,
/// в резервную копию и на другое устройство не попадают — аналог AES-GCM + Android Keystore.
/// Синхронный, с кэшем в памяти: читается из сетевого слоя при каждом запросе.
final class TokenStore: @unchecked Sendable {
    private let service: String
    private let lock = NSLock()
    private var cache: [String: String?] = [:]

    init(service: String = (Bundle.main.bundleIdentifier ?? "app.littlebite") + ".session") {
        self.service = service
    }

    var accessToken: String? { read("access_token") }
    var refreshToken: String? { read("refresh_token") }
    var userId: String? { read("user_id") }
    var email: String? { read("email") }

    /// Признак входа — наличие refresh token.
    var hasSession: Bool { refreshToken != nil }

    /// `refresh` = nil — оставить прежний (ответ смены почты не возвращает refresh token).
    func save(access: String, refresh: String?, userId: String?, email: String?) {
        write("access_token", access)
        if let refresh { write("refresh_token", refresh) }
        if let userId { write("user_id", userId) }
        write("email", email)
    }

    func clear() {
        for key in ["access_token", "refresh_token", "user_id", "email"] { write(key, nil) }
    }

    private func read(_ key: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        if let cached = cache[key] { return cached }
        var query = baseQuery(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        let value = SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess
            ? (out as? Data).flatMap { String(data: $0, encoding: .utf8) } : nil
        cache[key] = .some(value)
        return value
    }

    private func write(_ key: String, _ value: String?) {
        lock.lock(); defer { lock.unlock() }
        SecItemDelete(baseQuery(key) as CFDictionary)
        if let value {
            var query = baseQuery(key)
            query[kSecValueData as String] = Data(value.utf8)
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(query as CFDictionary, nil)
        }
        cache[key] = .some(value)
    }

    private func baseQuery(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: key]
    }
}

enum SessionState: Equatable {
    case loggedIn(email: String?)
    case loggedOut
}

/// Залогинен ли пользователь — только отсюда. Признак входа — наличие refresh token.
@MainActor @Observable
final class SessionManager {
    @ObservationIgnored private let tokens: TokenStore
    private(set) var state: SessionState

    init(tokens: TokenStore) {
        self.tokens = tokens
        state = tokens.hasSession ? .loggedIn(email: tokens.email) : .loggedOut
    }

    func onLoggedIn() { state = .loggedIn(email: tokens.email) }

    func onLoggedOut() {
        tokens.clear()
        state = .loggedOut
    }
}
