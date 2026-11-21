import Foundation
import UserNotifications
import FirstSpoonCore

/// Напоминания **вычисляются из данных**, а не ставятся по событиям: `ReminderRules.plan` (Core, unit-тесты) →
/// здесь сравниваем с запросами UNUserNotificationCenter (один запрос на `ReminderKind`, id = kind) и заменяем/снимаем.
/// Пересчёт — на любое изменение данных, настроек и при старте.
@MainActor
final class ReminderScheduler {
    private let center = UNUserNotificationCenter.current()
    private let settings: ReminderSettings
    private let onboarding: OnboardingStore
    private let diary: DiaryRepository
    private let catalog: CatalogRepository
    private let accountStarted: () -> Bool
    private var lastPlan: [PlannedReminder]?

    init(settings: ReminderSettings, onboarding: OnboardingStore, diary: DiaryRepository, catalog: CatalogRepository,
         accountStarted: @escaping () -> Bool) {
        self.settings = settings
        self.onboarding = onboarding
        self.diary = diary
        self.catalog = catalog
        self.accountStarted = accountStarted
    }

    /// Что должно стоять сейчас (и для debug-экрана).
    func plan(now: LocalDateTime = .now()) -> [PlannedReminder] {
        guard accountStarted(), let child = diary.activeChild else { return [] }
        let onboardedAt = onboarding.done ? onboarding.doneAt.map { LocalDateTime.now($0) } : nil
        return ReminderRules.plan(ReminderInput(
            now: now, enabled: settings.enabled, onboardedAt: onboardedAt, childName: child.name,
            entries: diary.entries, marks: diary.marks,
            productNames: Dictionary(catalog.catalog.products.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a }),
            // Пока малыш не готов к прикорму, «Начнём прикорм?» не шлём.
            readyForNewFoods: FeedingReadiness.canOfferNewFoods(FeedingReadiness.current(
                birthDate: child.birthDate, profile: child.profile,
                started: FeedingReadiness.started(entries: diary.entries, marks: diary.marks), today: now.toLocalDate())),
            blockedProducts: Set(catalog.catalog.products.filter { $0.containsKnownAllergen(child.profile.knownAllergens) }.map(\.id))
        ))
    }

    func refresh() {
        let plan = plan()
        guard plan != lastPlan else { return }
        lastPlan = plan
        let ids = Set(plan.map(\.id))
        center.removePendingNotificationRequests(withIdentifiers: ReminderKind.allCases.map(\.rawValue).filter { !ids.contains($0) })
        for reminder in plan {
            guard let date = reminder.fireAt.toDate() else { continue }
            let content = Self.content(reminder)
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            let request = UNNotificationRequest(identifier: reminder.id, content: content,
                                                trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
            center.add(request)
        }
    }

    /// Системный запрос разрешения — один раз, при первом попадании в приложение после онбординга.
    func askPermissionOnce() {
        guard !settings.permissionAsked else { return }
        settings.permissionAsked = true
        Task {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
            lastPlan = nil
            refresh()
        }
    }

    func canPost() async -> Bool {
        let s = await center.notificationSettings()
        return s.authorizationStatus == .authorized || s.authorizationStatus == .provisional
    }

    static func content(_ r: PlannedReminder) -> UNMutableNotificationContent {
        let c = UNMutableNotificationContent()
        switch r.kind {
        case .firstEntry:
            c.title = L.s("notif_first_entry_title")
            c.body = L.s("notif_first_entry_text")
        case .continueSeries:
            c.title = L.s("notif_series_title")
            c.body = r.productNames.count == 1
                ? L.s("notif_series_text_one", r.productNames[0])
                : L.s("notif_series_text_many", r.productNames.joined(separator: ", "))
        }
        c.sound = .default
        c.userInfo = ["kind": r.kind.rawValue, "product_id": r.productIds.first ?? ""]
        return c
    }
}
