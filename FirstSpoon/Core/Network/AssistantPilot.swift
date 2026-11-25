import Foundation
import FirstSpoonCore

enum AssistantPilot {
    static var enabled: Bool {
        #if DEBUG || ASSISTANT_PILOT
        true
        #else
        false
        #endif
    }

    private static let gateway = URL(string: "https://d5d3r0mjsmuuqmckv04v.qsvaa8tq.apigw.yandexcloud.net/")!
    private static let chatEncoder = JSONEncoder()

    static func reply(api: ApiClient, request: AssistantRequest, owner: String) async -> ApiResult<AssistantReply> {
        await api.call("POST", "assistant/chat", body: request, authorized: true,
                       root: gateway, encoder: chatEncoder, expectedOwner: owner)
    }
}

struct AssistantMessage: Codable {
    let role: String
    let text: String
}

struct AssistantProduct: Codable {
    let productId: String
    let ageMonths: Int?
    let stage: String
    let texture: String
    let familiarIds: [String]
    let locale: String
    let preparationOnly: Bool
}

struct AssistantContext: Codable {
    let locale: String
    let ageMonths: Int?
    let product: AssistantProduct?

    @MainActor init(app: AppContainer, child: Child, productId: String?) {
        let today = LocalDate.today()
        locale = UiLocale.language.rawValue
        ageMonths = child.ageMonths(today).flatMap { (0...240).contains($0) ? $0 : nil }
        let catalog = app.catalog.catalog
        guard let productId, let item = catalog.productsById[productId] else {
            product = nil
            return
        }

        let facts = Facts(RecommendationContext(today: today, child: child, products: catalog.products,
                                                entries: app.diary.entries.filter { !$0.date.isAfter(today) },
                                                marks: app.diary.marks))
        let config = Strategies.config()
        let status = facts.progress[item.id]?.status
        let restricted = item.isCustom || ageMonths == nil || (ageMonths ?? 0) < FeedingReadiness.minMonths
            || Rules.tooYoung.exclude(item, facts, config) != nil || Rules.notReadyForSolids.decide(facts, config) != nil
            || status == .allergy || status == .excluded || status == .reaction
            || Rules.knownAllergen.exclude(item, facts, config) != nil
            || (status != .introduced && (Rules.pauseAfterReaction.decide(facts, config) != nil
                || Rules.doctorFirstForHighRisk.exclude(item, facts, config) != nil))
        let known = facts.introduced.filter {
            $0.id != item.id && !$0.isCustom && Rules.knownAllergen.exclude($0, facts, config) == nil
        }
        let familiar = (known.filter { $0.categoryId == item.categoryId } + known.filter { $0.categoryId != item.categoryId })
            .prefix(12).map(\.id)
        product = AssistantProduct(productId: item.isCustom ? "custom" : item.id, ageMonths: ageMonths,
                                   stage: status == .introduced ? "known" : status == .inProgress ? "continue" : "first",
                                   texture: "unknown", familiarIds: restricted ? [] : familiar,
                                   locale: locale, preparationOnly: restricted)
    }
}

struct AssistantRequest: Encodable {
    let requestId: String
    let question: String
    let history: [AssistantMessage]
    let locale: String
    let ageMonths: Int?
    let product: AssistantProduct?
}

struct AssistantReply: Codable {
    struct Source: Codable, Hashable {
        let title: String
        let url: String
    }
    let kind: String
    let answer: String
    let sources: [Source]
}
