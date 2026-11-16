import SwiftUI
import FirstSpoonCore

/// Экраны, которые открываются поверх вкладки (push в стек этой вкладки).
enum Route: Hashable {
    case product(String)
    /// Новая проба (`entryId` = nil, можно с продуктом) или редактирование.
    case entry(entryId: String?, productId: String?)
    case customProduct(query: String)
    case editCustomProduct(String)
    case child(String?)
    case settings
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

private enum Tab: Hashable { case home, diary, products, profile }

/// Основной граф: системный таб-бар (`TabView`), у каждой вкладки свой `NavigationStack` с системным навбаром.
struct MainFlow: View {
    @Environment(AppContainer.self) private var app
    @State private var tab = MainFlow.initialTab
    @State private var catalogState = CatalogViewState()

    var body: some View {
        TabView(selection: $tab) {
            TabStack { HomeView() }
                .tabItem { Label(L.s("tab_home"), systemImage: "house") }
                .tag(Tab.home)
            TabStack { DiaryView() }
                .tabItem { Label(L.s("tab_diary"), systemImage: "calendar") }
                .tag(Tab.diary)
            TabStack(initialPath: MainFlow.initialProductsPath) { ProductsTab(state: catalogState) }
                .tabItem { Label(L.s("tab_products"), systemImage: "list.bullet") }
                .tag(Tab.products)
            TabStack { ProfileView() }
                .tabItem { Label(L.s("tab_profile"), systemImage: "person") }
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

/// `NavigationStack` вкладки: свой `Navigator` и общие маршруты.
struct TabStack<Root: View>: View {
    @State private var nav: Navigator
    @ViewBuilder let root: () -> Root

    init(initialPath: [Route] = [], @ViewBuilder root: @escaping () -> Root) {
        let nav = Navigator()
        nav.path = initialPath
        _nav = State(initialValue: nav)
        self.root = root
    }

    var body: some View {
        NavigationStack(path: $nav.path) {
            root().routes()
        }
        .environment(nav)
    }
}

extension View {
    /// Все экраны, которые можно открыть из вкладки.
    func routes() -> some View {
        navigationDestination(for: Route.self) { route in
            switch route {
            case .product(let id): ProductView(productId: id)
            case .entry(let entryId, let productId): EntryView(entryId: entryId, productId: productId)
            case .customProduct(let query): CustomProductView(initialName: query)
            case .editCustomProduct(let id): CustomProductView(editId: id)
            case .child(let id): ChildEditView(childId: id)
            case .settings: SettingsView()
            case .linkEmail: LinkEmailFlow()
            case .authCode(let m): AuthCodeView(model: m)
            }
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
        case "catalog", "entry": return .products
        case let s? where s.hasPrefix("product:"): return .products
        default: return .home
        }
        #else
        return .home
        #endif
    }

    fileprivate static var initialProductsPath: [Route] {
        #if DEBUG
        switch DemoScreen.current {
        case let s? where s.hasPrefix("product:"): return [.product(String(s.dropFirst("product:".count)))]
        case "entry": return [.product("broccoli"), .entry(entryId: nil, productId: "broccoli")]
        default: return []
        }
        #else
        return []
        #endif
    }
}
