import Foundation

public struct RecipeCatalog: Decodable, Sendable {
    public let version: Int
    public let recipes: [Recipe]
}

public struct Recipe: Decodable, Identifiable, Sendable {
    public let id: String
    public let title: CatalogPayload.Text
    public let minutes: Int
    public let portions: Int
    public let ingredients: [Ingredient]
    public let steps: [CatalogPayload.Text]
    public let textures: [Texture]

    public struct Ingredient: Decodable, Sendable, Identifiable {
        public let productId: String
        public let grams: Int
        public var id: String { productId }
    }

    public enum Texture: String, Decodable, CaseIterable, Sendable {
        case puree = "PUREE", mashed = "MASHED"
    }

    private enum CodingKeys: String, CodingKey { case id, title, minutes, portions, ingredients, steps, textures }

    public init(from decoder: Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        id = try fields.decode(String.self, forKey: .id)
        title = try fields.decode(CatalogPayload.Text.self, forKey: .title)
        minutes = try fields.decode(Int.self, forKey: .minutes)
        portions = try fields.decode(Int.self, forKey: .portions)
        ingredients = try fields.decode([Ingredient].self, forKey: .ingredients)
        steps = try fields.decode([CatalogPayload.Text].self, forKey: .steps)
        textures = try fields.decodeIfPresent([Texture].self, forKey: .textures) ?? Texture.allCases
    }
}

public struct RecipeSelection: Sendable {
    public struct Match: Identifiable, Sendable {
        public let recipe: Recipe
        public let favoriteCount: Int
        public let forChild: Bool
        public let hasMealReaction: Bool
        public var id: String { recipe.id }
    }

    public enum Notice: Sendable { case notReady, pause, unknownAllergy }

    public let matches: [Match]
    public let notice: Notice?

    public init(recipes: [Recipe], context: RecommendationContext, config: RecommendationConfig,
                recipesWithReaction: Set<String> = []) {
        var context = context
        context.entries = context.entries.filter { $0.date <= context.today }
        let facts = Facts(context)
        let notice: Notice?
        if facts.progress.contains(where: { $0.value.status == .allergy && facts.productsById[$0.key]?.isCustom != false }) {
            notice = .unknownAllergy
        } else if (facts.ageMonths ?? 0) < FeedingReadiness.minMonths || Rules.notReadyForSolids.decide(facts, config) != nil {
            notice = .notReady
        } else if Rules.pauseAfterReaction.decide(facts, config) != nil {
            notice = .pause
        } else {
            notice = nil
        }

        self.notice = notice
        matches = recipes.compactMap { recipe -> Match? in
            let products = recipe.ingredients.compactMap { facts.productsById[$0.productId] }
            guard !products.isEmpty, products.count == recipe.ingredients.count,
                  !products.contains(where: { product in
                      if product.isCustom || Rules.knownAllergen.exclude(product, facts, config) != nil { return true }
                      switch facts.progress[product.id]?.status {
                      case .allergy, .excluded, .reaction: return true
                      default: return false
                      }
                  }) else { return nil }

            let hasMealReaction = recipesWithReaction.contains(recipe.id)
            let forChild = !hasMealReaction && notice == nil && !recipe.textures.isEmpty && products.allSatisfy {
                facts.progress[$0.id]?.status == .introduced && Rules.tooYoung.exclude($0, facts, config) == nil
            }
            let favorites = forChild ? products.filter { context.favorites.contains($0.id) }.count : 0
            return Match(recipe: recipe, favoriteCount: favorites, forChild: forChild, hasMealReaction: hasMealReaction)
        }.sorted {
            if $0.forChild != $1.forChild { return $0.forChild }
            if $0.favoriteCount != $1.favoriteCount { return $0.favoriteCount > $1.favoriteCount }
            if $0.recipe.minutes != $1.recipe.minutes { return $0.recipe.minutes < $1.recipe.minutes }
            return $0.id < $1.id
        }
    }
}

public struct RecipeMeal: Identifiable, Sendable {
    public struct Snapshot: Codable, Sendable {
        public var title: CatalogPayload.Text
        public var ingredients: [Ingredient]

        public init(title: CatalogPayload.Text, ingredients: [Ingredient]) {
            self.title = title
            self.ingredients = ingredients
        }
    }

    public struct Ingredient: Codable, Identifiable, Sendable {
        public let productId: String
        public let name: String
        public var eaten: Bool
        public var id: String { productId }

        public init(productId: String, name: String, eaten: Bool = true) {
            self.productId = productId
            self.name = name
            self.eaten = eaten
        }
    }

    public let id: String
    public let childId: String
    public let recipeId: String
    public var snapshot: Snapshot
    public var date: LocalDate
    public var time: LocalTime?
    public var meal: Meal?
    public var amount: Amount?
    public var reaction: Reaction
    public var note: String?
    public var photos: [String]
    public let createdAt: Int64

    public init(id: String, childId: String, recipeId: String, snapshot: Snapshot, date: LocalDate,
                time: LocalTime? = nil, meal: Meal? = nil, amount: Amount? = nil, reaction: Reaction = .unknown,
                note: String? = nil, photos: [String] = [], createdAt: Int64 = 0) {
        self.id = id
        self.childId = childId
        self.recipeId = recipeId
        self.snapshot = snapshot
        self.date = date
        self.time = time
        self.meal = meal
        self.amount = amount
        self.reaction = reaction
        self.note = note
        self.photos = photos
        self.createdAt = createdAt
    }

    public var eatenIngredients: [Ingredient] { snapshot.ingredients.filter(\.eaten) }
    public var hasReaction: Bool { reaction == .unsure || reaction == .reaction }
}
