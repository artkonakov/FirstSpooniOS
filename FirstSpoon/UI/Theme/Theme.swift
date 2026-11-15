import SwiftUI
import UIKit
import CoreText

/*
 * Тема «крупно и мягко» (как в Android `ui/theme/Theme.kt`): шрифт Onest, крупная типографика, большие скругления,
 * белые карточки на тёплом фоне. Цвета статусов — только для текста и бейджей, карточки всегда белые.
 */

extension Color {
    /// Цвет, меняющийся со светлой/тёмной темой.
    init(light: UInt32, dark: UInt32) {
        self.init(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

/// Палитра приложения. В экранах — только отсюда, `Color(...)` с литералами в экранах не писать.
enum AppColors {
    static let primary = Color(light: 0x5B3FD1, dark: 0xB7A6FF)
    static let onPrimary = Color(light: 0xFFFFFF, dark: 0x241466)
    static let background = Color(light: 0xF7F4EF, dark: 0x141217)
    static let surface = Color(light: 0xFFFFFF, dark: 0x221F26)

    static let ink = Color(light: 0x1F1B24, dark: 0xF2EEF6)
    static let inkMuted = Color(light: 0x5E5866, dark: 0xB9B2C2)
    static let inkFaint = Color(light: 0x9A93A3, dark: 0x857E8E)
    static let surfaceSoft = Color(light: 0xF0ECE6, dark: 0x2E2A33)
    static let line = Color(light: 0xE7E1D9, dark: 0x3A3540)
    static let primarySoft = Color(light: 0xECE7FF, dark: 0x332A5C)
    static let good = Color(light: 0x2F8F5B, dark: 0x7FD3A1)
    static let goodSoft = Color(light: 0xE3F4E8, dark: 0x1F3A2A)
    static let progress = Color(light: 0xC2621B, dark: 0xF2A66B)
    static let progressSoft = Color(light: 0xFDEBDD, dark: 0x3F2A1A)
    static let alert = Color(light: 0xC2364B, dark: 0xF08A9A)
    static let alertSoft = Color(light: 0xFCE4E7, dark: 0x45222A)
    static let neutralSoft = Color(light: 0xEEEAE4, dark: 0x2E2A33)
}

/// Скругления (как `AppShapes` в Android).
enum AppRadius {
    static let small: CGFloat = 18   // превью продукта
    static let medium: CGFloat = 20  // поля, плитки выбора
    static let large: CGFloat = 28   // карточки
}

/// Горизонтальный отступ экранов.
let screenPadding: CGFloat = 20

/// Типографика Onest (вариативный шрифт: вес задаём осью `wght`).
enum AppFont {
    static func onest(_ size: CGFloat, _ weight: CGFloat) -> Font {
        Font(uiFont(size, weight))
    }

    static func uiFont(_ size: CGFloat, _ weight: CGFloat) -> UIFont {
        registerOnce
        let wght = 0x77676874 // 'wght'
        let descriptor = UIFontDescriptor(fontAttributes: [
            .name: "Onest-Regular",
            UIFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String): [wght: weight],
        ])
        return UIFont(descriptor: descriptor, size: size)
    }

    private static let registerOnce: Void = {
        if let url = Bundle.main.url(forResource: "Onest", withExtension: "ttf") {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }()

    static let displaySmall = onest(40, 800)   // заголовок экрана
    static let headlineMedium = onest(32, 800) // крупные числа
    static let headlineSmall = onest(26, 700)  // заголовок секции
    static let titleLarge = onest(21, 700)
    static let titleMedium = onest(19, 700)    // название продукта, кнопки
    static let titleSmall = onest(17, 700)
    static let bodyLarge = onest(18, 400)
    static let bodyMedium = onest(16, 400)
    static let bodySmall = onest(14, 400)
    static let labelLarge = onest(17, 600)
    static let labelMedium = onest(15, 700)    // бейджи
    static let labelSmall = onest(13, 600)
}

extension View {
    /// Мягкая тень карточек: почти незаметная, только чтобы белое отделялось от тёплого фона.
    func softShadow(radius: CGFloat = 10) -> some View {
        shadow(color: .black.opacity(0.06), radius: radius / 2, x: 0, y: radius / 4)
    }
}

/// Системные панели (навбар, таб-бар) остаются нативными; задаём только шрифт Onest и цвета бренда.
enum SystemBars {
    static func configure() {
        let ink = UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: 0xF2EEF6) : UIColor(hex: 0x1F1B24) }
        let large: [NSAttributedString.Key: Any] = [.font: AppFont.uiFont(34, 800), .foregroundColor: ink]
        let inline: [NSAttributedString.Key: Any] = [.font: AppFont.uiFont(17, 700), .foregroundColor: ink]

        let standard = UINavigationBarAppearance()
        standard.configureWithDefaultBackground()
        standard.largeTitleTextAttributes = large
        standard.titleTextAttributes = inline
        let edge = UINavigationBarAppearance()
        edge.configureWithTransparentBackground()
        edge.largeTitleTextAttributes = large
        edge.titleTextAttributes = inline
        let bar = UINavigationBar.appearance()
        bar.standardAppearance = standard
        bar.compactAppearance = standard
        bar.scrollEdgeAppearance = edge
    }
}
