import SwiftUI
import FirstSpoonCore

/// Свой продукт: фото, название, категория, аллергены. Если такой есть в каталоге — подсказка.
/// Новый (`editId` = nil): `onCreated` — режим выбора для пробы (новый продукт сразу выбирается), иначе открываем его страницу.
/// Редактирование (`editId`): те же поля, «Сохранить» возвращает на страницу продукта.
struct CustomProductView: View {
    @Environment(AppContainer.self) private var app
    @Environment(Navigator.self) private var nav
    let editId: String?
    @State private var name: String
    @State private var category: String?
    @State private var allergens: Set<String> = []
    @State private var photo: PhotoDraft?
    var onCreated: ((String) -> Void)?

    init(initialName: String, onCreated: ((String) -> Void)? = nil) {
        editId = nil
        _name = State(initialValue: initialName.trimmingCharacters(in: .whitespaces))
        self.onCreated = onCreated
    }

    init(editId: String) {
        self.editId = editId
        _name = State(initialValue: "")
    }

    var body: some View {
        let catalog = app.catalog.catalog
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let exists = catalog.products.contains { $0.id != editId && $0.name.lowercased() == trimmed.lowercased() }
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if editId == nil {
                    Text(L.s("custom_hint")).font(AppFont.bodyLarge).foregroundStyle(AppColors.inkMuted)
                }
                if let photo {
                    PhotoPickerField(draft: photo, placeholder: AnyView(placeholder(trimmed))).padding(.top, 8)
                }
                FieldLabel(L.s("custom_name")).padding(.top, 8)
                AppTextField(text: $name, placeholder: L.s("custom_name_hint"), error: exists ? L.s("custom_exists") : nil)
                FieldLabel(L.s("custom_category")).padding(.top, 8)
                FlowLayout(spacing: 8) {
                    ForEach(app.catalog.base.categories) { c in
                        AppChip(label: c.name, selected: category == c.id) { category = category == c.id ? nil : c.id }
                    }
                }
                FieldLabel(L.s("custom_allergens")).padding(.top, 8)
                FlowLayout(spacing: 8) {
                    ForEach(catalog.allergens) { a in
                        AppChip(label: a.name, selected: allergens.contains(a.id)) {
                            if allergens.contains(a.id) { allergens.remove(a.id) } else { allergens.insert(a.id) }
                        }
                    }
                }
            }
            .padding(.horizontal, screenPadding)
            .padding(.bottom, 24)
        }
        .bottomAction {
            AppButton(L.s(editId == nil ? "custom_save" : "save"), enabled: !trimmed.isEmpty && !exists) { save(trimmed) }
                .padding(.horizontal, screenPadding)
                .padding(.vertical, 12)
        }
        .appScreen()
        .navigationTitle(L.s("custom_title"))
        .onAppear {
            guard photo == nil else { return }
            let existing = editId.flatMap { app.catalog.catalog.productsById[$0] }
            if let p = existing {
                name = p.name
                category = p.categoryId == CatalogRepository.customCategoryId ? nil : p.categoryId
                allergens = Set(p.allergenIds)
            }
            photo = PhotoDraft(store: app.photos, original: existing?.photo)
        }
        // Ушли без сохранения — выбранные здесь снимки не нужны.
        .onDisappear { photo?.discard() }
    }

    private func placeholder(_ name: String) -> some View {
        ZStack {
            AppColors.surfaceSoft
            Text(name.prefix(1).uppercased()).font(AppFont.headlineMedium).foregroundStyle(AppColors.inkMuted)
        }
    }

    private func save(_ trimmed: String) {
        let newPhoto = photo?.commit()
        if let editId {
            try? app.catalog.updateCustomProduct(editId, name: trimmed, categoryId: category,
                                                 allergenIds: allergens.sorted(), photo: newPhoto)
            nav.back()
            return
        }
        guard let id = try? app.catalog.addCustomProduct(name: trimmed, categoryId: category,
                                                         allergenIds: allergens.sorted(), photo: newPhoto) else { return }
        if let onCreated { onCreated(id) } else { nav.back(); nav.open(.product(id)) }
    }
}
