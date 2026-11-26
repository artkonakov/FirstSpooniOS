import SwiftUI
import FirstSpoonCore

enum BundledRecipes {
    static let catalog: RecipeCatalog? = {
        guard let url = Bundle.main.url(forResource: "recipes", withExtension: "json") else { return nil }
        return try? JSONDecoder().decode(RecipeCatalog.self, from: Data(contentsOf: url))
    }()

    @MainActor static func selection(for app: AppContainer) -> RecipeSelection? {
        guard let catalog, let child = app.diary.activeChild else { return nil }
        let today = LocalDate.today()
        let context = RecommendationContext(today: today, child: child, products: app.catalog.catalog.products,
                                            entries: app.diary.entries, marks: app.diary.marks, favorites: app.diary.favorites)
        let reactions = Set(app.diary.recipeMeals.filter { $0.date <= today && $0.hasReaction }.map(\.recipeId))
        return RecipeSelection(recipes: catalog.recipes, context: context, config: Strategies.config(), recipesWithReaction: reactions)
    }
}

extension RecipeSelection.Notice {
    var message: String {
        switch self {
        case .notReady: return "recipes_not_ready"
        case .pause: return "recipes_paused"
        case .unknownAllergy: return "recipes_unknown_allergy"
        }
    }
}

struct RecipeCover: View {
    let recipeId: String
    let height: CGFloat
    var radius: CGFloat = 18

    var body: some View {
        let name = "recipe_" + recipeId.replacingOccurrences(of: "-", with: "_")
        Color.clear
            .frame(height: height)
            .overlay { Image(name).resizable().scaledToFill().accessibilityHidden(true) }
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

struct RecipesView: View {
    @Environment(AppContainer.self) private var app
    @Environment(Navigator.self) private var nav
    @Environment(\.dynamicTypeSize) private var typeSize
    let onOpenProducts: () -> Void
    let onOpenHome: () -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                if let selection = BundledRecipes.selection(for: app) {
                    let recommended = selection.matches.filter(\.forChild)
                    let reference = selection.matches.filter { !$0.forChild }
                    if !recommended.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            SectionTitle(L.s("recipes_today"))
                            Text(L.s("recipes_one_meal")).font(AppFont.bodyMedium).foregroundStyle(AppColors.inkMuted)
                        }
                        grid(recommended)
                    } else if let notice = selection.notice {
                        noticeCard(title: "recipes_wait_title", message: notice.message,
                                   button: "recipes_open_home", action: onOpenHome)
                    } else {
                        noticeCard(title: "recipes_few_known", message: "recipes_few_help",
                                   button: "recipes_open_products", action: onOpenProducts)
                    }
                    if !reference.isEmpty {
                        SectionTitle(L.s("recipes_for_reference"))
                        grid(reference)
                    } else if recommended.isEmpty {
                        Text(L.s("recipes_no_available")).font(AppFont.bodyMedium).foregroundStyle(AppColors.inkMuted)
                    }
                } else {
                    Text(L.s("recipes_catalog_error")).font(AppFont.bodyMedium).foregroundStyle(AppColors.inkMuted)
                }
            }
            .padding(.horizontal, screenPadding)
            .padding(.bottom, 24)
        }
        .appScreen()
        .navigationTitle(L.s("tab_recipes"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { ChildMenu(onAdd: { nav.open(.child(nil)) }) }
        }
    }

    private func grid(_ matches: [RecipeSelection.Match]) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top),
                                 count: typeSize.isAccessibilitySize ? 1 : 2), spacing: 12) {
            ForEach(matches) { match in
                AppCard(padding: EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12),
                        spacing: 8, onTap: { nav.open(.recipe(match.id)) }) {
                    RecipeCover(recipeId: match.id, height: 104, radius: 14)
                    Text(match.recipe.title.value()).font(AppFont.titleMedium).foregroundStyle(AppColors.ink)
                        .lineLimit(typeSize.isAccessibilitySize ? nil : 3)
                    Text(L.s("recipes_minutes", match.recipe.minutes)).font(AppFont.bodyMedium).foregroundStyle(AppColors.inkMuted)
                    let caption = match.forChild ? (match.favoriteCount > 0 ? "recipes_favorite" : "recipes_known") : "recipes_reference"
                    Text(L.s(caption)).font(AppFont.labelMedium)
                        .foregroundStyle(match.forChild ? AppColors.primary : AppColors.inkMuted)
                }
                .accessibilityIdentifier("recipe-\(match.id)")
            }
        }
    }

    private func noticeCard(title: String, message: String, button: String, action: @escaping () -> Void) -> some View {
        AppCard(spacing: 10) {
            Text(L.s(title)).font(AppFont.titleMedium)
            Text(L.s(message)).font(AppFont.bodyMedium).foregroundStyle(AppColors.inkMuted)
            AppButton(L.s(button), kind: .soft, size: .medium, action: action)
        }
    }
}

