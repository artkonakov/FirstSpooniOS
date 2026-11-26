import Foundation
import Observation
import GRDB
import FirstSpoonCore

/// Дети и дневник активного ребёнка: пробы и ручные отметки продуктов.
/// Состояние перечитывается из БД после каждой записи — экраны наблюдают свойства (`@Observable`).
@MainActor @Observable
final class DiaryRepository {
    private(set) var children: [Child] = []
    /// Выбранный ребёнок; если выбор не сохранён или ребёнок удалён — первый по дате создания.
    private(set) var activeChild: Child?
    /// Пробы активного ребёнка: дата ↓, время ↓, создание ↓ (как в Android DAO).
    private(set) var entries: [DiaryEntry] = []
    private(set) var recipeMeals: [RecipeMeal] = []
    /// Ручные отметки активного ребёнка: productId → отметка.
    private(set) var marks: [String: ProductMark] = [:]
    /// Избранные продукты активного ребёнка.
    private(set) var favorites: Set<String> = []
    /// Меняется при любой записи — удобно для пересчёта производных (напоминания).
    private(set) var version = 0

    @ObservationIgnored private let db: AppDatabase
    @ObservationIgnored private let activeStore: ActiveChildStore
    @ObservationIgnored let photos: PhotoStore
    @ObservationIgnored private let findProduct: (String) -> Product?

    init(db: AppDatabase, activeStore: ActiveChildStore, photos: PhotoStore,
         findProduct: @escaping (String) -> Product? = { _ in nil }) {
        self.db = db
        self.activeStore = activeStore
        self.photos = photos
        self.findProduct = findProduct
        reload()
    }

    func reload() {
        do {
            let all = try db.dbQueue.read { db in
                try ChildRecord.filter(sql: "deleted_at IS NULL").order(sql: "created_at").fetchAll(db)
            }
            children = all.map { $0.toDomain() }
            activeChild = children.first { $0.id == activeStore.id } ?? children.first
            if let id = activeChild?.id {
                let (e, rows, meals) = try db.dbQueue.read { db in
                    (try EntryRecord.filter(sql: "child_id = ? AND deleted_at IS NULL", arguments: [id])
                        .order(sql: "date DESC, time DESC, created_at DESC").fetchAll(db),
                     try ChildProductRecord.filter(sql: "child_id = ? AND deleted_at IS NULL", arguments: [id]).fetchAll(db),
                     try RecipeMealRecord.filter(sql: "child_id = ? AND deleted_at IS NULL", arguments: [id])
                         .order(sql: "date DESC, time DESC, created_at DESC").fetchAll(db))
                }
                entries = e.map { $0.toDomain() }
                recipeMeals = meals.compactMap { $0.toDomain() }
                marks = Dictionary(rows.compactMap { r in r.status.flatMap(ProductMark.init(rawValue:)).map { (r.productId, $0) } },
                                   uniquingKeysWith: { a, _ in a })
                favorites = Set(rows.filter(\.liked).map(\.productId))
            } else {
                entries = []; recipeMeals = []; marks = [:]; favorites = []
            }
        } catch {
            assertionFailure("DiaryRepository.reload: \(error)")
        }
        version += 1
    }

    func getChild(_ id: String) -> Child? {
        try? db.dbQueue.read { try ChildRecord.fetchOne($0, key: id) }.flatMap { $0.deletedAt == nil ? $0.toDomain() : nil }
    }

    /// Создать (`id` = nil) или изменить ребёнка. Новый ребёнок сразу становится активным.
    /// `photo`: `.none` — не менять; `.some(nil)` — убрать фото; `.some(имя)` — файл из `PhotoStore`.
    /// Прежний файл при замене или удалении фото стирается.
    @discardableResult
    func saveChild(id: String?, name: String, birthDate: LocalDate?, sex: Sex?, profile: ChildProfile,
                   photo: String?? = .none, addKnown: Set<String> = [], removeKnown: Set<String> = []) throws -> String {
        let now = nowMillis()
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let existing = try id.flatMap { id in try db.dbQueue.read { try ChildRecord.fetchOne($0, key: id) } }
        var record = existing ?? ChildRecord(id: newId(), name: trimmed, birthDate: nil, sex: nil, profile: [:],
                                             createdAt: now, updatedAt: now)
        record.name = trimmed
        record.birthDate = birthDate?.iso
        record.sex = sex?.rawValue
        record.profile = profile.toMap()
        let oldPhoto = record.photo
        if case .some(let newPhoto) = photo { record.photo = newPhoto }
        record.updatedAt = now
        let addedCount = try db.dbQueue.write { db in
            try record.save(db)
            var count = 0
            for product in addKnown {
                if try Self.updateProductRow(db, childId: record.id, productId: product, now: now, onlyIf: { $0.status == nil },
                                             { $0.status = ProductMark.known.rawValue }) {
                    count += 1
                }
            }
            for product in removeKnown {
                try Self.updateProductRow(db, childId: record.id, productId: product, now: now,
                                          onlyIf: { $0.status == ProductMark.known.rawValue }) { $0.status = nil }
            }
            return count
        }
        for _ in 0..<addedCount { Analytics.track(.productMarked(mark: .known)) }
        if oldPhoto != record.photo {
            photos.delete(oldPhoto)
            if record.photo != nil { Analytics.track(.childPhotoSet) }
        }
        if existing == nil { activeStore.set(record.id) }
        if id == nil { Analytics.track(.childAdded) }
        reload()
        return record.id
    }

