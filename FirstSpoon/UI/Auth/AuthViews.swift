import SwiftUI
import Observation

/// LOGIN — вход в существующий аккаунт; LINK — привязка почты к анонимному аккаунту (из настроек).
enum AuthMode: Hashable { case login, link }

/// Общий VM экранов почты и кода. После успеха экраны сами никуда не переходят:
/// вход меняет сессию — корневой граф перестраивается; привязка закрывает поток (`onLinked`).
@MainActor @Observable
final class AuthViewModel: Hashable {
    let mode: AuthMode
    var email = ""
    var code = ""
    var loading = false
    var error: String?
    /// Почта уже занята (только LINK) — предлагаем войти в этот аккаунт.
    var emailInUse = false
    var resendIn = 0
    var info: String?
    @ObservationIgnored private let auth: AuthRepository
    @ObservationIgnored private var timer: Task<Void, Never>?
    /// Успешный вход/привязка. Во входе с приветствия не нужен: граф перестраивается сам по сессии.
    @ObservationIgnored var onSuccess: () -> Void = {}

    init(auth: AuthRepository, mode: AuthMode) {
        self.auth = auth
        self.mode = mode
    }

    nonisolated static func == (a: AuthViewModel, b: AuthViewModel) -> Bool { a === b }
    nonisolated func hash(into h: inout Hasher) { h.combine(ObjectIdentifier(self)) }

    var emailValid: Bool {
        let e = email.trimmingCharacters(in: .whitespaces)
        return e.range(of: #"^[^@\s]+@[^@\s]+\.[^@\s]+$"#, options: .regularExpression) != nil
    }

    /// true — код отправлен, пора на экран кода.
    func submitEmail() async -> Bool {
        guard emailValid, !loading else { error = emailValid ? nil : L.s("error_invalid_email"); return false }
        loading = true; error = nil; emailInUse = false
        defer { loading = false }
        switch mode {
        case .login:
            switch await auth.requestCode(email) {
            case .success(.codeSent): startTimer(); return true
            case .success(.loggedIn): return false
            case .failure(let e): error = ErrorText.message(e); return false
            }
        case .link:
            switch await auth.linkEmail(email) {
            case .success: startTimer(); return true
            case .failure(let e):
                if e.status == 409 && e.code == ApiCodes.emailAlreadyInUse { emailInUse = true; error = L.s("link_email_in_use") }
                else { error = ErrorText.message(e) }
                return false
            }
        }
    }

    func submitCode() async {
        guard code.count >= 4, !loading else { return }
        loading = true; error = nil
        defer { loading = false }
        let r = mode == .login ? await auth.verifyCode(email: email, code: code) : await auth.verifyLink(code)
        switch r {
        case .success: onSuccess()
        case .failure(let e): error = ErrorText.message(e)
        }
    }

    func resend() async {
        guard resendIn == 0 else { return }
        let r = mode == .login ? await auth.resendCode(email) : await auth.linkEmail(email)
        switch r {
        case .success: info = L.s("auth_code_resent"); error = nil; startTimer()
        case .failure(let e): error = ErrorText.message(e)
        }
    }

    private func startTimer() {
        timer?.cancel()
        resendIn = 60
        timer = Task { [weak self] in
            while let self, self.resendIn > 0, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                self.resendIn -= 1
            }
        }
    }
}

/// Шаг 1: почта.
struct AuthEmailView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: AuthViewModel
    let onCodeSent: (AuthViewModel) -> Void
    var onLoginInstead: (() -> Void)?

    var body: some View {
        ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text(L.s(model.mode == .login ? "auth_subtitle" : "link_subtitle"))
                        .font(AppFont.bodyLarge).foregroundStyle(AppColors.inkMuted)
                    AppTextField(text: $model.email, placeholder: L.s("auth_email"), icon: "envelope", error: model.error,
                                 keyboard: .emailAddress, contentType: .emailAddress, capitalization: .never,
                                 onSubmit: submit)
                    if model.emailInUse, let onLoginInstead {
                        AppButton(L.s("link_login_instead"), kind: .soft, action: onLoginInstead)
                        Text(L.s("link_login_instead_hint")).font(AppFont.bodyMedium).foregroundStyle(AppColors.inkMuted)
                    }
                }
                .padding(.horizontal, screenPadding)
        }
        .bottomAction {
            AppButton(L.s("auth_continue"), enabled: model.emailValid, loading: model.loading, action: submit)
                .padding(.horizontal, screenPadding).padding(.vertical, 12)
        }
        .appScreen()
        .navigationTitle(L.s(model.mode == .login ? "auth_title" : "link_title"))
    }

    private func submit() {
        Task { if await model.submitEmail() { onCodeSent(model) } }
    }
}

/// Шаг 2: код из письма, повторная отправка с таймером 60 с.
struct AuthCodeView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: AuthViewModel

    var body: some View {
        ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text(L.s("auth_otp_subtitle", model.email)).font(AppFont.bodyLarge).foregroundStyle(AppColors.inkMuted)
                    AppTextField(text: $model.code, placeholder: L.s("auth_otp_code"), error: model.error,
                                 keyboard: .numberPad, contentType: .oneTimeCode, capitalization: .never)
                        .onChange(of: model.code) { _, v in
                            let digits = String(v.filter(\.isNumber).prefix(6))
                            if digits != v { model.code = digits }
                            if digits.count == 6 { Task { await model.submitCode() } }
                        }
                    if let info = model.info, model.error == nil {
                        Text(info).font(AppFont.bodyMedium).foregroundStyle(AppColors.good)
                    }
                    HStack {
                        TextLink(model.resendIn > 0 ? L.s("auth_resend_in", model.resendIn) : L.s("auth_resend"),
                                 enabled: model.resendIn == 0) { Task { await model.resend() } }
                        Spacer()
                        TextLink(L.s("auth_change_email"), color: AppColors.inkMuted) { dismiss() }
                    }
                }
                .padding(.horizontal, screenPadding)
        }
        .bottomAction {
            AppButton(L.s(model.mode == .login ? "auth_verify" : "link_verify"), enabled: model.code.count >= 4,
                      loading: model.loading) { Task { await model.submitCode() } }
                .padding(.horizontal, screenPadding).padding(.vertical, 12)
        }
        .appScreen()
        .navigationTitle(L.s("auth_otp_title"))
        .onAppear {
            #if DEBUG
            // Только debug, для e2e-проверки входа: код кладётся в настройки симулятора извне
            // (`defaults write app.littlebite.dev debug_otp …`), подставляется один раз и сразу стирается.
            if model.code.isEmpty, let code = UserDefaults.standard.string(forKey: "debug_otp") {
                UserDefaults.standard.removeObject(forKey: "debug_otp")
                model.code = code
            }
            #endif
        }
    }
}

/// ApiError → текст для пользователя (как `ApiError.messageRes()` в Android).
enum ErrorText {
    static func message(_ e: ApiError) -> String {
        let msg = e.message.lowercased()
        if e.isNetwork { return L.s("error_network") }
        if e.status == 400 && msg.contains("email") { return L.s("error_invalid_email") }
        if e.status == 401 { return L.s("error_invalid_code") }
        if e.status == 410 { return L.s("error_code_expired") }
        if e.status == 409 && e.code == ApiCodes.emailAlreadyInUse { return L.s("error_email_in_use") }
        if e.status == 429 && msg.contains("wait") { return L.s("error_resend_wait") }
        if e.status == 429 { return L.s("error_too_many_attempts") }
        if e.status == 403 { return L.s("error_blocked") }
        return L.s("error_generic")
    }
}
