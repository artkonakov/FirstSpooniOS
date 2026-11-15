import Foundation

// DTO сервера (auth-function, API.md). Ключи — snake_case, кодировщики ApiClient конвертируют сами.

struct AuthEmailRequest: Encodable { let email: String }

struct VerifyRequest: Encodable {
    let email: String
    let code: String
    /// Вход с анонимного аккаунта: его подписки сервер перенесёт в аккаунт, в который входим.
    let anonymousRefreshToken: String?
}

struct ChangeEmailRequest: Encodable { let newEmail: String }
struct CodeRequest: Encodable { let code: String }
struct RefreshRequest: Encodable { let refreshToken: String }

struct StatusResponse: Decodable { let status: String? }

/// `/auth/email`: либо `{status: code_sent, otp_required: true}`, либо сразу токены (`otp_required: false`).
struct AuthEmailResponse: Decodable {
    let status: String?
    let otpRequired: Bool?
    let token: String?
    let refreshToken: String?
    let userId: String?
    let email: String?
}

struct TokenResponse: Decodable {
    let token: String
    let refreshToken: String
    let userId: String
    /// nil — анонимный пользователь (`/auth/anonymous`).
    let email: String?
}

/// Ответ `/auth/email/change/verify`: новый access token; refresh token прежний.
struct EmailChangedResponse: Decodable {
    let token: String
    let userId: String
    let email: String
}

struct UserMeResponse: Decodable {
    let userId: String
    let email: String?
}

struct DeleteAccountResponse: Decodable { let status: String? }