    func selectChild(_ id: String) {
        activeStore.set(id)
        reload()
    }

    /// Мягкое удаление ребёнка; его пробы остаются в базе, но больше не показываются.
    func deleteChild(_ id: String) throws {
        let now = nowMillis()
        // Фото живут только на устройстве — при удалении ребёнка стираем его фото и фото его проб сразу.
        photos.delete(getChild(id)?.photo)
        let entryPhotos = (try? db.dbQueue.read { db in
            try EntryRecord.filter(sql: "child_id = ?", arguments: [id]).fetchAll(db).flatMap(\.photos)
        }) ?? []
        entryPhotos.forEach(photos.delete)
        let mealPhotos = try db.dbQueue.write { db -> [String] in
            let files = try RecipeMealRecord.filter(sql: "child_id = ?", arguments: [id]).fetchAll(db).flatMap(\.photos)
            try db.execute(sql: "UPDATE recipe_meals SET photos = '[]' WHERE child_id = ?", arguments: [id])
            try db.execute(sql: "UPDATE children SET deleted_at = ?, updated_at = ?, photo = NULL WHERE id = ?", arguments: [now, now, id])
            try db.execute(sql: "DELETE FROM assistant_chats WHERE child_id = ?", arguments: [id])
            return files
        }
        mealPhotos.forEach(photos.delete)
        if activeStore.id == id { activeStore.set(nil) }
        reload()
    }

    @discardableResult
    func addEntry(productId: String, date: LocalDate = .today(), time: LocalTime? = nil, meal: Meal? = nil,
                  amount: Amount? = nil, reaction: Reaction = .unknown, symptoms: [Symptom] = [], note: String? = nil,
                  photos: [String] = []) throws -> String {
        guard let childId = activeChild?.id else { throw RepositoryError.noActiveChild }
        let now = nowMillis()
        let record = EntryRecord(id: newId(), childId: childId, productId: productId, date: date.iso, time: time?.description,
                                 meal: meal?.rawValue, amount: amount?.rawValue, reaction: reaction.rawValue,
                                 symptoms: symptoms.map(\.rawValue), note: Self.clean(note),
                                 photos: Array(photos.prefix(DiaryEntry.maxPhotos)), createdAt: now, updatedAt: now)
        try db.dbQueue.write { try record.insert($0) }
        Analytics.track(.entryAdded(food: analyticsFood(productId)))
        reload()
        return record.id
    }

