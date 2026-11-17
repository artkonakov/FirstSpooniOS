import Foundation

// Перечисления: в БД — текстовый код (`rawValue`, как `DbCode.db` в Android), подписи — в Localizable.strings.

/// Реакция на пробу.
public enum Reaction: String, CaseIterable, Codable, Sendable {
    /// Ещё не отмечено — родитель наблюдает.
    case unknown
    /// «Хорошо» — понравилось, реакции нет.
    case good
    /// «Без изменений» — реакции нет.
    case none
    /// «Сомнительно» — что-то настораживает.
    case unsure
    /// «Плохо» — была реакция.
    case reaction
}

/// Сколько съел.
public enum Amount: String, CaseIterable, Codable, Sendable {
    case halfTsp = "half_tsp", tsp, twoTsp = "two_tsp", tbsp
}

/// Приём пищи.
public enum Meal: String, CaseIterable, Codable, Sendable {
    case breakfast, lunch, dinner, snack
}

/// Симптомы реакции (списком кодов в `entries.symptoms`).
public enum Symptom: String, CaseIterable, Codable, Sendable {
    case rash, itch, redness, hives, swelling, bloating, diarrhea, constipation, vomiting
}

public enum Sex: String, CaseIterable, Codable, Sendable { case male, female }

/// Ручная отметка продукта для ребёнка (`child_products.status`).
public enum ProductMark: String, CaseIterable, Codable, Sendable {
    /// Уже ел до приложения — считается введённым.
    case known
    /// Не давать (например, по рекомендации врача).
    case excluded
    /// Подтверждённая аллергия.
    case allergy
}

/// Язык интерфейса и каталога. Выбирается по языку телефона, переключателя в приложении нет (решение пользователя,
/// то же правило в Android): русский — для русского и языков СНГ, иначе английский.
/// Системный выбор iOS так не умеет (казахскому телефону без русского в списке дал бы английский), поэтому язык
/// определяем сами и строки берём из `<язык>.lproj` явно.
public enum AppLocale: String, Sendable {
    case ru, en

    /// Языки, для которых показываем русский.
    public static let russianSpeaking: Set<String> = ["ru", "be", "uk", "kk", "ky", "uz", "tg", "tk", "hy", "az", "ka"]

    /// По первому предпочитаемому языку телефона (`ru-RU`, `kk-KZ`, `uz-Cyrl-UZ`…).
    public static func resolve(preferredLanguages: [String]) -> AppLocale {
        guard let first = preferredLanguages.first else { return .en }
        let code = first.split(whereSeparator: { $0 == "-" || $0 == "_" }).first.map(String.init)?.lowercased() ?? ""
        return russianSpeaking.contains(code) ? .ru : .en
    }

    /// Текущий язык (вычисляется один раз за запуск: язык телефона меняется только с перезапуском приложения).
    public static func current() -> AppLocale { cached }
    private static let cached = resolve(preferredLanguages: Locale.preferredLanguages)
}

public struct Category: Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public init(id: String, name: String) { self.id = id; self.name = name }
}

public struct Allergen: Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public init(id: String, name: String) { self.id = id; self.name = name }
}

public struct Product: Hashable, Sendable, Identifiable {
    public let id: String
    public let categoryId: String
    public let name: String
    public let minAgeMonths: Int
    /// Названия аллергенов для показа.
    public let allergens: [String]
    public let description: String
    public let firstServing: String
    /// Добавлен пользователем (custom_products), а не из каталога.
    public let isCustom: Bool
    /// id аллергенов — для сверки с аллергиями ребёнка.
    public let allergenIds: [String]
    /// Только для своих продуктов: имя файла фото в локальном хранилище фото (`PhotoStore`); nil — без фото.
    public let photo: String?

    public init(id: String, categoryId: String, name: String, minAgeMonths: Int, allergens: [String],
                description: String, firstServing: String, isCustom: Bool = false, allergenIds: [String] = [],
                photo: String? = nil) {
        self.id = id; self.categoryId = categoryId; self.name = name; self.minAgeMonths = minAgeMonths
        self.allergens = allergens; self.description = description; self.firstServing = firstServing
        self.isCustom = isCustom; self.allergenIds = allergenIds; self.photo = photo
    }

    public var isAllergen: Bool { !allergens.isEmpty }
}

public struct Catalog: Sendable {
    public let categories: [Category]
    public let products: [Product]
    public let allergens: [Allergen]
    public let productsById: [String: Product]

    public init(categories: [Category], products: [Product], allergens: [Allergen] = []) {
        self.categories = categories; self.products = products; self.allergens = allergens
        productsById = Dictionary(products.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    public static let empty = Catalog(categories: [], products: [])
}

public struct Child: Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var birthDate: LocalDate?
    public var sex: Sex?
    public var profile: ChildProfile
    /// Имя файла фото в локальном хранилище фото; nil — без фото (аватар-эмодзи).
    public var photo: String?

    public init(id: String, name: String, birthDate: LocalDate? = nil, sex: Sex? = nil, profile: ChildProfile = ChildProfile(),
                photo: String? = nil) {
        self.id = id; self.name = name; self.birthDate = birthDate; self.sex = sex; self.profile = profile; self.photo = photo
    }

    /// Полных месяцев на дату `today`; nil, если дата рождения не указана.
    public func ageMonths(_ today: LocalDate) -> Int? {
        birthDate.map { max(0, $0.monthsUntil(today)) }
    }
}

public struct DiaryEntry: Hashable, Sendable, Identifiable {
    public var id: String
    public var productId: String
    public var date: LocalDate
    public var time: LocalTime?
    public var meal: Meal?
    public var amount: Amount?
    public var reaction: Reaction
    public var symptoms: [Symptom]
    public var note: String?
    public var createdAt: Int64

    public init(id: String, productId: String, date: LocalDate, time: LocalTime? = nil, meal: Meal? = nil,
                amount: Amount? = nil, reaction: Reaction = .unknown, symptoms: [Symptom] = [], note: String? = nil,
                createdAt: Int64 = 0) {
        self.id = id; self.productId = productId; self.date = date; self.time = time; self.meal = meal
        self.amount = amount; self.reaction = reaction; self.symptoms = symptoms; self.note = note; self.createdAt = createdAt
    }
}

/// Новый id для пользовательских данных: UUID-строка в нижнем регистре (как `newId()` в Android).
public func newId() -> String { UUID().uuidString.lowercased() }
