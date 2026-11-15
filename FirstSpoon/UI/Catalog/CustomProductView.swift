import SwiftUI
import FirstSpoonCore

/// Свой продукт: название, категория, аллергены. Если такой есть в каталоге — подсказка.
/// `onCreated` — режим выбора для пробы (новый продукт сразу выбирается); иначе открываем его страницу.
struct CustomProductView: View {
    @Environment(AppContainer.self) private var app
    @Environment(Navigator.self) private var nav
    @State private var name: String
    @State private var category: String?
    @State private var allergens: Set<String> = []
    var onCreated: ((String) -> Void)?

    init(initialName: String, onCreated: ((String) -> Void)? = nil) {
        _name = State(initialValue: initialName.trimmingCharacters(in: .whitespaces))
        self.onCreated = onCreated
    }

    var body: some View {
        let catalog = app.catalog.catalog
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let exists = catalog.products.contains { $0.name.lowercased() == trimmed.lowercased() }
        ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(L.s("custom_hint")).font(AppFont.bodyLarge).foregroundStyle(AppColors.inkMuted)
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
            AppButton(L.s("custom_save"), enabled: !trimmed.isEmpty && !exists) {
                guard let id = try? app.catalog.addCustomProduct(name: trimmed, categoryId: category,
                                                                 allergenIds: allergens.sorted()) else { return }
                if let onCreated { onCreated(id) } else { nav.back(); nav.open(.product(id)) }
            }
            .padding(.horizontal, screenPadding)
            .padding(.vertical, 12)
        }
        .appScreen()
        .navigationTitle(L.s("custom_title"))
    }
}
