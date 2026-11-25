import SwiftUI
import FirstSpoonCore

/// Настройки приложения и аккаунта. После выхода/удаления сессия → LoggedOut, корневой граф уходит на вход сам.
struct SettingsView: View {
    @Environment(AppContainer.self) private var app
    @Environment(Navigator.self) private var nav
    @Environment(\.scenePhase) private var scenePhase
    @State private var canPost = true
    @State private var confirm: Confirm?
    @State private var busy = false
    @State private var error: String?
    @AppStorage("app_theme") private var theme = AppearanceMode.system
    @State private var chooseTheme = false
    @State private var document: URL?

    private enum Confirm: Identifiable { case logout, delete; var id: Self { self } }

    var body: some View {
        let email: String? = { if case .loggedIn(let e) = app.session.state { return e } else { return nil } }()
        let anonymous = email == nil
        ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    SectionTitle(L.s("settings_notifications"))
                    SwitchRow(title: L.s("settings_reminders"), subtitle: L.s("settings_reminders_hint"),
                              isOn: Binding(get: { app.reminderSettings.enabled }, set: { app.reminderSettings.setEnabled($0) }))
                    if app.reminderSettings.enabled && !canPost {
                        ActionRow(title: L.s("settings_notifications_open"), titleColor: AppColors.primary) {
                            if let url = URL(string: UIApplication.openNotificationSettingsURLString) { UIApplication.shared.open(url) }
                        }
                        hint(L.s("settings_notifications_off"))
                    }

                    // Язык: своего переключателя нет (решение 2026-11-16) — открываем настройки приложения в «Настройках»
                    // iOS, там пункт «Язык». Новый язык iOS применяет, перезапуская приложение.
                    ActionRow(title: L.s("settings_language"),
                              value: L.s(AppLocale.current() == .ru ? "language_ru" : "language_en")) {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                    ActionRow(title: L.s("theme_title"), value: L.s(theme.titleKey)) { chooseTheme = true }
                        .confirmationDialog(L.s("theme_title"), isPresented: $chooseTheme, titleVisibility: .visible) {
                            ForEach(AppearanceMode.allCases, id: \.self) { mode in
                                Button(L.s(mode.titleKey)) {
                                    guard theme != mode else { return }
                                    theme = mode
                                    Analytics.track(.themeChanged(mode: mode))
                                }
                            }
                        }

                    SectionTitle(L.s("settings_account"))
                    if busy { ProgressView().frame(maxWidth: .infinity) }
                    if anonymous {
                        // Гость: выход стёр бы дневник без возможности вернуть, поэтому вместо него — привязка почты.
                        ActionRow(title: L.s("settings_link_email"), titleColor: AppColors.primary) { nav.open(.linkEmail) }
                        hint(L.s("settings_link_email_hint"))
                    } else {
                        ActionRow(title: email ?? "")
                        AppButton(L.s("settings_logout"), kind: .ghost) { if !busy { confirm = .logout } }
                    }
                    if let userId = app.tokens.userId {
                        AppCard {
                            Text(L.s("settings_user_id")).font(AppFont.titleMedium)
                            Text(userId).font(AppFont.bodyMedium).foregroundStyle(AppColors.inkMuted)
                                .textSelection(.enabled)
                        }
                    }
                    AppButton(L.s(anonymous ? "settings_delete_data" : "settings_delete_account"), kind: .danger) {
                        if !busy { confirm = .delete }
                    }
                    if let error { Text(error).font(AppFont.bodyLarge).foregroundStyle(AppColors.alert).padding(.leading, 6) }

                    SectionTitle(L.s("settings_about"))
                    ActionRow(title: L.s("settings_app_version"), value: appVersion)
                    ActionRow(title: L.s("settings_privacy")) { openDocument(.privacy) }
                    ActionRow(title: L.s("settings_terms")) { openDocument(.terms) }

                    if AssistantPilot.enabled {
                        SectionTitle(L.s("settings_debug"))
                        ActionRow(title: L.s("assistant_entry")) {
                        nav.open(.assistant(productId: nil))
                        Analytics.track(.assistantOpened(source: .settings))
                    }
                    }
                    #if DEBUG
                    Picker(L.s("settings_debug_strategy"), selection: Binding(
                        get: { app.recommendations.debugStrategy }, set: { app.recommendations.debugStrategy = $0 }
                    )) {
                        ForEach(Strategies.all, id: \.id) { strategy in
                            Text(strategy.title[UiLocale.language.rawValue] ?? strategy.id).tag(strategy.id)
                        }
                    }
                    .pickerStyle(.menu)
                    ActionRow(title: L.s("settings_rerun_onboarding")) { app.onboarding.set(false) }
                    #endif
                }
                .padding(.horizontal, screenPadding)
                .padding(.bottom, 24)
        }
        .appScreen()
        .navigationTitle(L.s("settings"))
        .sheet(item: $document) { SafariView(url: $0).ignoresSafeArea() }
        // Разрешение могут выдать в системных настройках — перепроверяем при возвращении.
        .task(id: scenePhase) { canPost = await app.reminders.canPost() }
        .alert(item: $confirm) { kind in
            Alert(
                title: Text(L.s(kind == .logout ? "settings_logout_confirm" : (anonymous ? "settings_delete_data_confirm" : "settings_delete_confirm"))),
                primaryButton: .destructive(Text(L.s(kind == .logout ? "settings_logout" : "delete"))) {
                    if kind == .logout { app.auth.logout() } else { deleteAccount() }
                },
                secondaryButton: .cancel(Text(L.s("cancel")))
            )
        }
    }

    private var appVersion: String? {
        guard let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String else { return nil }
        guard let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String else { return version }
        return "\(version) (\(build))"
    }

    private func openDocument(_ type: AnalyticsEvent.LegalDocument) {
        guard let url = URL(string: L.s(type == .privacy ? "url_privacy" : "url_terms")) else { return }
        document = url
        Analytics.track(.legalDocumentOpened(document: type))
    }

    private func hint(_ text: String) -> some View {
        Text(text).font(AppFont.bodyMedium).foregroundStyle(AppColors.inkMuted).padding(.leading, 6)
    }

    private func deleteAccount() {
        busy = true; error = nil
        Task {
            if case .failure(let e) = await app.auth.deleteAccount() { error = ErrorText.message(e) }
            busy = false
        }
    }
}

/// Привязка почты к анонимному аккаунту: почта → код. Почта занята → «Войти в этот аккаунт» (дневник с телефона сохранится).
struct LinkEmailFlow: View {
    @Environment(AppContainer.self) private var app
    @Environment(Navigator.self) private var nav
    @State private var model: AuthViewModel?

    var body: some View {
        ZStack {
            if let model {
                AuthEmailView(model: model, onCodeSent: { nav.open(.authCode($0)) }, onLoginInstead: {
                    let login = make(.login)
                    login.email = model.email
                    self.model = login
                })
                .id(ObjectIdentifier(model))
            }
        }
        .appScreen()
        .onAppear { if model == nil { model = make(.link) } }
    }

    private func make(_ mode: AuthMode) -> AuthViewModel {
        let m = AuthViewModel(auth: app.auth, mode: mode)
        m.onSuccess = { nav.path.removeAll() }
        return m
    }
}
