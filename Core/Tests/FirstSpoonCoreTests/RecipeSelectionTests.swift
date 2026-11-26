import XCTest
@testable import FirstSpoonCore

final class RecipeSelectionTests: XCTestCase {
    func testReactionToMealDoesNotBlockOtherMealsWithTheSameIngredients() throws {
        let url = RecTestKit.catalogURL.deletingLastPathComponent().appendingPathComponent("recipes.json")
        let catalog = try JSONDecoder().decode(RecipeCatalog.self, from: Data(contentsOf: url))
        let context = RecTestKit.ctx(ageMonths: 10, marks: ["potato": .known, "broccoli": .known, "chicken": .known])
        let selection = RecipeSelection(recipes: catalog.recipes, context: context, config: RecommendationConfig(),
                                        recipesWithReaction: ["potato-broccoli"])
        let potatoes = try XCTUnwrap(selection.matches.first { $0.id == "potato-broccoli" })
        XCTAssertFalse(potatoes.forChild)
        XCTAssertTrue(potatoes.hasMealReaction)
        XCTAssertTrue(selection.matches.contains { $0.id == "chicken-potato-broccoli" && $0.forChild })
    }

    func testAllergenOrProductReactionOverridesFavorite() throws {
        let url = RecTestKit.catalogURL.deletingLastPathComponent().appendingPathComponent("recipes.json")
        let catalog = try JSONDecoder().decode(RecipeCatalog.self, from: Data(contentsOf: url))
        let context = RecTestKit.ctx(ageMonths: 10, entries: [RecTestKit.entry("broccoli", 0, .unsure)],
                                     marks: ["potato": .known], favorites: ["broccoli"])
        let selection = RecipeSelection(recipes: catalog.recipes, context: context, config: RecommendationConfig())
        XCTAssertEqual(selection.notice, .pause)
        XCTAssertFalse(selection.matches.contains { $0.id == "potato-broccoli" })
    }
}
