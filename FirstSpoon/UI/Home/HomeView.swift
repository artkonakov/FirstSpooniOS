import SwiftUI
import FirstSpoonCore

/// Проба сегодня. `status`/`tries` — состояние продукта сейчас (бейдж); `nextTry` — «Завтра — N-я проба»,
/// только для активной серии без реакции (одна серия за раз — обещать можно только её).
struct TodayItem: Identifiable {
    let id: String
    let productId: String
    let name: String
    let reaction: Reaction
    var time: LocalTime?
    var status: ProductStatus?
    var tries = 0
    var nextTry: Int?
}
struct ProgressItem: Identifiable { var id: String { productId }; let productId: String; let name: String; let tries: Int; let status: ProductStatus }

/// Состояние главной — чистая функция данных дневника, каталога и рекомендации (порт Android `HomeViewModel`).
/// Один продукт — одна карточка (Android `docs/product-rules.md` «Главный экран»): дали сегодня → только в «Сегодня»;
/// предложен в рекомендации → только там. Одна серия за раз: активная — «Знакомимся сейчас» (если её не видно выше),
/// остальные начатые — «Ждут очереди»; во время паузы ждут все.
struct HomeState {
    var introducedCount = 0
    var today: [TodayItem] = []
    var todayRecords: [DiaryTimelineItem] = []
    var inProgress: [ProgressItem] = []
    var attention: [ProgressItem] = []
    /// Начатые, но не активные продукты — ждут очереди, без кнопки записи (одна серия за раз).
    var queued: [ProgressItem] = []
    var recommendation: Recommendation?
    var notReady: Bool { if case .notReady = recommendation { return true } else { return false } }
    var isEmpty: Bool { todayRecords.isEmpty && inProgress.isEmpty && attention.isEmpty && introducedCount == 0 }

    /// Продукт для формы «Записать пробу»: из рекомендации (новый или продолжить серию), иначе пустая форма.
    var entryProductId: String? {
        switch recommendation {
        case .tryNew(let id, _), .continueSeries(let id, _, _): return id
        default: return nil
        }
    }

    /// Пауза после реакции — до какого дня (для подписи в «Ждут очереди»).
    var pauseUntil: LocalDate? { if case .wait(let until, _, _) = recommendation { return until } else { return nil } }

    @MainActor init(diary: DiaryRepository, catalog: Catalog, result: RecommendationResult?, date: LocalDate = .today()) {
        func name(_ id: String) -> String { catalog.productsById[id]?.name ?? id }
        // Порядок как у Android (LinkedHashMap): по первому появлению в пробах (свежие сверху), затем отметки.
        let map = FeedingRules.progressByProduct(diary.entries, marks: diary.marks)
        var order: [String] = []
        var seen = Set<String>()
        for id in diary.entries.map(\.productId) + diary.marks.keys.sorted() where seen.insert(id).inserted { order.append(id) }
        let progress = order.compactMap { map[$0] }
        func item(_ p: ProductProgress) -> ProgressItem { ProgressItem(productId: p.productId, name: name(p.productId), tries: p.tries, status: p.status) }
        introducedCount = progress.filter { $0.status == .introduced }.count
        let started = progress.filter { $0.status == .inProgress }.map(item)

        let r = result?.recommendation
        recommendation = r
        let todayEntries = diary.entries.filter { $0.date == date }
        todayRecords = DiaryTimelineItem.newestFirst(entries: todayEntries, meals: diary.recipeMeals.filter { $0.date == date })
        let todayIds = Set(todayEntries.map(\.productId))
        let shownInCard = r?.productId
        let active = result?.activeSeries
        let paused = pauseUntil != nil
        attention = progress.filter { $0.status.needsAttention && !todayIds.contains($0.productId) }.map(item)
        today = todayEntries.map { e in
            let p = map[e.productId]
            var t = TodayItem(id: e.id, productId: e.productId, name: name(e.productId), reaction: e.reaction,
                              time: e.time, status: p?.status, tries: p?.tries ?? 0)
            if e.productId == active && t.status == .inProgress && t.reaction != .reaction && t.reaction != .unsure && !paused {
                t.nextTry = t.tries + 1
            }
            return t
        }
        let activeItem = active.flatMap { id in !todayIds.contains(id) && id != shownInCard ? started.first { $0.productId == id } : nil }
        let queuedItems = (result?.queued ?? []).filter { !todayIds.contains($0) && $0 != shownInCard }
            .compactMap { id in started.first { $0.productId == id } }
        if let activeItem, !paused { inProgress = [activeItem] }
        queued = (paused ? [activeItem].compactMap { $0 } : []) + queuedItems
    }
}

struct HomeView: View {
    @Environment(AppContainer.self) private var app
    @Environment(Navigator.self) private var nav

