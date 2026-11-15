import SwiftUI
import UIKit
import FirstSpoonCore

/// Картинка продукта в мягком квадрате; для своих продуктов (и без картинки) — первая буква названия.
struct ProductThumb: View {
    let productId: String
    let name: String
    var size: CGFloat = 56

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.32, style: .continuous).fill(AppColors.surfaceSoft)
            if let image = ProductImages.image(productId) {
                Image(uiImage: image).resizable().scaledToFit().frame(width: size * 0.82, height: size * 0.82)
            } else {
                Text(name.prefix(1).uppercased()).font(AppFont.titleLarge).foregroundStyle(AppColors.inkMuted)
            }
        }
        .frame(width: size, height: size)
    }
}

/// slug продукта → картинка из `Assets.xcassets/Products` (`product_<slug с _ вместо ->`, как в Android).
enum ProductImages {
    static func image(_ slug: String) -> UIImage? {
        UIImage(named: "product_" + slug.replacingOccurrences(of: "-", with: "_"))
    }
}

/// Пилюля с иконкой и текстом в цвете статуса.
struct Badge: View {
    let text: String
    let color: Color
    let background: Color
    var icon: String?
    var body: some View {
        HStack(spacing: 6) {
            if let icon { Image(systemName: icon).font(.system(size: 15, weight: .bold)) }
            Text(text).font(AppFont.labelMedium).lineLimit(1)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 12)
        .frame(height: 32)
        .background(background, in: Capsule())
    }
}

/// Точки серии без подписи.
struct Dots: View {
    let filled: Int
    let total: Int
    let color: Color
    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<total, id: \.self) { i in
                Circle().fill(i < filled ? color : AppColors.inkFaint.opacity(0.3)).frame(width: 12, height: 12)
            }
        }
    }
}

/// Бейдж статуса продукта. Для `.notTried` ничего не рисует; `.inProgress` показывает точки серии.
struct StatusBadge: View {
    let status: ProductStatus
    let tries: Int
    var body: some View {
        switch status {
        case .notTried: EmptyView()
        case .inProgress:
            HStack(spacing: 8) {
                Dots(filled: tries, total: FeedingRules.seriesTarget, color: AppColors.progress)
                Text(L.s("series_of", tries, FeedingRules.seriesTarget)).font(AppFont.labelMedium).foregroundStyle(AppColors.progress)
            }
            .padding(.horizontal, 12).frame(height: 32)
            .background(AppColors.progressSoft, in: Capsule())
        case .introduced:
            Badge(text: L.s("status_introduced"), color: AppColors.good, background: AppColors.goodSoft, icon: "checkmark.circle.fill")
        case .reaction:
            Badge(text: L.s("status_reaction"), color: AppColors.alert, background: AppColors.alertSoft, icon: "exclamationmark.triangle.fill")
        case .allergy:
            Badge(text: L.s("status_allergy"), color: AppColors.alert, background: AppColors.alertSoft, icon: "exclamationmark.triangle.fill")
        case .excluded:
            Badge(text: L.s("status_excluded"), color: AppColors.inkMuted, background: AppColors.neutralSoft)
        }
    }
}

/// Строка продукта: превью, название, `supporting` под названием, `trailing` справа.
struct ProductRow<Supporting: View, Trailing: View>: View {
    let productId: String
    let name: String
    @ViewBuilder var supporting: () -> Supporting
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 16) {
            ProductThumb(productId: productId, name: name)
            VStack(alignment: .leading, spacing: 8) {
                Text(name).font(AppFont.titleMedium).foregroundStyle(AppColors.ink).multilineTextAlignment(.leading)
                supporting()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing()
        }
    }
}

/// Карточка продукта: строка продукта + `footer` под ней (например, «Записать 2-ю пробу»).
struct ProductCard<Supporting: View, Trailing: View, Footer: View>: View {
    let productId: String
    let name: String
    var onTap: (() -> Void)?
    @ViewBuilder var supporting: () -> Supporting
    @ViewBuilder var trailing: () -> Trailing
    @ViewBuilder var footer: () -> Footer

    var body: some View {
        AppCard(padding: EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16), onTap: onTap) {
            ProductRow(productId: productId, name: name, supporting: supporting, trailing: trailing)
            footer()
        }
    }
}

extension ProductCard where Trailing == Chevron, Footer == EmptyView {
    init(productId: String, name: String, onTap: @escaping () -> Void, @ViewBuilder supporting: @escaping () -> Supporting) {
        self.init(productId: productId, name: name, onTap: onTap, supporting: supporting, trailing: { Chevron() }, footer: { EmptyView() })
    }
}

extension ProductCard where Supporting == EmptyView, Trailing == Chevron, Footer == EmptyView {
    init(productId: String, name: String, onTap: @escaping () -> Void) {
        self.init(productId: productId, name: name, onTap: onTap, supporting: { EmptyView() }, trailing: { Chevron() }, footer: { EmptyView() })
    }
}

/// Аватар ребёнка: эмодзи по полу на мягком круге.
struct ChildAvatar: View {
    let child: Child
    var size: CGFloat = 56
    var body: some View {
        Text(child.sex.map(Labels.emoji) ?? "👶")
            .font(.system(size: size * 0.5))
            .frame(width: size, height: size)
            .background(AppColors.primarySoft, in: Circle())
    }
}
