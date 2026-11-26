import SwiftUI
import FirstSpoonCore

/// Экраны, которые открываются поверх вкладки (push в стек этой вкладки).
enum Route: Hashable {
    case product(String)
    case recipe(String)
    case recipeMeal(recipeId: String?, childId: String?, entryId: String?)
    /// Новая проба (`entryId` = nil, можно с продуктом) или редактирование.
    case entry(entryId: String?, productId: String?)
    case customProduct(query: String)
    case editCustomProduct(String)
    case child(String?)
    case settings
    case devices
    case stats
    case assistant(productId: String?)
    case linkEmail
    case authCode(AuthViewModel)
}

/// Стек навигации одной вкладки.
@MainActor @Observable
final class Navigator {
    var path: [Route] = []
    func open(_ r: Route) { path.append(r) }
    func back() { if !path.isEmpty { path.removeLast() } }
}

private enum Tab: Hashable { case home, diary, products, recipes, profile }

/// Основной граф — стандартный iOS: системный `TabView`, у каждой вкладки свой `NavigationStack` (`TabStack`).
/// Заголовок, кнопки навбара и поиск задаёт сам экран; таб-бар виден и на вложенных экранах.
/// Переключение вкладок сохраняет стек каждой (решение пользователя 2026-11-19, «вариант 1»).
struct MainFlow: View {
    @Environment(AppContainer.self) private var app
    @State private var tab = MainFlow.initialTab
    @State private var catalogState = CatalogViewState()

    var body: some View {
        TabView(selection: $tab) {
            TabStack(initialPath: MainFlow.initialHomePath) { HomeView() }
                .tabItem { Label(L.s("tab_home"), image: "ic_tab_home") }
                .tag(Tab.home)
            TabStack { DiaryView() }
                .tabItem { Label(L.s("tab_diary"), image: "ic_tab_diary") }
                .tag(Tab.diary)
            TabStack(initialPath: MainFlow.initialProductsPath) { ProductsTab(state: catalogState) }
                .tabItem { Label(L.s("tab_products"), image: "ic_tab_products") }
                .tag(Tab.products)
            TabStack(initialPath: MainFlow.initialRecipesPath, onRecipeLogged: { tab = .diary }) {
                RecipesView(onOpenProducts: { tab = .products }, onOpenHome: { tab = .home })
            }
            .tabItem { Label(L.s("tab_recipes"), image: "ic_document") }
            .tag(Tab.recipes)
            TabStack { ProfileView() }
                .tabItem { Label(L.s("tab_profile"), image: "ic_tab_profile") }
                .tag(Tab.profile)
        }
        .tint(AppColors.primary)
        .onAppear {
            app.reminders.askPermissionOnce()
            app.reminders.refresh()
            Task { await app.auth.refreshProfile() }
        }
    }
}

/// Стек одной вкладки: свой `Navigator` в окружении, все маршруты `Route`.
struct TabStack<Root: View>: View {
    @State private var nav: Navigator
    private let onRecipeLogged: (() -> Void)?
    @ViewBuilder let root: () -> Root

    init(initialPath: [Route] = [], onRecipeLogged: (() -> Void)? = nil, @ViewBuilder root: @escaping () -> Root) {
        let nav = Navigator()
        nav.path = initialPath
        _nav = State(initialValue: nav)
        self.root = root
        self.onRecipeLogged = onRecipeLogged
    }

    var body: some View {
        NavigationStack(path: $nav.path) { root().routes(onRecipeLogged: onRecipeLogged) }
            .environment(nav)
    }
}

extension View {
    /// Все экраны, которые открываются в стеке вкладки (таб-бар остаётся; нижняя кнопка — над ним).
    func routes(onRecipeLogged: (() -> Void)? = nil) -> some View {
        navigationDestination(for: Route.self) { route in destination(route, onRecipeLogged: onRecipeLogged) }
    }

    @ViewBuilder
    private func destination(_ route: Route, onRecipeLogged: (() -> Void)?) -> some View {
            switch route {
            case .product(let id): ProductView(productId: id)
            case .recipe(let id): RecipeDetailView(id: id)
            case .recipeMeal(let recipeId, let childId, let entryId):
                RecipeMealView(recipeId: recipeId, childId: childId, entryId: entryId, onNewMealSaved: onRecipeLogged)
            case .entry(let entryId, let productId): EntryView(entryId: entryId, productId: productId)
            case .customProduct(let query): CustomProductView(initialName: query)
            case .editCustomProduct(let id): CustomProductView(editId: id)
            case .child(let id): ChildEditView(childId: id)
            case .settings: SettingsView()
            case .devices: DevicesView()
            case .stats: StatsView()
            case .assistant(let id): AssistantView(productId: id)
            case .linkEmail: LinkEmailFlow()
            case .authCode(let m): AuthCodeView(model: m)
            }
    }
}

private struct ProductsTab: View {
    @Environment(Navigator.self) private var nav
    let state: CatalogViewState
    var body: some View {
        CatalogView(state: state, onPick: { nav.open(.product($0)) })
    }
}

extension MainFlow {
    /// Только debug: экран для скриншотов магазина (`-demo_screen`), иначе — Главная.
    fileprivate static var initialTab: Tab {
        #if DEBUG
        switch DemoScreen.current {
        case "diary": return .diary
        case let s? where s == "recipes" || s.hasPrefix("recipe:"): return .recipes
        case "catalog", "entry": return .products
        case let s? where s.hasPrefix("product:") || s.hasPrefix("assistant-product:"): return .products
        default: return .home
        }
        #else
        return .home
        #endif
    }

    fileprivate static var initialHomePath: [Route] {
        #if DEBUG
        // Скриншоты и проверка экрана статистики без касаний: `-demo_screen stats`.
        if DemoScreen.current == "stats" { return [.stats] }
        if DemoScreen.current == "assistant" { return [.assistant(productId: nil)] }
        if DemoScreen.current == "assistant-settings" { return [.settings] }
        #endif
        return []
    }

    fileprivate static var initialProductsPath: [Route] {
        #if DEBUG
        switch DemoScreen.current {
        case let s? where s.hasPrefix("product:"): return [.product(String(s.dropFirst("product:".count)))]
        case "entry": return [.product("broccoli"), .entry(entryId: nil, productId: "broccoli")]
        case let s? where s.hasPrefix("assistant-product:"):
            let id = String(s.dropFirst("assistant-product:".count))
            return [.product(id), .assistant(productId: id)]
        default: return []
        }
        #else
        return []
        #endif
    }

    fileprivate static var initialRecipesPath: [Route] {
        #if DEBUG
        if let screen = DemoScreen.current, screen.hasPrefix("recipe:") {
            return [.recipe(String(screen.dropFirst("recipe:".count)))]
        }
        #endif
        return []
    }
}
