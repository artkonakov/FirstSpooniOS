import SwiftUI
import FirstSpoonCore

struct StatProduct: Identifiable {
    let id: String
    let name: String
}

/// Состояние экрана статистики — чистая функция дневника и каталога (порт Android `StatsViewModel`).
struct StatsState {
    let stats: FeedingStats.Stats
    private let names: [String: String]

    @MainActor init(diary: DiaryRepository, catalog: Catalog, date: LocalDate = .today()) {
        stats = FeedingStats.build(entries: diary.entries, marks: diary.marks, today: date)
        names = Dictionary(catalog.products.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
    }

    func name(_ id: String) -> String { names[id] ?? id }

    func products(_ ids: [String]) -> [StatProduct] {
        ids.map { StatProduct(id: $0, name: name($0)) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

/// Другой взгляд на дневник: сколько продуктов в меню, какие месяцы шли пробы и на что была реакция.
struct StatsView: View {
    @Environment(AppContainer.self) private var app
    @Environment(Navigator.self) private var nav

    var body: some View {
        let state = StatsState(diary: app.diary, catalog: app.catalog.catalog)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if state.stats.isEmpty {
                    EmptyState(emoji: "🥄", title: L.s("stats_empty_title"), text: L.s("stats_empty"))
                    AppButton(L.s("home_new_entry")) { nav.open(.entry(entryId: nil, productId: nil)) }
                } else {
                    ProgressCard(introduced: state.stats.introduced.count, goal: FeedingRules.introductionGoal)
                    CalendarCard(
                        months: state.stats.months,
                        name: { state.name($0) }
                    )

                    let introduced = state.products(state.stats.introduced)
                    if !introduced.isEmpty {
                        SectionTitle(L.s("stats_introduced"))
                        PillList(introduced) { nav.open(.product($0)) }
                    }
                    let attention = state.products(state.stats.attention)
                    if !attention.isEmpty {
                        SectionTitle(L.s("home_attention"))
                        PillList(attention, background: AppColors.alertSoft, foreground: AppColors.alert) { nav.open(.product($0)) }
                    }
                    let excluded = state.products(state.stats.excluded)
                    if !excluded.isEmpty {
                        SectionTitle(L.s("stats_excluded"))
                        PillList(excluded, background: AppColors.neutralSoft, foreground: AppColors.inkMuted) { nav.open(.product($0)) }
                    }
                    Text(L.s("stats_note"))
                        .font(AppFont.bodyMedium)
                        .foregroundStyle(AppColors.inkMuted)
                        .padding(.leading, 6)
                        .padding(.top, 6)
                }
            }
            .padding(.horizontal, screenPadding)
            .padding(.bottom, 24)
        }
        .appScreen()
        .navigationTitle(L.s("stats_title"))
    }
}

private func PillList(_ items: [StatProduct], background: Color = AppColors.goodSoft,
                      foreground: Color = AppColors.good, onTap: @escaping (String) -> Void) -> some View {
    FlowLayout(spacing: 8) {
        ForEach(items) { item in
            ProductPill(productId: item.id, name: item.name, background: background, foreground: foreground) { onTap(item.id) }
        }
    }
}

/// Календарь месяцев: строка чипов для переключения + сетка выбранного месяца.
/// Месяцы новые первыми, чипы листаются горизонтально; целиком показываются все месяцы от первой пробы.
private struct CalendarCard: View {
    let months: [FeedingStats.MonthGrid]
    let name: (String) -> String
    @State private var selected: String?

    private var month: FeedingStats.MonthGrid? {
        months.first { $0.key == selected } ?? months.first
    }

    var body: some View {
        AppCard(spacing: 0) {
            Text(L.s("stats_chart_title")).font(AppFont.titleLarge)
            if months.allSatisfy({ $0.totalTries == 0 }) {
                Text(L.s("stats_chart_empty"))
                    .font(AppFont.bodyLarge)
                    .foregroundStyle(AppColors.inkMuted)
                    .padding(.vertical, 48)
            } else if let month {
                monthChips
                monthGrid(month)
            }
        }
    }

    /// Горизонтальные чипы месяцев: активный — тёмный, остальные — белые с рамкой (как `AppChip`).
    private var monthChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 8) {
                ForEach(months, id: \.key) { m in
                    AppChip(label: monthName(m), selected: m.key == month?.key) { selected = m.key }
                }
            }
            .padding(.vertical, 2)
        }
        .padding(.top, 14)
    }

    @ViewBuilder
    private func monthGrid(_ month: FeedingStats.MonthGrid) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                ForEach(Array(weekdays.enumerated()), id: \.offset) { _, day in
                    Text(day).font(AppFont.labelSmall).foregroundStyle(AppColors.inkFaint)
                        .frame(maxWidth: .infinity)
                }
            }
            let rows = stride(from: 0, to: month.cells.count, by: 7).map { start in
                Array(month.cells[start..<min(start + 7, month.cells.count)])
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 4) {
                    ForEach(row, id: \.date) { cell in dayCell(cell) }
                }
            }
        }
        .padding(.top, 12)
        HStack(spacing: 14) {
            LegendDot(color: AppColors.primary, label: L.s("stats_chart_legend_tries"))
            LegendDot(color: AppColors.alert, label: L.s("stats_chart_legend_reaction"))
            LegendDot(color: AppColors.surfaceSoft, label: L.s("stats_chart_legend_empty"))
        }
        .padding(.top, 14)
        Text("\(L.s("stats_tries_total", month.totalTries)) · \(L.s("stats_days_active", month.activeDays))")
            .font(AppFont.bodyMedium)
            .foregroundStyle(AppColors.inkMuted)
            .padding(.top, 14)
    }

    private var weekdays: [String] {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = UiLocale.locale
        // `shortWeekdaySymbols` всегда начинается с воскресенья, какой бы ни был `firstWeekday`.
        let symbols = cal.shortWeekdaySymbols
        return symbols.count == 7 ? Array(symbols.dropFirst()) + [symbols[0]] : symbols
    }

    /// Название месяца для чипа: «Ноябрь» / «September» по языку приложения.
    /// `standaloneMonthSymbols` — именительный падеж (ноябрь), а не форматный («ноября» как в датах).
    private func monthName(_ m: FeedingStats.MonthGrid) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = UiLocale.locale
        let names = cal.standaloneMonthSymbols
        let name = names.indices.contains(m.month - 1) ? names[m.month - 1] : ""
        let label = UiLocale.language == .ru ? name.prefix(1).uppercased() + name.dropFirst() : name
        return months.first?.year == months.last?.year ? label : "\(label) \(m.year)"
    }

    @ViewBuilder
    private func dayCell(_ cell: FeedingStats.CalendarCell) -> some View {
        // Прямоугольники, а не квадраты: ширина по сетке 7, высота фиксированная; номер даты чуть ниже верха.
        let reaction = cell.bar?.hasReaction == true
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        VStack(spacing: 0) {
            Text("\(cell.date.day)")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(reaction ? AppColors.alert : AppColors.inkMuted)
                .padding(.top, 4)
            Spacer(minLength: 0)
            if let bar = cell.bar, let productId = bar.productIds.first {
                ZStack(alignment: .bottomTrailing) {
                    ProductThumb(productId: productId, name: name(productId), size: 24, background: nil)
                    if bar.tries > 1 {
                        Text("+\(bar.tries - 1)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(AppColors.surface)
                            .padding(.horizontal, 3)
                            .background(AppColors.primary, in: Capsule())
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 40)
        .background(shape.fill(reaction ? AppColors.alertSoft : AppColors.surfaceSoft))
        .overlay {
            if reaction {
                shape.strokeBorder(AppColors.alert, lineWidth: 1.5)
            }
        }
        .opacity(cell.inMonth && !cell.isFuture ? 1 : 0.4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(UiLocale.dayMonth(cell.date))
        .accessibilityValue(cell.bar.map { bar in
            [bar.productIds.first.map(name), L.s("stats_tries_total", bar.tries),
             bar.hasReaction ? L.s("stats_chart_legend_reaction") : nil].compactMap { $0 }.joined(separator: ", ")
        } ?? (cell.inMonth && !cell.isFuture ? L.s("stats_chart_legend_empty") : ""))
    }
}

private struct LegendDot: View {
    let color: Color
    let label: String
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 10, height: 10)
            Text(label).font(AppFont.bodyMedium).foregroundStyle(AppColors.inkMuted).lineLimit(1)
        }
    }
}
