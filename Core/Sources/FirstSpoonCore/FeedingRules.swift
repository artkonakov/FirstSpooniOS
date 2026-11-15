/// Бизнес-правила введения продуктов. Статусы НЕ хранятся в БД — вычисляются из проб
/// и ручных отметок (child_products). Приоритет, сверху вниз:
/// 1. отметка «аллергия» → `.allergy`;
/// 2. отметка «исключён» → `.excluded`;
/// 3. проба с реакцией «Плохо»/«Сомнительно» → `.reaction` (требует внимания);
/// 4. отметка «уже знаком» или `seriesTarget` проб → `.introduced`;
/// 5. 1..2 пробы → `.inProgress`, 0 → `.notTried`.
/// Цель — `introductionGoal` введённых продуктов.
public enum FeedingRules {
    public static let seriesTarget = 3
    public static let introductionGoal = 100

    private static let attention: Set<Reaction> = [.reaction, .unsure]

    public static func progressByProduct(_ entries: [DiaryEntry], marks: [String: ProductMark] = [:]) -> [String: ProductProgress] {
        let byProduct = Dictionary(grouping: entries, by: \.productId)
        var result: [String: ProductProgress] = [:]
        for id in Set(byProduct.keys).union(marks.keys) {
            result[id] = progressOf(id, byProduct[id] ?? [], mark: marks[id])
        }
        return result
    }

    public static func progressOf(_ productId: String, _ entries: [DiaryEntry], mark: ProductMark? = nil) -> ProductProgress {
        let tries = entries.count
        let status: ProductStatus
        if mark == .allergy { status = .allergy }
        else if mark == .excluded { status = .excluded }
        else if entries.contains(where: { attention.contains($0.reaction) }) { status = .reaction }
        else if mark == .known || tries >= seriesTarget { status = .introduced }
        else if tries > 0 { status = .inProgress }
        else { status = .notTried }
        return ProductProgress(productId: productId, tries: min(tries, seriesTarget), status: status)
    }
}

public enum ProductStatus: String, CaseIterable, Sendable {
    case notTried, inProgress, introduced, reaction, excluded, allergy

    /// Показывать в «Требуют внимания».
    public var needsAttention: Bool { self == .reaction || self == .allergy }
}

public struct ProductProgress: Hashable, Sendable {
    public let productId: String
    public let tries: Int
    public let status: ProductStatus

    public init(productId: String, tries: Int, status: ProductStatus) {
        self.productId = productId; self.tries = tries; self.status = status
    }
}
