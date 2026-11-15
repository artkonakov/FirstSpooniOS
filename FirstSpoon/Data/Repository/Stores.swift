import Foundation
import Observation

/// Настройки устройства (не данные дневника) — в UserDefaults, как prefs в Android.

/// Пройден ли онбординг профиля ребёнка на этом устройстве. Онбординг показывается, если флага нет ИЛИ детей нет
/// (например, после выхода дневник стёрт) — поэтому при выходе флаг не сбрасываем.
@MainActor @Observable
final class OnboardingStore {
    @ObservationIgnored private let defaults: UserDefaults
    private(set) var done: Bool
    /// Когда онбординг пройден — от этого считаются напоминания.
    private(set) var doneAt: Date?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        done = defaults.bool(forKey: "onboarding_done")
        doneAt = defaults.object(forKey: "onboarding_done_at") as? Date
        if done && doneAt == nil {
            doneAt = Date()
            defaults.set(doneAt, forKey: "onboarding_done_at")
        }
    }

    func set(_ value: Bool) {
        done = value
        doneAt = value ? Date() : nil
        defaults.set(value, forKey: "onboarding_done")
        defaults.set(doneAt, forKey: "onboarding_done_at")
    }
}

/// Какой ребёнок выбран сейчас. Если id нет или ребёнок удалён — активным считается первый.
@MainActor @Observable
final class ActiveChildStore {
    @ObservationIgnored private let defaults: UserDefaults
    private(set) var id: String?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        id = defaults.string(forKey: "active_child_id")
    }

    func set(_ value: String?) {
        id = value
        defaults.set(value, forKey: "active_child_id")
    }
}

/// Настройки напоминаний: включены ли и спрашивали ли уже разрешение.
@MainActor @Observable
final class ReminderSettings {
    @ObservationIgnored private let defaults: UserDefaults
    private(set) var enabled: Bool
    var permissionAsked: Bool {
        get { defaults.bool(forKey: "reminders_permission_asked") }
        set { defaults.set(newValue, forKey: "reminders_permission_asked") }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        enabled = defaults.object(forKey: "reminders_enabled") as? Bool ?? true
    }

    func setEnabled(_ value: Bool) {
        enabled = value
        defaults.set(value, forKey: "reminders_enabled")
    }
}
