import Foundation
import os
import AppMetricaCore
import AppMetricaCrashes
import FirstSpoonCore

/// AppMetrica: сессии, падения + наши события (`AnalyticsEvent`). Ключ — **тот же, что в Android**
/// (`APPMETRICA_API_KEY` в `app/build.gradle.kts`): одно приложение в консоли, общие отчёты. Ключ не секрет.
///
/// - рекламный идентификатор не собираем: `AppMetricaAdSupport` не подключён, `advertisingIdentifierTrackingEnabled = false`;
/// - геолокацию и автоучёт покупок StoreKit — тоже нет;
/// - debug-сборки данные не отправляют (`dataSendingEnabled = false`), события видны в логе (`LogTracker`).
/// Меняется состав данных — до выпуска обновить «Конфиденциальность приложения» в App Store Connect.
struct AppMetricaTracker: AnalyticsTracker {
    static let apiKey = "d66b8eef-cbfa-4321-b172-c35b5d6c1557"

    func track(_ event: AnalyticsEvent) {
        if event.params.isEmpty {
            AppMetrica.reportEvent(name: event.name, onFailure: nil)
        } else {
            AppMetrica.reportEvent(name: event.name, parameters: event.params.mapValues(\.any), onFailure: nil)
        }
    }

    /// Включить AppMetrica (вызывать один раз при запуске). nil — ключа нет.
    static func activate() -> AppMetricaTracker? {
        guard !apiKey.isEmpty, let config = AppMetricaConfiguration(apiKey: apiKey) else { return nil }
        config.advertisingIdentifierTrackingEnabled = false
        config.locationTracking = false
        config.revenueAutoTrackingEnabled = false
        config.appEnvironment = ["store": "appstore"]
        let info = Bundle.main.infoDictionary
        config.appVersion = info?["CFBundleShortVersionString"] as? String
        config.appBuildNumber = info?["CFBundleVersion"] as? String
        #if DEBUG
        config.dataSendingEnabled = false
        config.areLogsEnabled = false
        #endif
        AppMetricaCrashes.crashes().initializeCrashMonitoring(with: AppMetricaCrashesConfiguration())
        AppMetrica.activate(with: config)
        return AppMetricaTracker()
    }
}

/// Debug: события в системный лог (`log stream --predicate 'category == "Analytics"'`).
struct LogTracker: AnalyticsTracker {
    private static let log = Logger(subsystem: "app.littlebite", category: "Analytics")
    func track(_ event: AnalyticsEvent) {
        let text = event.params.isEmpty ? event.name
            : event.name + " " + event.params.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
        Self.log.notice("\(text, privacy: .public)")
    }
}
