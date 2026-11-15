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
    /// Ручные отметки активного ребёнка: productId → отметка.
    private(set) var marks: [String: ProductMark] = [:]
    /// Избранные продукты активного ребёнка.
    private(set) var favorites: Set<String> = []
    /// Меняется при любой записи — удобно для пересчёта производных (напоминания).
    private(set) var version = 0

    @ObservationIgnored private let db: AppDatabase
    @ObservationIgnored private let activeStore: ActiveChildStore

    init(db: AppDatabase, activeStore: ActiveChildStore) {
        self.db = db
        self.activeStore = activeStore
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
                let (e, rows) = try db.dbQueue.read { db in
                    (try EntryRecord.filter(sql: "child_id = ? AND deleted_at IS NULL", arguments: [id])
                        .order(sql: "date DESC, time DESC, created_at DESC").fetchAll(db),
                     try ChildProductRecord.filter(sql: "child_id = ? AND deleted_at IS NULL", arguments: [id]).fetchAll(db))
                }
                entries = e.map { $0.toDomain() }
                marks = Dictionary(rows.compactMap { r in r.status.flatMap(ProductMark.init(rawValue:)).map { (r.productId, $0) } },
                                   uniquingKeysWith: { a, _ in a })
                favorites = Set(rows.filter(\.liked).map(\.productId))
            } else {
                entries = []; marks = [:]; favorites = []
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
    @discardableResult
    func saveChild(id: String?, name: String, birthDate: LocalDate?, sex: Sex?, profile: ChildProfile) throws -> String {
        let now = nowMillis()
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let existing = try id.flatMap { id in try db.dbQueue.read { try ChildRecord.fetchOne($0, key: id) } }
        var record = existing ?? ChildRecord(id: newId(), name: trimmed, birthDate: nil, sex: nil, profile: [:],
                                             createdAt: now, updatedAt: now)
        record.name = trimmed
        record.birthDate = birthDate?.iso
        record.sex = sex?.rawValue
        record.profile = profile.toMap()
        record.updatedAt = now
        try db.dbQueue.write { try record.save($0) }
        if existing == nil { activeStore.set(record.id) }
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
        try db.dbQueue.write { try $0.execute(sql: "UPDATE children SET deleted_at = ?, updated_at = ? WHERE id = ?", arguments: [now, now, id]) }
        if activeStore.id == id { activeStore.set(nil) }
        reload()
    }

    @discardableResult
    func addEntry(productId: String, date: LocalDate = .today(), time: LocalTime? = nil, meal: Meal? = nil,
                  amount: Amount? = nil, reaction: Reaction = .unknown, symptoms: [Symptom] = [], note: String? = nil) throws -> String {
        guard let childId = activeChild?.id else { throw RepositoryError.noActiveChild }
        let now = nowMillis()
        let record = EntryRecord(id: newId(), childId: childId, productId: productId, date: date.iso, time: time?.description,
                                 meal: meal?.rawValue, amount: amount?.rawValue, reaction: reaction.rawValue,
                                 symptoms: symptoms.map(\.rawValue), note: Self.clean(note), createdAt: now, updatedAt: now)
        try db.dbQueue.write { try record.insert($0) }
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

    /// Сохранить изменённую пробу. Ребёнок и дата создания не меняются.
    func updateEntry(_ entry: DiaryEntry) throws {
        guard var old = try db.dbQueue.read({ try EntryRecord.fetchOne($0, key: entry.id) }) else { return }
        old.productId = entry.productId
        old.date = entry.date.iso
        old.time = entry.time?.description
        old.meal = entry.meal?.rawValue
        old.amount = entry.amount?.rawValue
        old.reaction = entry.reaction.rawValue
        old.symptoms = entry.symptoms.map(\.rawValue)
        old.note = Self.clean(entry.note)
        old.updatedAt = nowMillis()
        try db.dbQueue.write { try old.update($0) }
        reload()
    }

    func setReaction(_ entryId: String, _ reaction: Reaction) throws {
        let now = nowMillis()
        try db.dbQueue.write {
            try $0.execute(sql: "UPDATE entries SET reaction = ?, updated_at = ? WHERE id = ?", arguments: [reaction.rawValue, now, entryId])
        }
        reload()
    }

    /// Мягкое удаление: запись скрывается, но остаётся для будущей синхронизации.
    func deleteEntry(_ entryId: String) throws {
        let now = nowMillis()
        try db.dbQueue.write { try $0.execute(sql: "UPDATE entries SET deleted_at = ?, updated_at = ? WHERE id = ?", arguments: [now, now, entryId]) }
        reload()
    }

    /// Поставить или снять (mark = nil) ручную отметку продукта. Избранное не трогает.
    func setMark(_ productId: String, _ mark: ProductMark?) throws {
        try updateProductRow(productId) { $0.status = mark?.rawValue }
    }

    /// Добавить или убрать продукт из избранного. Отметку не трогает.
    func setLiked(_ productId: String, _ liked: Bool) throws {
        try updateProductRow(productId) { $0.liked = liked }
    }

    /// Строка child_products без отметки и без лайка не нужна — мягко удаляем.
    private func updateProductRow(_ productId: String, _ change: (inout ChildProductRecord) -> Void) throws {
        guard let childId = activeChild?.id else { throw RepositoryError.noActiveChild }
        let now = nowMillis()
        try db.dbQueue.write { db in
            var row = try ChildProductRecord.fetchOne(db, key: ["child_id": childId, "product_id": productId])
                ?? ChildProductRecord(childId: childId, productId: productId, status: nil, liked: false, note: nil, createdAt: now, updatedAt: now)
            change(&row)
            row.updatedAt = now
            row.deletedAt = (row.status == nil && !row.liked) ? now : nil
            try row.save(db)
        }
        reload()
    }

    private static func clean(_ note: String?) -> String? {
        guard let t = note?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return t
    }
}

enum RepositoryError: Error { case noActiveChild }
