import SwiftUI
import FirstSpoonCore

/// Страница продукта: описание, статус, пробы, отметки и избранное для активного ребёнка.
struct ProductView: View {
    @Environment(AppContainer.self) private var app
    @Environment(Navigator.self) private var nav
    let productId: String
    @State private var confirmDelete = false

    private static let marks: [(ProductMark, String, String)] = [
        (.known, "mark_known", "✅"), (.allergy, "mark_allergy", "⚠️"), (.excluded, "mark_excluded", "🚫"),
    ]

    var body: some View {
        let catalog = app.catalog.catalog
        let own = app.diary.entries.filter { $0.productId == productId }
        let mark = app.diary.marks[productId]
        let progress = FeedingRules.progressOf(productId, own, mark: mark)
        let liked = app.diary.favorites.contains(productId)
        ScrollView {
            if let product = catalog.productsById[productId] {
                content(product, catalog: catalog, own: own, mark: mark, progress: progress)
                    .padding(.horizontal, screenPadding)
                    .padding(.vertical, 12)
            }
        }
        .bottomAction {
            if catalog.productsById[productId] != nil {
                AppButton(progress.status == .inProgress ? L.s("home_record_try", progress.tries + 1) : L.s("product_record_try"), icon: "plus") {
                    nav.open(.entry(entryId: nil, productId: productId))
                }
                .padding(.horizontal, screenPadding)
                .padding(.vertical, 12)
            }
        }
        .appScreen()
        .navigationTitle(catalog.productsById[productId]?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Свой продукт можно изменить (название, категория, аллергены, фото).
            if catalog.productsById[productId]?.isCustom == true {
                ToolbarItem(placement: .primaryAction) {
                    Button { nav.open(.editCustomProduct(productId)) } label: { Image(systemName: "pencil") }
                        .accessibilityLabel(L.s("custom_edit"))
                }
            }
            if catalog.productsById[productId] != nil {
                ToolbarItem(placement: .primaryAction) {
                    Button { try? app.diary.setLiked(productId, !liked) } label: {
                        Image(systemName: liked ? "heart.fill" : "heart").foregroundStyle(liked ? AppColors.alert : AppColors.primary)
                    }
                    .accessibilityLabel(L.s(liked ? "product_unlike" : "product_like"))
                }
            }
        }
        .alert(L.s("product_delete_custom_confirm", catalog.productsById[productId]?.name ?? ""), isPresented: $confirmDelete) {
            Button(L.s("delete"), role: .destructive) {
                guard canDelete(catalog) else { return }
                try? app.catalog.deleteCustomProduct(productId)
                nav.back()
            }
            Button(L.s("cancel"), role: .cancel) {}
        }
    }

    /// Свой продукт без проб (ни у одного ребёнка) можно удалить.
    private func canDelete(_ catalog: Catalog) -> Bool {
        catalog.productsById[productId]?.isCustom == true && !app.diary.hasEntries(productId)
    }

    @ViewBuilder
    private func content(_ product: Product, catalog: Catalog, own: [DiaryEntry], mark: ProductMark?, progress: ProductProgress) -> some View {
        let child = app.diary.activeChild
        let childAllergies = product.allergenIds.filter { child?.profile.knownAllergens.contains($0) == true }
            .compactMap { id in catalog.allergens.first { $0.id == id }?.name }
        let facts = [product.isCustom ? L.s("product_custom_note") : L.s("catalog_age", product.minAgeMonths),
                     product.isAllergen ? L.s("catalog_allergen", product.allergens.joined(separator: ", ")) : nil].compactMap { $0 }
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 18) {
                ProductThumb(productId: product.id, name: product.name, size: 112)
                VStack(alignment: .leading, spacing: 10) {
                    Text(product.name).font(AppFont.headlineMedium).foregroundStyle(AppColors.ink)
                    StatusBadge(status: progress.status, tries: progress.tries)
                }
            }
            Text(facts.joined(separator: " · ")).font(AppFont.bodyLarge).foregroundStyle(AppColors.inkMuted)
            if !childAllergies.isEmpty {
                AppCard {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(AppColors.alert)
                        Text(L.s("product_allergy_warning", child?.name ?? "", childAllergies.joined(separator: ", ")))
                            .font(AppFont.bodyLarge).foregroundStyle(AppColors.alert)
                    }
                }
            }
            if !product.description.isEmpty { InfoCard(title: L.s("product_about"), text: product.description) }
            if !product.firstServing.isEmpty { InfoCard(title: L.s("product_first_serving"), text: product.firstServing) }

            SectionTitle(L.s("product_marks"))
            Text(L.s("product_marks_hint")).font(AppFont.bodyMedium).foregroundStyle(AppColors.inkMuted)
            HStack(spacing: 10) {
                ForEach(Self.marks, id: \.0) { m, label, emoji in
                    // Повторный тап по той же отметке снимает её.
                    ChoiceTile(label: L.s(label), selected: mark == m, emoji: emoji) { try? app.diary.setMark(productId, mark == m ? nil : m) }
                }
            }
            .fixedSize(horizontal: false, vertical: true)

            SectionTitle(text: L.s("product_tries")) {
                Text(L.s("series_of", progress.tries, FeedingRules.seriesTarget)).font(AppFont.titleSmall).foregroundStyle(AppColors.inkMuted)
            }
            if own.isEmpty {
                Text(L.s("product_no_tries")).font(AppFont.bodyLarge).foregroundStyle(AppColors.inkMuted)
            } else {
                ForEach(own) { entry in TryRow(entry: entry) { nav.open(.entry(entryId: entry.id, productId: nil)) } }
            }
            if canDelete(catalog) {
                AppButton(L.s("product_delete_custom"), kind: .danger) { confirmDelete = true }.padding(.top, 12)
            }
        }
    }
}

private struct InfoCard: View {
    let title: String
    let text: String
    var body: some View {
        AppCard(spacing: 8) {
            FieldLabel(title, inset: 0)
            Text(text).font(AppFont.bodyLarge).foregroundStyle(AppColors.ink).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Одна проба: дата и время, количество, реакция эмодзи. Тап — редактирование.
private struct TryRow: View {
    let entry: DiaryEntry
    let onTap: () -> Void
    var body: some View {
        let meta = [entry.time?.description, entry.amount.map(Labels.label)].compactMap { $0 }
        AppCard(padding: EdgeInsets(top: 16, leading: 20, bottom: 16, trailing: 20), onTap: onTap) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Labels.dayTitle(entry.date, withYear: false)).font(AppFont.titleMedium).foregroundStyle(AppColors.ink)
                    if !meta.isEmpty { Text(meta.joined(separator: " · ")).font(AppFont.bodyMedium).foregroundStyle(AppColors.inkMuted) }
                }
                Spacer()
                Text(Labels.emoji(entry.reaction)).font(.system(size: 28))
            }
        }
    }
}
