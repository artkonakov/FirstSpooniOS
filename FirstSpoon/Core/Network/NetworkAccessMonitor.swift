import Foundation
import Network
import Observation
import UIKit
import SwiftUI
import FirstSpoonCore

/// Запрещён ли приложению доступ к сети в настройках телефона (Настройки → <приложение> → Беспроводные данные: «Выкл.»).
/// Только этот случай — блокирующий экран. Авиарежим, отсутствие сети и ошибки сервера сюда **не** относятся:
/// у них другой `unsatisfiedReason` (`.notAvailable`), с ними приложение работает офлайн как обычно.
/// Снимается само, когда доступ вернули (монитор присылает новый путь).
@MainActor @Observable
final class NetworkAccessMonitor {
    private(set) var blocked = false
    @ObservationIgnored private let monitor = NWPathMonitor()
    @ObservationIgnored private var reportedThisTime = false

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let denied = Self.isDenied(path)
            Task { @MainActor in self?.update(denied) }
        }
        monitor.start(queue: DispatchQueue(label: "app.littlebite.network-access"))
    }

    deinit { monitor.cancel() }

    nonisolated static func isDenied(_ path: NWPath) -> Bool {
        guard path.status == .unsatisfied else { return false }
        switch path.unsatisfiedReason {
        case .cellularDenied, .wifiDenied: return true
        default: return false
        }
    }

    private func update(_ denied: Bool) {
        var value = denied
        #if DEBUG
        // Debug: показать экран без реального запрета — `defaults write app.littlebite.dev debug_network_blocked -bool YES`.
        if UserDefaults.standard.bool(forKey: "debug_network_blocked") { value = true }
        #endif
        if value && !blocked && !reportedThisTime {
            reportedThisTime = true
            Analytics.track(.networkBlockedShown)
        }
        if !value { reportedThisTime = false }
        blocked = value
    }

    /// Перепроверка при возвращении в приложение (debug-флаг мог поменяться).
    func refresh() { update(Self.isDenied(monitor.currentPath)) }
}

/// Блокирующий экран поверх всего приложения: доступ к сети выключен в настройках телефона.
struct NetworkBlockedView: View {
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            Image(systemName: "wifi.slash")
                .font(.system(size: 64, weight: .semibold))
                .foregroundStyle(AppColors.primary)
                .frame(width: 120, height: 120)
                .background(AppColors.primarySoft, in: Circle())
            Text(L.s("network_blocked_title")).font(AppFont.displaySmall).foregroundStyle(AppColors.ink)
                .multilineTextAlignment(.center).padding(.top, 28)
            Text(L.s("network_blocked_text")).font(AppFont.bodyLarge).foregroundStyle(AppColors.inkMuted)
                .multilineTextAlignment(.center).padding(.top, 14)
            Spacer()
            AppButton(L.s("network_blocked_open_settings")) {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
        }
        .padding(.horizontal, screenPadding)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.background.ignoresSafeArea())
        .accessibilityAddTraits(.isModal)
    }
}
