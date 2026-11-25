import SwiftUI
import FirstSpoonCore

typealias AppearanceMode = AnalyticsEvent.Theme

extension AppearanceMode {
    var titleKey: String { "theme_\(rawValue)" }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