    /// Есть ли пробы продукта у любого ребёнка.
    func hasEntries(_ productId: String) -> Bool {
        (try? db.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM entries WHERE product_id = ? AND deleted_at IS NULL", arguments: [productId])
        } ?? 0) ?? 0 > 0
    }

    func getEntry(_ id: String) -> DiaryEntry? {
        try? db.dbQueue.read { try EntryRecord.fetchOne($0, key: id) }.flatMap { $0.deletedAt == nil ? $0.toDomain() : nil }
    }

    func saveRecipeMeal(_ meal: RecipeMeal, editing: Bool) throws {
        guard activeChild?.id == meal.childId, !meal.eatenIngredients.isEmpty else { throw RepositoryError.invalidMeal }
        let now = nowMillis()
        let files = Array(meal.photos.prefix(DiaryEntry.maxPhotos))
        let removed = try db.dbQueue.write { db -> Set<String> in
            let previous = try RecipeMealRecord.fetchOne(db, key: meal.id)
            if editing {
                guard previous?.deletedAt == nil, previous?.childId == meal.childId else { throw RepositoryError.invalidMeal }
            } else if previous != nil {
                throw RepositoryError.invalidMeal
            }
            let row = RecipeMealRecord(id: meal.id, childId: meal.childId, recipeId: previous?.recipeId ?? meal.recipeId,
                                       snapshot: meal.snapshot, date: meal.date.iso, time: meal.time?.description,
                                       meal: meal.meal?.rawValue, amount: meal.amount?.rawValue,
                                       reaction: meal.reaction.rawValue, note: Self.clean(meal.note),
                                       photos: files, createdAt: previous?.createdAt ?? now, updatedAt: now)
            if editing { try row.update(db) } else { try row.insert(db) }
            return Set(previous?.photos ?? []).subtracting(files)
        }
        removed.forEach(photos.delete)
        reload()
    }

    func deleteRecipeMeal(_ meal: RecipeMeal) throws {
        guard activeChild?.id == meal.childId else { throw RepositoryError.invalidMeal }
        let files = try db.dbQueue.write { db -> [String] in
            guard var row = try RecipeMealRecord.fetchOne(db, key: meal.id),
                  row.deletedAt == nil, row.childId == meal.childId else { throw RepositoryError.invalidMeal }
            let files = row.photos
            row.photos = []
            row.updatedAt = nowMillis()
            row.deletedAt = row.updatedAt
            try row.update(db)
            return files
        }
        files.forEach(photos.delete)
        reload()
    }

    /// Сохранить изменённую пробу. Ребёнок и дата создания не меняются.
    func updateEntry(_ entry: DiaryEntry) throws {
        guard var old = try db.dbQueue.read({ try EntryRecord.fetchOne($0, key: entry.id) }) else { return }
        let reactionChanged = old.reaction != entry.reaction.rawValue
        old.productId = entry.productId
        old.date = entry.date.iso
        old.time = entry.time?.description
        old.meal = entry.meal?.rawValue
        old.amount = entry.amount?.rawValue
        old.reaction = entry.reaction.rawValue
        old.symptoms = entry.symptoms.map(\.rawValue)
        old.note = Self.clean(entry.note)
        let removed = Set(old.photos).subtracting(entry.photos)
        old.photos = Array(entry.photos.prefix(DiaryEntry.maxPhotos))
        old.updatedAt = nowMillis()
        try db.dbQueue.write { try old.update($0) }
        let food = analyticsFood(entry.productId)
        Analytics.track(.entryUpdated(food: food))
        if reactionChanged { Analytics.track(.entryReactionChanged(food: food)) }
        // Убранные из пробы фото — стираем файлы (сначала БД, потом файл).
        removed.forEach(photos.delete)
        reload()
    }

    func setReaction(_ entryId: String, _ reaction: Reaction) throws {
        let original = getEntry(entryId)
        let now = nowMillis()
        try db.dbQueue.write {
            try $0.execute(sql: "UPDATE entries SET reaction = ?, updated_at = ? WHERE id = ?", arguments: [reaction.rawValue, now, entryId])
        }
        if let original, original.reaction != reaction {
            Analytics.track(.entryReactionChanged(food: analyticsFood(original.productId)))
        }
        reload()
    }

    /// Мягкое удаление: запись скрывается, но остаётся для будущей синхронизации.
    func deleteEntry(_ entryId: String) throws {
        let now = nowMillis()
        let original = try? db.dbQueue.read { try EntryRecord.fetchOne($0, key: entryId) }
        let files = original?.photos ?? []
        try db.dbQueue.write { try $0.execute(sql: "UPDATE entries SET deleted_at = ?, updated_at = ?, photos = '[]' WHERE id = ?", arguments: [now, now, entryId]) }
        // Мягкое удаление записи, но фото живут только на устройстве — стираем их сразу.
        files.forEach(photos.delete)
        if let original, original.deletedAt == nil { Analytics.track(.entryDeleted(food: analyticsFood(original.productId))) }
        reload()
    }

    /// Поставить или снять (mark = nil) ручную отметку продукта. Избранное не трогает.
    func setMark(_ productId: String, _ mark: ProductMark?) throws {
        let previous = marks[productId]
        try updateProductRow(productId) { $0.status = mark?.rawValue }
        guard previous != mark else { return }
        let food = analyticsFood(productId)
        if let mark { Analytics.track(.productMarked(mark: mark, food: food)) }
        else { Analytics.track(.productMarkRemoved(food: food)) }
    }

    /// Добавить или убрать продукт из избранного. Отметку не трогает.
    func setLiked(_ productId: String, _ liked: Bool) throws {
        let changed = favorites.contains(productId) != liked
        try updateProductRow(productId) { $0.liked = liked }
        if changed { Analytics.track(.productFavoriteChanged(food: analyticsFood(productId), liked: liked)) }
    }

    private func analyticsFood(_ id: String) -> AnalyticsEvent.Food {
        if let product = findProduct(id) { return product.isCustom ? .custom : .catalog(product.id) }
        if (try? db.dbQueue.read { try CustomProductRecord.fetchOne($0, key: id) }) != nil { return .custom }
        return .unknown
    }

    /// Строка child_products без отметки и без лайка не нужна — мягко удаляем.
    private func updateProductRow(_ productId: String, _ change: (inout ChildProductRecord) -> Void) throws {
        guard let childId = activeChild?.id else { throw RepositoryError.noActiveChild }
        let now = nowMillis()
        try db.dbQueue.write { db in
            _ = try Self.updateProductRow(db, childId: childId, productId: productId, now: now, change)
        }
        reload()
    }

    @discardableResult
    private static func updateProductRow(_ db: Database, childId: String, productId: String, now: Int64,
                                         onlyIf: (ChildProductRecord) -> Bool = { _ in true },
                                         _ change: (inout ChildProductRecord) -> Void) throws -> Bool {
        var row = try ChildProductRecord.fetchOne(db, key: ["child_id": childId, "product_id": productId])
            ?? ChildProductRecord(childId: childId, productId: productId, status: nil, liked: false, note: nil, createdAt: now, updatedAt: now)
        guard onlyIf(row) else { return false }
        change(&row)
        row.updatedAt = now
        row.deletedAt = (row.status == nil && !row.liked) ? now : nil
        try row.save(db)
        return true
    }

    private static func clean(_ note: String?) -> String? {
        guard let t = note?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return t
    }
}

enum RepositoryError: Error { case noActiveChild, invalidMeal }