struct RecipeDetailView: View {
    @Environment(AppContainer.self) private var app
    @Environment(Navigator.self) private var nav
    @State private var texture: Recipe.Texture?
    let id: String

    var body: some View {
        let selection = BundledRecipes.selection(for: app)
        let match = selection?.matches.first { $0.id == id }
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let match {
                    details(match, notice: selection?.notice)
                } else {
                    Text(L.s("recipes_unavailable")).font(AppFont.bodyMedium).foregroundStyle(AppColors.inkMuted)
                }
            }
            .padding(.horizontal, screenPadding)
            .padding(.bottom, 24)
        }
        .bottomAction {
            if match != nil, let child = app.diary.activeChild {
                AppButton(L.s("recipe_meal_log")) { nav.open(.recipeMeal(recipeId: id, childId: child.id, entryId: nil)) }
                    .padding(.horizontal, screenPadding).padding(.vertical, 12)
            }
        }
        .appScreen()
        .navigationTitle(L.s("tab_recipes"))
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: app.diary.activeChild?.id) { _, _ in texture = nil }
    }

    private func details(_ match: RecipeSelection.Match, notice: RecipeSelection.Notice?) -> some View {
        let recipe = match.recipe
        let catalog = app.catalog.catalog.productsById
        return Group {
            VStack(alignment: .leading, spacing: 6) {
                SectionTitle(recipe.title.value())
                Text(L.s("recipes_minutes", recipe.minutes)).foregroundStyle(AppColors.inkMuted)
                Text(L.s("recipes_portions", recipe.portions)).foregroundStyle(AppColors.inkMuted)
            }
            .font(AppFont.bodyMedium)
            RecipeCover(recipeId: id, height: 200, radius: AppRadius.large)
            section("recipes_ingredients") {
                ForEach(recipe.ingredients) { ingredient in
                    HStack {
                        Text(catalog[ingredient.productId]?.name ?? ingredient.productId)
                        Spacer()
                        Text(L.s("recipes_grams", ingredient.grams)).foregroundStyle(AppColors.inkMuted)
                    }
                }
            }
            section("recipes_steps") {
                ForEach(Array(recipe.steps.enumerated()), id: \.offset) { index, step in
                    Text("\(index + 1). \(step.value())")
                }
                if match.forChild { Text(L.s("recipes_split")).foregroundStyle(AppColors.primary) }
            }
            if match.forChild {
                section("recipes_serving") {
                    Text(L.s("recipes_texture_hint")).foregroundStyle(AppColors.inkMuted)
                    HStack {
                        ForEach(recipe.textures, id: \.self) { option in
                            AppButton(L.s(option == .puree ? "recipes_texture_puree" : "recipes_texture_mash"),
                                      kind: texture == option ? .primary : .soft, size: .medium) { texture = option }
                        }
                    }
                    if let texture { Text(L.s(texture == .puree ? "recipes_serve_puree" : "recipes_serve_mash")) }
                }
            } else {
                section("recipes_reference") {
                    let message = match.hasMealReaction ? "recipe_meal_previous_reaction" : notice?.message ?? "recipes_not_match"
                    Text(L.s(message)).foregroundStyle(AppColors.inkMuted)
                }
            }
            if app.diary.activeChild?.profile.knownAllergens.isEmpty == false || app.diary.marks.values.contains(.allergy) {
                Text(L.s("recipes_check_labels")).font(AppFont.bodyMedium).foregroundStyle(AppColors.inkMuted)
            }
        }
    }

    private func section<C: View>(_ key: String, @ViewBuilder content: @escaping () -> C) -> some View {
        AppCard(spacing: 10) {
            Text(L.s(key)).font(AppFont.titleMedium)
            content().font(AppFont.bodyLarge)
        }
    }
}
