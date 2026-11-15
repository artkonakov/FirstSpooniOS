import SwiftUI
import FirstSpoonCore

struct TodayItem: Identifiable { let id: String; let productId: String; let name: String; let reaction: Reaction }
struct ProgressItem: Identifiable { var id: String { productId }; let productId: String; let name: String; let tries: Int; let status: ProductStatus }

/// Состояние главной — чистая функция данных дневника и каталога (как `HomeViewModel.buildState`).
struct HomeState {
    var introducedCount = 0
    var today: [TodayItem] = []
    var inProgress: [ProgressItem] = []
    var attention: [ProgressItem] = []
    var isEmpty: Bool { today.isEmpty && inProgress.isEmpty && attention.isEmpty && introducedCount == 0 }

    @MainActor init(diary: DiaryRepository, catalog: Catalog, date: LocalDate = .today()) {
        func name(_ id: String) -> String { catalog.productsById[id]?.name ?? id }
        // Порядок как у Android (LinkedHashMap): по первому появлению в пробах (свежие сверху), затем отметки.
        let map = FeedingRules.progressByProduct(diary.entries, marks: diary.marks)
        var order: [String] = []
        var seen = Set<String>()
        for id in diary.entries.map(\.productId) + diary.marks.keys.sorted() where seen.insert(id).inserted { order.append(id) }
        let progress = order.compactMap { map[$0] }
        introducedCount = progress.filter { $0.status == .introduced }.count
        today = diary.entries.filter { $0.date == date }.map { TodayItem(id: $0.id, productId: $0.productId, name: name($0.productId), reaction: $0.reaction) }
        inProgress = progress.filter { $0.status == .inProgress }
            .map { ProgressItem(productId: $0.productId, name: name($0.productId), tries: $0.tries, status: $0.status) }
        attention = progress.filter { $0.status.needsAttention }
            .map { ProgressItem(productId: $0.productId, name: name($0.productId), tries: $0.tries, status: $0.status) }
    }
}

struct HomeView: View {
    @Environment(AppContainer.self) private var app
    @Environment(Navigator.self) private var nav

    var body: some View {
        let state = HomeState(diary: app.diary, catalog: app.catalog.catalog)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                if let child = app.diary.activeChild {
                    Text(Labels.ageText(child)).font(AppFont.bodyLarge).foregroundStyle(AppColors.inkMuted)
                }
                if let rec = app.recommendations.result?.recommendation {
                    RecommendationCard(rec: rec, catalog: app.catalog.catalog,
                                       onOpenProduct: { nav.open(.product($0)) },
                                       onRecord: { Analytics.track(.recommendationRecord); nav.open(.entry(entryId: nil, productId: $0)) },
                                       onOther: { app.recommendations.skip($0) })
                }
                ProgressCard(introduced: state.introducedCount, goal: FeedingRules.introductionGoal)
                if state.isEmpty {
                    EmptyState(emoji: "🥄", title: L.s("home_empty_title"), text: L.s("home_empty"))
                }
                if !state.attention.isEmpty {
                    SectionTitle(L.s("home_attention"))
                    ForEach(state.attention) { item in
                        ProductCard(productId: item.productId, name: item.name, onTap: { nav.open(.product(item.productId)) }) {
                            StatusBadge(status: item.status, tries: item.tries)
                        }
                    }
                }
                if !state.inProgress.isEmpty {
                    SectionTitle(L.s("home_in_progress"))
                    ForEach(state.inProgress) { item in
                        ProductCard(productId: item.productId, name: item.name, onTap: { nav.open(.product(item.productId)) },
                                    supporting: { StatusBadge(status: item.status, tries: item.tries) },
                                    trailing: { Chevron() },
                                    footer: {
                                        AppButton(L.s("home_record_try", item.tries + 1), kind: .soft, size: .medium, icon: "plus") {
                                            try? app.diary.addEntry(productId: item.productId)
                                        }
                                    })
                    }
                }
                if !state.today.isEmpty {
                    SectionTitle(L.s("home_today"))
                    ForEach(state.today) { item in
                        ProductCard(productId: item.productId, name: item.name, onTap: { nav.open(.entry(entryId: item.id, productId: nil)) },
                                    supporting: { EmptyView() }, trailing: { Chevron() },
                                    footer: {
                                        HStack(spacing: 10) {
                                            reactionChip(item, .none, "reaction_none")
                                            reactionChip(item, .reaction, "reaction_yes")
                                        }
                                    })
                    }
                }
            }
            .padding(.horizontal, screenPadding)
            .padding(.bottom, 24)
        }
        .bottomAction {
            AppButton(L.s("home_new_entry"), icon: "plus") { nav.open(.entry(entryId: nil, productId: nil)) }
                .padding(.horizontal, screenPadding)
                .padding(.vertical, 12)
        }
        .appScreen()
        .navigationTitle(app.diary.activeChild?.name ?? L.s("tab_home"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { ChildMenu(onAdd: { nav.open(.child(nil)) }) }
        }
    }

    /// Повторный тап снимает отметку — снова «наблюдаем».
    private func reactionChip(_ item: TodayItem, _ value: Reaction, _ label: String) -> some View {
        AppChip(label: L.s(label), selected: item.reaction == value, expand: true) {
            try? app.diary.setReaction(item.id, item.reaction == value ? .unknown : value)
        }
    }
}

/// Выбор активного ребёнка — системное меню в навбаре: аватар активного, список детей, «Добавить ребёнка».
private struct ChildMenu: View {
    @Environment(AppContainer.self) private var app
    let onAdd: () -> Void
    var body: some View {
        Menu {
            Picker(L.s("child_switch"), selection: Binding(
                get: { app.diary.activeChild?.id ?? "" },
                set: { app.diary.selectChild($0) })) {
                ForEach(app.diary.children) { c in
                    Text("\(c.name) · \(Labels.ageText(c))").tag(c.id)
                }
            }
            Divider()
            Button(action: onAdd) { Label(L.s("child_add"), systemImage: "plus") }
        } label: {
            if let child = app.diary.activeChild { ChildAvatar(child: child, size: 34) }
        }
        .accessibilityLabel(L.s("child_switch"))
    }
}

private struct ProgressCard: View {
    let introduced: Int
    let goal: Int
    var body: some View {
        AppCard {
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text("\(introduced)").font(AppFont.displaySmall).foregroundStyle(AppColors.primary)
                Text(L.s("home_progress_of", goal)).font(AppFont.titleLarge).foregroundStyle(AppColors.inkMuted)
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
    }
}

