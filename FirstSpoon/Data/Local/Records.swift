import Foundation
import GRDB
import FirstSpoonCore

// Строки таблиц. Колонки — snake_case, JSON-колонки GRDB кодирует сам (Codable-значения, не примитивы).

protocol SnakeCaseRecord: Codable, FetchableRecord, PersistableRecord {}
extension SnakeCaseRecord {
    static var databaseColumnDecodingStrategy: DatabaseColumnDecodingStrategy { .convertFromSnakeCase }
    static var databaseColumnEncodingStrategy: DatabaseColumnEncodingStrategy { .convertToSnakeCase }
}

struct ChildRecord: SnakeCaseRecord, Equatable {
    static let databaseTableName = "children"
    var id: String
    var name: String
    var birthDate: String?
    var sex: String?
    var profile: [String: String]
    /// Имя файла фото (PhotoStore) или nil.
    var photo: String?
    var createdAt: Int64
    var updatedAt: Int64
    var deletedAt: Int64?

    func toDomain() -> Child {
        Child(id: id, name: name, birthDate: birthDate.flatMap(LocalDate.parse), sex: sex.flatMap(Sex.init(rawValue:)),
              profile: ChildProfile.fromMap(profile), photo: photo)
    }
}

struct CustomProductRecord: SnakeCaseRecord, Equatable {
    static let databaseTableName = "custom_products"
    var id: String
    var name: String
    var categoryId: String?
    var allergenIds: [String]
    /// Имя файла фото (PhotoStore) или nil.
    var photo: String?
    var createdAt: Int64
    var updatedAt: Int64
    var deletedAt: Int64?
}

struct EntryRecord: SnakeCaseRecord, Equatable {
    static let databaseTableName = "entries"
    var id: String
    var childId: String
    var productId: String
    var date: String
    var time: String?
    var meal: String?
    var amount: String?
    var reaction: String
    var symptoms: [String]
    var note: String?
    /// Фото пробы — имена файлов PhotoStore по порядку.
    var photos: [String]
    var createdAt: Int64
    var updatedAt: Int64
    var deletedAt: Int64?

    func toDomain() -> DiaryEntry {
        DiaryEntry(id: id, productId: productId, date: LocalDate.parse(date) ?? LocalDate(epochDay: 0),
                   time: time.flatMap(LocalTime.parse), meal: meal.flatMap(Meal.init(rawValue:)),
                   amount: amount.flatMap(Amount.init(rawValue:)), reaction: Reaction(rawValue: reaction) ?? .unknown,
                   symptoms: symptoms.compactMap(Symptom.init(rawValue:)), note: note, photos: photos, createdAt: createdAt)
    }
}

struct RecipeMealRecord: SnakeCaseRecord {
    static let databaseTableName = "recipe_meals"
    var id: String
    var childId: String
    var recipeId: String
    var snapshot: RecipeMeal.Snapshot
    var date: String
    var time: String?
    var meal: String?
    var amount: String?
    var reaction: String
    var note: String?
    var photos: [String]
    var createdAt: Int64
    var updatedAt: Int64
    var deletedAt: Int64?

    func toDomain() -> RecipeMeal? {
        guard let day = LocalDate.parse(date) else { return nil }
        return RecipeMeal(id: id, childId: childId, recipeId: recipeId, snapshot: snapshot, date: day,
                          time: time.flatMap(LocalTime.parse), meal: meal.flatMap(Meal.init(rawValue:)),
                          amount: amount.flatMap(Amount.init(rawValue:)), reaction: Reaction(rawValue: reaction) ?? .unknown,
                          note: note, photos: photos, createdAt: createdAt)
    }
}

/// То, что нельзя вывести из проб: ручная отметка и избранное. Одна строка на пару ребёнок + продукт.
struct ChildProductRecord: SnakeCaseRecord, Equatable {
    static let databaseTableName = "child_products"
    var childId: String
    var productId: String
    var status: String?
    var liked: Bool
    var note: String?
    var createdAt: Int64
    var updatedAt: Int64
    var deletedAt: Int64?
}
