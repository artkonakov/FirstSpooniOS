import SwiftUI
import FirstSpoonCore

/// Все пробы активного ребёнка по дням, свежие сверху.
struct DiaryView: View {
    @Environment(AppContainer.self) private var app
    @Environment(Navigator.self) private var nav

    var body: some View {
        let records = DiaryTimelineItem.newestFirst(entries: app.diary.entries, meals: app.diary.recipeMeals)
        let countKey = app.diary.recipeMeals.isEmpty ? "diary_count" : "diary_record_count"
        var days: [(LocalDate, [DiaryTimelineItem])] = []
        for record in records {
            if days.last?.0 == record.date { days[days.count - 1].1.append(record) }
            else { days.append((record.date, [record])) }
        }
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                Text(L.plural(countKey, records.count, app.diary.activeChild?.name ?? "", records.count))
                    .font(AppFont.bodyLarge).foregroundStyle(AppColors.inkMuted)
                if days.isEmpty {
                    EmptyState(emoji: "📖", title: L.s("home_empty_title"), text: L.s("diary_empty"))
                }
                ForEach(days, id: \.0) { day in
                    SectionTitle(Labels.dayTitle(day.0))
                    ForEach(day.1) { record in
                        switch record {
                        case .product(let entry):
                            EntryCard(entry: entry, name: name(entry.productId)) {
                                nav.open(.entry(entryId: entry.id, productId: nil))
                            }
                        case .meal(let meal):
                            RecipeMealCard(meal: meal) {
                                nav.open(.recipeMeal(recipeId: nil, childId: nil, entryId: meal.id))
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, screenPadding)
            .padding(.bottom, 24)
        }
        .appScreen()
        .navigationTitle(L.s("diary_title"))
    }

    private func name(_ id: String) -> String { app.catalog.catalog.productsById[id]?.name ?? id }
}

private struct EntryCard: View {
    @Environment(AppContainer.self) private var app
    let entry: DiaryEntry
    let name: String
    let onTap: () -> Void
    var body: some View {
        let meta = [entry.time.map(UiLocale.time), entry.meal.map(Labels.label), entry.amount.map(Labels.label)].compactMap { $0 }.joined(separator: " · ")
        ProductCard(productId: entry.productId, name: name, onTap: onTap,
                    supporting: {
                        if !meta.isEmpty { Text(meta).font(AppFont.bodyMedium).foregroundStyle(AppColors.inkMuted) }
                        EntryPhotoBadge(store: app.photos, photos: entry.photos)
                    },
                    trailing: { Text(Labels.emoji(entry.reaction)).font(.system(size: 30)).padding(.trailing, 4) },
                    footer: { EmptyView() })
    }
}
