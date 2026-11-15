import Foundation

/// Формат `catalog.json` (тот же, что в Android `assets/catalog.json`; генерируется `tools/build_catalog.py`
/// в Android-проекте — руками не править). Будущий `GET /catalog` отдаёт тот же формат.
public struct CatalogPayload: Codable, Sendable {
    public struct Text: Codable, Sendable {
        public let ru: String
        public let en: String
        public func value(_ locale: AppLocale = .current()) -> String { locale == .ru ? ru : en }
    }
    public struct CategoryDto: Codable, Sendable {
        public let id: String
        public let sort: Int
        public let name: Text
    }
    public struct AllergenDto: Codable, Sendable {
        public let id: String
        public let name: Text
    }
    public struct ProductDto: Codable, Sendable {
        public let id: String
        public let category: String
        public let minAgeMonths: Int
        public let allergens: [String]
        public let sort: Int
        public let name: Text
        public let description: Text?
        public let firstServing: Text?
    }

    public let version: Int
    public let categories: [CategoryDto]
    public let allergens: [AllergenDto]
    public let products: [ProductDto]

    public static func decode(_ data: Data) throws -> CatalogPayload {
        try JSONDecoder().decode(CatalogPayload.self, from: data)
    }

    /// Доменный каталог: категории и продукты в порядке `sort`, названия аллергенов на языке интерфейса.
    public func toCatalog(_ locale: AppLocale = .current()) -> Catalog {
        let allergenNames = Dictionary(allergens.map { ($0.id, $0.name.value(locale)) }, uniquingKeysWith: { a, _ in a })
        return Catalog(
            categories: categories.sorted { $0.sort < $1.sort }.map { Category(id: $0.id, name: $0.name.value(locale)) },
            products: products.enumerated().sorted { $0.element.sort != $1.element.sort ? $0.element.sort < $1.element.sort : $0.offset < $1.offset }
                .map(\.element).map { p in
                    Product(id: p.id, categoryId: p.category, name: p.name.value(locale), minAgeMonths: p.minAgeMonths,
                            allergens: p.allergens.map { allergenNames[$0] ?? $0 },
                            description: p.description?.value(locale) ?? "", firstServing: p.firstServing?.value(locale) ?? "",
                            allergenIds: p.allergens)
                },
            allergens: allergens.map { Allergen(id: $0.id, name: $0.name.value(locale)) }
        )
    }
}
