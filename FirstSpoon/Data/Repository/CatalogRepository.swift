import Foundation
import Observation
import GRDB
import FirstSpoonCore

/// Откуда берём каталог. Сейчас — из бандла (`catalog.json`); сетевой источник (`GET /catalog`) подключается сюда же.
protocol CatalogSource {
    func load() throws -> CatalogPayload
}

struct BundleCatalogSource: CatalogSource {
    func load() throws -> CatalogPayload {
        guard let url = Bundle.main.url(forResource: "catalog", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try CatalogPayload.decode(Data(contentsOf: url))
    }
}

/// Каталог для экранов: продукты каталога + свои продукты пользователя (`custom_products`).
/// Свой продукт без категории попадает в группу «Свои продукты» в конце списка.
@MainActor @Observable
final class CatalogRepository {
    /// Псевдо-категория для своих продуктов без категории.
    static let customCategoryId = "custom"

    private(set) var catalog: Catalog = .empty
    /// Каталог без своих продуктов — им пользуется рекомендательный движок.
    private(set) var base: Catalog = .empty

    @ObservationIgnored private let db: AppDatabase
    @ObservationIgnored private let source: CatalogSource
    @ObservationIgnored let photos: PhotoStore

    init(db: AppDatabase, photos: PhotoStore, source: CatalogSource = BundleCatalogSource()) {
        self.db = db
        self.photos = photos
        self.source = source
        do {
            base = try source.load().toCatalog()
        } catch {
            assertionFailure("catalog.json: \(error)")
        }
        reload()
    }

    func reload() {
        let custom = (try? db.dbQueue.read { db in
            try CustomProductRecord.filter(sql: "deleted_at IS NULL").order(sql: "name COLLATE NOCASE").fetchAll(db)
        }) ?? []
        let known = Set(base.categories.map(\.id))
        let allergenNames = Dictionary(base.allergens.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        let customProducts = custom.map { c in
            Product(id: c.id, categoryId: c.categoryId.flatMap { known.contains($0) ? $0 : nil } ?? Self.customCategoryId,
                    name: c.name, minAgeMonths: 0, allergens: c.allergenIds.compactMap { allergenNames[$0] },
                    description: "", firstServing: "", isCustom: true, allergenIds: c.allergenIds, photo: c.photo)
        }
        let customCategory = customProducts.contains { $0.categoryId == Self.customCategoryId }
            ? [Category(id: Self.customCategoryId, name: L.s("catalog_custom_category"))] : []
        catalog = Catalog(categories: base.categories + customCategory, products: base.products + customProducts,
                          allergens: base.allergens)
    }

    /// Добавить свой продукт. Возвращает его id (UUID) — его же пишем в `entries.product_id`.
    @discardableResult
    func addCustomProduct(name: String, categoryId: String?, allergenIds: [String], photo: String? = nil) throws -> String {
        let now = nowMillis()
        let record = CustomProductRecord(id: newId(), name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                                         categoryId: categoryId, allergenIds: allergenIds, photo: photo,
                                         createdAt: now, updatedAt: now)
        try db.dbQueue.write { try record.insert($0) }
        Analytics.track(.customProductAdded)
        if photo != nil { Analytics.track(.customProductPhotoSet) }
        reload()
        return record.id
    }

    /// Изменить свой продукт. Прежнее фото при замене или удалении стирается.
    func updateCustomProduct(_ id: String, name: String, categoryId: String?, allergenIds: [String], photo: String?) throws {
        guard var record = try db.dbQueue.read({ try CustomProductRecord.fetchOne($0, key: id) }) else { return }
        let oldPhoto = record.photo
        record.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        record.categoryId = categoryId
        record.allergenIds = allergenIds
        record.photo = photo
        record.updatedAt = nowMillis()
        try db.dbQueue.write { try record.update($0) }
        if oldPhoto != photo {
            photos.delete(oldPhoto)
            if photo != nil { Analytics.track(.customProductPhotoSet) }
        }
        reload()
    }

    func deleteCustomProduct(_ id: String) throws {
        let now = nowMillis()
        photos.delete(catalog.productsById[id]?.photo)
        let removed = try db.dbQueue.write { db in
            try db.execute(sql: "UPDATE custom_products SET deleted_at = ?, updated_at = ?, photo = NULL WHERE id = ? AND deleted_at IS NULL", arguments: [now, now, id])
            return db.changesCount > 0
        }
        if removed { Analytics.track(.customProductDeleted) }
        reload()
    }
}
