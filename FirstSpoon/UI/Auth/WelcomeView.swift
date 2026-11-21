import SwiftUI
import SafariServices
import FirstSpoonCore

/// Граф входа: приветствие → [email → код].
struct AuthFlow: View {
    @Environment(AppContainer.self) private var app
    @State private var path: [AuthRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            WelcomeView(onContinue: { app.auth.startAnonymous() }, onLogin: { path.append(.email(.login)) })
                .onAppear { Analytics.track(.welcomeShown) }
                .navigationDestination(for: AuthRoute.self) { route in
                    switch route {
                    case .email(let mode): AuthEmailView(model: AuthViewModel(auth: app.auth, mode: mode), onCodeSent: { path.append(.code($0)) })
                    case .code(let model): AuthCodeView(model: model)
                    }
                }
        }
    }
}

enum AuthRoute: Hashable {
    case email(AuthMode)
    case code(AuthViewModel)
}

/// Первый экран до входа: название, «Продолжить», «У меня уже есть аккаунт», ссылки на документы.
struct WelcomeView: View {
    let onContinue: () -> Void
    let onLogin: () -> Void
    @State private var document: URL?

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            Text("🥄").font(.system(size: 96))
            Text(L.s("welcome_title")).font(AppFont.displaySmall).foregroundStyle(AppColors.ink)
                .multilineTextAlignment(.center).padding(.top, 24)
            Text(L.s("welcome_subtitle")).font(AppFont.onest(20, 400)).foregroundStyle(AppColors.inkMuted)
                .multilineTextAlignment(.center).padding(.top, 14)
            Spacer().frame(maxHeight: .infinity).layoutPriority(-1)
            Spacer()
            VStack(spacing: 16) {
                AppButton(L.s("welcome_continue"), action: onContinue)
                TextLink(L.s("welcome_have_account"), action: onLogin)
                legal
            }
        }
        .padding(.horizontal, screenPadding)
        .padding(.vertical, 16)
        .appScreen()
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $document) { SafariView(url: $0).ignoresSafeArea() }
    }

    /// «Продолжая, вы принимаете условия использования и политику конфиденциальности» — ссылки открываются внутри приложения.
    private var legal: some View {
        var text = AttributedString(L.s("welcome_legal_prefix") + " ")
        text.foregroundColor = AppColors.inkMuted
        var terms = AttributedString(L.s("welcome_legal_terms"))
        terms.link = URL(string: L.s("url_terms"))
        var and = AttributedString(" " + L.s("welcome_legal_and") + " ")
        and.foregroundColor = AppColors.inkMuted
        var privacy = AttributedString(L.s("welcome_legal_privacy"))
        privacy.link = URL(string: L.s("url_privacy"))
        terms.underlineStyle = .single
        privacy.underlineStyle = .single
        return Text(text + terms + and + privacy)
            .font(AppFont.bodyMedium)
            .tint(AppColors.primary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 8)
            .environment(\.openURL, OpenURLAction { url in
                document = url
                return .handled
            })
    }
}

extension URL: @retroactive Identifiable { public var id: String { absoluteString } }

/// Документы открываем внутри приложения (аналог Custom Tabs).
struct SafariView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController { SFSafariViewController(url: url) }
    func updateUIViewController(_ vc: SFSafariViewController, context: Context) {}
}
