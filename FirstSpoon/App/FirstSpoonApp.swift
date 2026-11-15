import SwiftUI
import UserNotifications

@main
struct FirstSpoonApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var container = AppContainer()

    init() { SystemBars.configure() }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(container)
                .tint(AppColors.primary)
        }
    }
}

/// Уведомления показываем и когда приложение открыто.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
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
        Group {
            switch app.rootGraph {
            case .auth: AuthFlow()
            case .onboarding: OnboardingFlow()
            case .main: MainFlow()
            }
        }
        .animation(.easeInOut(duration: 0.25), value: app.rootGraph)
        // Пересчёт напоминаний на любое изменение данных и настроек.
        .onChange(of: app.diary.version) { app.reminders.refresh() }
        .onChange(of: app.reminderSettings.enabled) { app.reminders.refresh() }
        .onChange(of: app.onboarding.done) { app.reminders.refresh() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { app.reminders.refresh() } }
    }
}