    var body: some View {
        let state = HomeState(diary: app.diary, catalog: app.catalog.catalog, result: app.recommendations.result)
        ScrollViewReader { proxy in
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                if let child = app.diary.activeChild {
                    Text(Labels.ageText(child)).font(AppFont.bodyLarge).foregroundStyle(AppColors.inkMuted)
                }
                if let rec = state.recommendation {
                    RecommendationCard(rec: rec, catalog: app.catalog.catalog,
                                       onOpenProduct: { nav.open(.product($0)) },
                                       onOther: { app.recommendations.skip($0) },
                                       onMarkReady: markReady)
                }
                if AssistantPilot.enabled {
                    ActionRow(title: L.s("assistant_entry")) {
                        nav.open(.assistant(productId: nil))
                        Analytics.track(.assistantOpened(source: .home))
                    }
                }
                ProgressCard(introduced: state.introducedCount, goal: FeedingRules.introductionGoal,
                             onTap: {
                                 Analytics.track(.statsOpened)
                                 nav.open(.stats)
                             }).id("progress")
                // «Пока готовимся» — пустое состояние («попробуйте продукт выше») ему противоречит.
                if state.isEmpty && !state.notReady {
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
                if !state.todayRecords.isEmpty {
                    SectionTitle(L.s("home_today"))
                    ForEach(state.todayRecords) { record in
                        switch record {
                        case .product(let entry):
                            if let item = state.today.first(where: { $0.id == entry.id }) {
                                TodayCard(item: item) { nav.open(.entry(entryId: item.id, productId: nil)) }
                            }
                        case .meal(let meal):
                            RecipeMealCard(meal: meal) {
                                nav.open(.recipeMeal(recipeId: nil, childId: nil, entryId: meal.id))
                            }
                        }
                    }
                }
                if !state.inProgress.isEmpty {
                    SectionTitle(L.s("home_in_progress"))
                    // Активная серия, которую не видно выше. Записывают общей кнопкой внизу.
                    ForEach(state.inProgress) { item in
                        ProductCard(productId: item.productId, name: item.name, onTap: { nav.open(.product(item.productId)) }) {
                            StatusBadge(status: item.status, tries: item.tries)
                        }
                    }
                }
                if !state.queued.isEmpty {
                    SectionTitle(L.s("home_queue"))
                    let note = state.pauseUntil.map { L.s("home_queue_pause", UiLocale.dayMonth($0).replacingOccurrences(of: " ", with: "\u{00A0}")) }
                        ?? L.s("home_queue_after")
                    ForEach(state.queued) { item in
                        ProductCard(productId: item.productId, name: item.name, onTap: { nav.open(.product(item.productId)) },
                                    supporting: { StatusBadge(status: item.status, tries: item.tries) },
                                    footer: { Text(note).font(AppFont.bodyMedium).foregroundStyle(AppColors.inkMuted) })
                    }
                }
            }
            .padding(.horizontal, screenPadding)
            .padding(.bottom, 24)
        }
        #if DEBUG
        .task {
            // Скриншоты: `-demo_screen home_progress` — главная, прокрученная к прогрессу и «Требуют внимания».
            if DemoScreen.current == "home_progress" {
                try? await Task.sleep(for: .milliseconds(400))
                proxy.scrollTo("progress", anchor: .top)
            }
        }
        #endif
        }
        .bottomAction {
            // Общая кнопка записи: форма открывается с продуктом из рекомендации (его можно сменить).
            AppButton(L.s("home_new_entry"), icon: "ic_plus") {
                let pid = state.entryProductId
                if pid != nil { Analytics.track(.recommendationRecord) }
                nav.open(.entry(entryId: nil, productId: pid))
            }
                .padding(.horizontal, screenPadding)
                .padding(.vertical, 12)
        }
        .appScreen()
        .navigationTitle(app.diary.activeChild?.name ?? L.s("tab_home"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { ChildMenu(onAdd: { nav.open(.child(nil)) }) }
        }
    }
}

/// Проба сегодня: время, бейдж, «Как прошло?», реакция; «Завтра — N-я проба» для активной серии.
private struct TodayCard: View {
    @Environment(AppContainer.self) private var app
    let item: TodayItem
    let onTap: () -> Void
    var body: some View {
        ProductCard(productId: item.productId, name: item.name, onTap: onTap,
                    supporting: {
                        VStack(alignment: .leading, spacing: 6) {
                            if let t = item.time { Text(UiLocale.time(t)).font(AppFont.bodyMedium).foregroundStyle(AppColors.inkMuted) }
                            if let s = item.status, s != .notTried { StatusBadge(status: s, tries: item.tries) }
                        }
                    },
                    footer: {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(L.s("home_today_question")).font(AppFont.bodyMedium).foregroundStyle(AppColors.inkMuted)
                            HStack(spacing: 10) {
                                chip(.none, "reaction_none")
                                chip(.reaction, "reaction_yes")
                            }
                            if let n = item.nextTry {
                                Text(L.s("home_today_next", n)).font(AppFont.bodyMedium).foregroundStyle(AppColors.inkMuted)
                            }
                        }
                    })
    }

    /// Повторный тап снимает отметку — снова «наблюдаем».
    private func chip(_ value: Reaction, _ label: String) -> some View {
        AppChip(label: L.s(label), selected: item.reaction == value, expand: true) {
            try? app.diary.setReaction(item.id, item.reaction == value ? .unknown : value)
        }
    }
}

/// Выбор активного ребёнка — системное меню в навбаре: аватар активного, список детей, «Добавить ребёнка».
struct ChildMenu: View {
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
            Button(action: onAdd) { Label(L.s("child_add"), image: "ic_plus") }
        } label: {
            if let child = app.diary.activeChild { ChildAvatar(child: child, size: 34) }
        }
        .accessibilityLabel(L.s("child_switch"))
    }
}

extension HomeView {
    /// «Малыш уже держит голову и сидит»: отмечаем оба навыка — движок сразу предложит первые продукты.
    func markReady() {
        guard let c = app.diary.activeChild else { return }
        Analytics.track(.readyMarked)
        let yes = ProfileQuestion.Answer.yes
        let profile = c.profile.with(.headControl, answer: yes).with(.sits, answer: yes)
        let readiness = FeedingReadiness.evaluate(birthDate: c.birthDate, profile: profile, knownFoods: [], today: .today())
        _ = try? app.diary.saveChild(id: c.id, name: c.name, birthDate: c.birthDate, sex: c.sex,
                                     profile: profile.withReadiness(readiness.rawValue))
    }
}
