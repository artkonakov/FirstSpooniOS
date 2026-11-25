import SwiftUI
import UserNotifications
import FirstSpoonCore

@main
struct FirstSpoonApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var container = AppContainer()
    @AppStorage("app_theme") private var theme = AppearanceMode.system

    init() { SystemBars.configure() }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(container)
                .tint(AppColors.primary)
                .preferredColorScheme(theme.colorScheme)
        }
        .backgroundTask(.appRefresh(DiarySync.backgroundIdentifier)) {
            await container.diarySync.refresh()
            await container.diarySync.scheduleBackground()
        }
    }
}

/// Уведомления показываем и когда приложение открыто.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        // Аналитика: AppMetrica (ключ общий с Android) + лог в debug. Каталог событий и правила — docs/analytics.md.
        var trackers: [AnalyticsTracker] = []
        if let appMetrica = AppMetricaTracker.activate() { trackers.append(appMetrica) }
        #if DEBUG
        trackers.append(LogTracker())
        #endif
        Analytics.install(trackers)
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions { [.banner, .sound] }
}

/// Корень: граф выбирается только `AppContainer.rootGraph` (вход → онбординг → приложение).
struct RootView: View {
    @Environment(AppContainer.self) private var app
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Group {
                switch app.rootGraph {
                case .auth: AuthFlow()
                case .onboarding: OnboardingFlow().modifier(RestoreDiaryPrompt(sync: app.diarySync))
                case .main: MainFlow()
                }
            }
            // iPad: приложение — колонка удобной ширины по центру, а не карточки на всю ширину 13".
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
            .background(AppColors.background.ignoresSafeArea())
            // Блокирующий экран поверх всего — только при запрете сети для приложения (не авиарежим, не сбой сети).
            if app.networkAccess.blocked {
                NetworkBlockedView().transition(.opacity).zIndex(1)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: app.networkAccess.blocked)
        .animation(.easeInOut(duration: 0.25), value: app.rootGraph)
        // Пересчёт напоминаний на любое изменение данных и настроек.
        .onChange(of: app.catalog.catalog.products) { app.reminders.refresh(); app.diarySync.schedule() }
        .onChange(of: app.diary.version) { app.reminders.refresh(); app.diarySync.schedule() }
        .task(id: app.session.state) { await app.diarySync.refresh() }
        .onChange(of: app.reminderSettings.enabled) { app.reminders.refresh() }
        .onChange(of: app.onboarding.done) { app.reminders.refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { app.reminders.refresh(); app.networkAccess.refresh(); app.diarySync.schedule() }
            if phase == .background { app.diarySync.scheduleBackground() }
        }
    }
}
