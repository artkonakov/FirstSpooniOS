import SwiftUI
import FirstSpoonCore

/// «13 из 100 — продуктов уже в меню». На главной открывает статистику по тапу; на экране статистики просто карточка.
struct ProgressCard: View {
    let introduced: Int
    let goal: Int
    var onTap: (() -> Void)?

    var body: some View {
        AppCard(onTap: onTap) {
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                HStack(alignment: .lastTextBaseline, spacing: 8) {
                    Text("\(introduced)").font(AppFont.displaySmall).foregroundStyle(AppColors.primary)
                    Text(L.s("home_progress_of", goal)).font(AppFont.titleLarge).foregroundStyle(AppColors.inkMuted)
                }
                Spacer(minLength: 0)
                if onTap != nil { Chevron() }
            }
            Text(L.s("home_progress_label")).font(AppFont.bodyLarge).foregroundStyle(AppColors.inkMuted)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(AppColors.surfaceSoft)
                    Capsule().fill(AppColors.primary)
                        .frame(width: geo.size.width * min(max(CGFloat(introduced) / CGFloat(goal), 0), 1))
                }
            }
            .frame(height: 14)
        }
        .accessibilityLabel("\(introduced) \(L.s("home_progress_of", goal))")
    }
}
