import SwiftUI
import FirstSpoonCore

enum CatalogFilter: CaseIterable {
    case all, favorites, notTried, inProgress, introduced, attention

    var label: String {
        switch self {
        case .all: return L.s("filter_all")
        case .favorites: return L.s("filter_favorites")
        case .notTried: return L.s("filter_not_tried")
        case .inProgress: return L.s("filter_in_progress")
        case .introduced: return L.s("filter_introduced")
        case .attention: return L.s("filter_attention")
        }
    }

    func matches(_ row: CatalogRow) -> Bool {
        switch self {
        case .all: return true
        case .favorites: return row.liked
        case .notTried: return row.progress.status == .notTried
        case .inProgress: return row.progress.status == .inProgress
        case .introduced: return row.progress.status == .introduced
        case .attention: return row.progress.status.needsAttention
        }
    }
}

struct CatalogRow: Identifiable { var id: String { product.id }; let product: Product; let progress: ProductProgress; let liked: Bool }

/// Поиск и фильтр вкладки — переживают переключение вкладок.
@Observable final class CatalogViewState {
    var query = ""
    var filter = CatalogFilter.all
}

/// Каталог. Вкладка «Продукты»: тап открывает страницу продукта. Режим выбора для пробы (`pickMode`): тап возвращает продукт.
struct CatalogView: View {
    @Environment(AppContainer.self) private var app
    @Environment(Navigator.self) private var nav
    @Bindable var state: CatalogViewState
    var pickMode = false
    var onBack: (() -> Void)?
    let onPick: (String) -> Void

    var body: some View {
        let sections = makeSections()
        ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(CatalogFilter.allCases, id: \.self) { f in
                                AppChip(label: f.label, selected: state.filter == f) { state.filter = f }
                            }
                        }
                        .padding(.horizontal, screenPadding)
                        .padding(.vertical, 2)
                    }
                    if sections.isEmpty {
                        EmptyState(emoji: "🔍", title: L.s("catalog_empty_title"), text: L.s("catalog_empty"))
                        AppButton(L.s("custom_add"), kind: .soft, icon: "plus") { addCustom() }
                            .padding(.horizontal, screenPadding).padding(.top, 12)
                    }
                    ForEach(sections, id: \.0.id) { category, rows in
                        SectionTitle(category.name).padding(.horizontal, screenPadding)
                        ForEach(rows) { row in
                            CatalogItem(row: row) { onPick(row.product.id) }.padding(.horizontal, screenPadding)
                        }
                    }
                }
                .padding(.bottom, 32)
        }
        .scrollDismissesKeyboard(.immediately)
        .appScreen()
        .navigationTitle(L.s(pickMode ? "entry_product_pick" : "products_title"))
        .searchable(text: $state.query, placement: .navigationBarDrawer(displayMode: .always), prompt: L.s("catalog_search"))
        .toolbar {
            if let onBack {
                ToolbarItem(placement: .cancellationAction) { Button(L.s("cancel"), action: onBack) }
            }
            // «Свой продукт» — всегда справа в навбаре (и во вкладке, и при выборе продукта для пробы).
            ToolbarItem(placement: .primaryAction) {
                Button(action: addCustom) { Image(systemName: "plus") }.accessibilityLabel(L.s("custom_add"))
            }
        }
    }

    private func addCustom() { nav.open(.customProduct(query: state.query)) }

    private func makeSections() -> [(FirstSpoonCore.Category, [CatalogRow])] {
        let catalog = app.catalog.catalog
        let progress = FeedingRules.progressByProduct(app.diary.entries, marks: app.diary.marks)
        let needle = state.query.trimmingCharacters(in: .whitespaces).lowercased()
        let rows = catalog.products
            .map { CatalogRow(product: $0, progress: progress[$0.id] ?? ProductProgress(productId: $0.id, tries: 0, status: .notTried),
                              liked: app.diary.favorites.contains($0.id)) }
            .filter { (needle.isEmpty || $0.product.name.lowercased().contains(needle)) && state.filter.matches($0) }
        let byCategory = Dictionary(grouping: rows, by: { (r: CatalogRow) in r.product.categoryId })
        return catalog.categories.compactMap { c in byCategory[c.id].map { (c, $0) } }
    }
}

private struct CatalogItem: View {
    let row: CatalogRow
    let onTap: () -> Void
    var body: some View {
        let p = row.product
        let details = ([p.isCustom ? nil : L.s("catalog_age", p.minAgeMonths),
                        p.isAllergen ? L.s("catalog_allergen", p.allergens.joined(separator: ", ")) : nil] as [String?])
            .compactMap { $0 }.joined(separator: " · ")
        ProductCard(productId: p.id, name: p.name, onTap: onTap,
                    supporting: {
                        VStack(alignment: .leading, spacing: 8) {
                            if !details.isEmpty { Text(details).font(AppFont.bodyMedium).foregroundStyle(AppColors.inkMuted) }
                            if row.progress.status != .notTried { StatusBadge(status: row.progress.status, tries: row.progress.tries) }
                        }
                    },
                    trailing: {
                        HStack(spacing: 0) {
                            if row.liked {
                                Image(systemName: "heart.fill").font(.system(size: 18)).foregroundStyle(AppColors.alert)
                                    .accessibilityLabel(L.s("filter_favorites"))
                            }
                            Chevron()
                        }
                    },
                    footer: { EmptyView() })
    }
}
