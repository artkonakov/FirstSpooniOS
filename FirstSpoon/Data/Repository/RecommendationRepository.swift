import Foundation
import Observation
import FirstSpoonCore

/// Собирает контекст для `RecommendationEngine` из дневника и каталога. Один источник для главной и debug-экрана.
/// «Другой» (`skip`) живёт до конца дня в памяти — это не данные дневника.
@MainActor @Observable
final class RecommendationRepository {
    @ObservationIgnored private let diary: DiaryRepository
    @ObservationIgnored private let catalog: CatalogRepository
    private var config: RecommendationConfig
    #if DEBUG
    var debugStrategy: String {
        get { config.strategyId }
        set {
            config = Strategies.config(Strategies.byId(newValue))
            resetSkips()
        }
    }
    #endif
    private var skipped: (day: LocalDate, ids: Set<String>) = (.today(), [])
    /// Только debug: подменить «сегодня», чтобы прожить сценарий.
    var debugToday: LocalDate?

    init(diary: DiaryRepository, catalog: CatalogRepository, config: RecommendationConfig = Strategies.config()) {
        self.diary = diary
        self.catalog = catalog
        self.config = config
    }

    /// Пересчитывается при каждом обращении из View — зависимости отслеживает Observation.
    var result: RecommendationResult? {
        guard let child = diary.activeChild, !catalog.base.products.isEmpty else { return nil }
        let today = debugToday ?? .today()
        return RecommendationEngine.recommend(
            RecommendationContext(today: today, child: child, products: catalog.base.products, entries: diary.entries,
                                  marks: diary.marks, favorites: diary.favorites,
                                  skipped: skipped.day == today ? skipped.ids : []),
            config: config
        )
    }

    /// Кнопка «Другой»: этот продукт сегодня больше не предлагать.
    func skip(_ productId: String) {
        Analytics.track(.recommendationOther)
        let today = debugToday ?? .today()
        if skipped.day == today { skipped.ids.insert(productId) } else { skipped = (today, [productId]) }
    }

    func resetSkips() { skipped = (.today(), []) }
}
