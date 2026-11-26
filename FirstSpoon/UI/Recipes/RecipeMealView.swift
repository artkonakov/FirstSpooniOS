import SwiftUI
import FirstSpoonCore

@MainActor @Observable
private final class RecipeMealEditor {
    var record: RecipeMeal
    let photos: EntryPhotosDraft
    let editing: Bool
    var failed = false

    init(record: RecipeMeal, store: PhotoStore, editing: Bool) {
        self.record = record
        self.editing = editing
        photos = EntryPhotosDraft(store: store, original: record.photos)
    }

    var canSave: Bool { !record.eatenIngredients.isEmpty && !photos.processing }

    func save(to diary: DiaryRepository) -> Bool {
        guard canSave else { return false }
        record.photos = photos.photos
        do {
            try diary.saveRecipeMeal(record, editing: editing)
            _ = photos.commit()
            return true
        } catch {
            failed = true
            return false
        }
    }
}

struct RecipeMealView: View {
    @Environment(AppContainer.self) private var app
    @Environment(Navigator.self) private var nav
    let recipeId: String?
    let childId: String?
    let entryId: String?
    var onNewMealSaved: (() -> Void)?
    @State private var model: RecipeMealEditor?
    @State private var chooseDate = false
    @State private var confirmDelete = false

    var body: some View {
        ZStack {
            if let model { form(model) }
            else { Text(L.s("recipe_meal_unavailable")).foregroundStyle(AppColors.inkMuted) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .bottomAction {
            if let model {
                AppButton(L.s("entry_save"), enabled: model.canSave) {
                    if model.save(to: app.diary) {
                        nav.back()
                        if !model.editing { onNewMealSaved?() }
                    }
                }
                .padding(.horizontal, screenPadding).padding(.vertical, 12)
            }
        }
        .appScreen()
        .navigationTitle(L.s(entryId == nil ? "recipe_meal_log" : "recipe_meal_edit"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if model == nil, let record = initialRecord() {
                model = RecipeMealEditor(record: record, store: app.photos, editing: entryId != nil)
            }
        }
        .onDisappear { model?.photos.discard() }
        .sheet(isPresented: $chooseDate) {
            if let model {
                let time = Binding(get: { model.record.time ?? LocalDateTime.now().time }, set: { model.record.time = $0 })
                DateTimeSheet(date: Bindable(model).record.date, time: time) { chooseDate = false }
            }
        }
        .alert(L.s("recipe_meal_delete_confirm"), isPresented: $confirmDelete) {
            Button(L.s("recipe_meal_delete"), role: .destructive) {
                guard let model else { return }
                do {
                    try app.diary.deleteRecipeMeal(model.record)
                    nav.back()
                } catch {
                    model.failed = true
                }
            }
            Button(L.s("cancel"), role: .cancel) {}
        }
    }

    private func initialRecord() -> RecipeMeal? {
        if let entryId { return app.diary.recipeMeals.first { $0.id == entryId } }
        guard let childId, childId == app.diary.activeChild?.id,
              let recipe = BundledRecipes.selection(for: app)?.matches.first(where: { $0.id == recipeId })?.recipe else {
            return nil
        }
        let catalog = app.catalog.catalog.productsById
        let ingredients = recipe.ingredients.compactMap { ingredient in
            catalog[ingredient.productId].map { RecipeMeal.Ingredient(productId: $0.id, name: $0.name) }
        }
        guard ingredients.count == recipe.ingredients.count else { return nil }
        return RecipeMeal(id: newId(), childId: childId, recipeId: recipe.id,
                          snapshot: .init(title: recipe.title, ingredients: ingredients),
                          date: .today(), time: LocalDateTime.now().time)
    }

    private func form(_ model: RecipeMealEditor) -> some View {
        @Bindable var model = model
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(model.record.snapshot.title.value()).font(AppFont.headlineMedium)
                FieldLabel(L.s("recipe_meal_eaten"))
                AppCard(spacing: 4) {
                    ForEach(model.record.snapshot.ingredients.indices, id: \.self) { index in
                        let ingredient = model.record.snapshot.ingredients[index]
                        Button {
                            model.record.snapshot.ingredients[index].eaten.toggle()
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: ingredient.eaten ? "checkmark.square.fill" : "square")
                                    .foregroundStyle(ingredient.eaten ? AppColors.primary : AppColors.inkMuted)
                                Text(app.catalog.catalog.productsById[ingredient.productId]?.name ?? ingredient.name)
                                    .foregroundStyle(AppColors.ink)
                                Spacer()
                            }
                            .font(AppFont.bodyLarge).frame(minHeight: 44).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(ingredient.eaten ? .isSelected : [])
                    }
                }
                FieldLabel(L.s("recipe_meal_reaction"))
                TileGrid(items: Labels.reactionChoices) { reaction in
                    ChoiceTile(label: Labels.label(reaction), selected: model.record.reaction == reaction, emoji: Labels.emoji(reaction)) {
                        model.record.reaction = model.record.reaction == reaction ? .unknown : reaction
                    }
                }
                FieldLabel(L.s("entry_datetime"))
                let dateLabel = Labels.dayTitle(model.record.date)
                let timeLabel = model.record.time.map { ", " + UiLocale.time($0) } ?? ""
                ActionRow(title: dateLabel + timeLabel, icon: "ic_tab_diary") { chooseDate = true }
                FieldLabel(L.s("entry_meal"))
                TileGrid(items: Meal.allCases) { meal in
                    ChoiceTile(label: Labels.label(meal), selected: model.record.meal == meal, emoji: Labels.emoji(meal)) {
                        model.record.meal = model.record.meal == meal ? nil : meal
                    }
                }
                FieldLabel(L.s("entry_note"))
                AppTextField(text: Binding(
                    get: { model.record.note ?? "" },
                    set: { model.record.note = String($0.prefix(500)) }
                ), placeholder: L.s("recipe_meal_note_hint"), multiline: true, minimumLines: 2)
                FieldLabel(L.s("entry_photos"))
                EntryPhotosSection(draft: model.photos, showsHint: false)
                if model.failed {
                    Text(L.s("recipe_meal_save_error")).font(AppFont.bodyMedium).foregroundStyle(AppColors.alert)
                }
                if model.editing {
                    AppButton(L.s("recipe_meal_delete"), kind: .danger, enabled: !model.photos.processing) { confirmDelete = true }
                }
            }
            .padding(.horizontal, screenPadding).padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
    }
}

struct RecipeMealCard: View {
    @Environment(AppContainer.self) private var app
    let meal: RecipeMeal
    let onTap: () -> Void

    var body: some View {
        let metadata = [meal.time.map(UiLocale.time), meal.meal.map(Labels.label), meal.amount.map(Labels.label)]
            .compactMap { $0 }.joined(separator: " · ")
        let eaten = meal.eatenIngredients.map { app.catalog.catalog.productsById[$0.productId]?.name ?? $0.name }
        AppCard(padding: EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16), onTap: onTap) {
            HStack(spacing: 12) {
                RecipeCover(recipeId: meal.recipeId, height: 56).frame(width: 56)
                VStack(alignment: .leading, spacing: 4) {
                    Text(meal.snapshot.title.value()).font(AppFont.titleMedium).foregroundStyle(AppColors.ink)
                    if !metadata.isEmpty {
                        Text(metadata).font(AppFont.bodyMedium).foregroundStyle(AppColors.inkMuted)
                    }
                    Text(eaten.joined(separator: ", ")).font(AppFont.bodyMedium).foregroundStyle(AppColors.inkMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(spacing: 4) {
                    Text(Labels.emoji(meal.reaction)).font(.system(size: 30))
                    EntryPhotoBadge(store: app.photos, photos: meal.photos)
                }
            }
        }
    }
}
