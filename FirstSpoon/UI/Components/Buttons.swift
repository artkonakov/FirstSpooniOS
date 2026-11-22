import SwiftUI

enum ButtonKind {
    /// Главное действие экрана: фиолетовая, белый текст.
    case primary
    /// Второстепенное: светло-фиолетовая, фиолетовый текст.
    case soft
    /// Нейтральная: серо-бежевая.
    case ghost
    /// Опасное действие: розовая.
    case danger
}

enum ButtonSize {
    case large, medium
    var height: CGFloat { self == .large ? 64 : 52 }
    var horizontalPadding: CGFloat { self == .large ? 28 : 22 }
}

/// Кнопка-пилюля. По умолчанию на всю ширину, высота 64.
/// Для компактной — `size: .medium, fill: false`.
struct AppButton: View {
    let title: String
    var kind: ButtonKind = .primary
    var size: ButtonSize = .large
    var icon: String?
    var enabled = true
    var loading = false
    var fill = true
    let action: () -> Void

    init(_ title: String, kind: ButtonKind = .primary, size: ButtonSize = .large, icon: String? = nil,
         enabled: Bool = true, loading: Bool = false, fill: Bool = true, action: @escaping () -> Void) {
        self.title = title; self.kind = kind; self.size = size; self.icon = icon
        self.enabled = enabled; self.loading = loading; self.fill = fill; self.action = action
    }

    private var colors: (Color, Color) {
        if !enabled { return (AppColors.surfaceSoft, AppColors.inkFaint) }
        switch kind {
        case .primary: return (AppColors.primary, AppColors.onPrimary)
        case .soft: return (AppColors.primarySoft, AppColors.primary)
        case .ghost: return (AppColors.surfaceSoft, AppColors.ink)
        case .danger: return (AppColors.alertSoft, AppColors.alert)
        }
    }

    var body: some View {
        let (bg, fg) = colors
        Button(action: action) {
            HStack(spacing: 10) {
                if loading {
                    ProgressView().tint(fg)
                } else {
                    if let icon { Image(icon).font(.system(size: 20, weight: .bold)) }
                    Text(title).font(size == .large ? AppFont.titleMedium : AppFont.titleSmall).lineLimit(1)
                }
            }
            .foregroundStyle(fg)
            .padding(.horizontal, size.horizontalPadding)
            .frame(maxWidth: fill ? .infinity : nil, minHeight: size.height, maxHeight: size.height)
            .background(bg, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .disabled(!enabled || loading)
    }
}

/// Текстовая кнопка-ссылка («Отправить код ещё раз»).
struct TextLink: View {
    let title: String
    var enabled = true
    var color: Color = AppColors.primary
    let action: () -> Void

    init(_ title: String, enabled: Bool = true, color: Color = AppColors.primary, action: @escaping () -> Void) {
        self.title = title; self.enabled = enabled; self.color = color; self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title).font(AppFont.labelLarge).foregroundStyle(enabled ? color : AppColors.inkFaint)
                .padding(.horizontal, 12).frame(minHeight: 48)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}
