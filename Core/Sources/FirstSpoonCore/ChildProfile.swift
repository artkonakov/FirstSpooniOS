/// Вопросы профиля ребёнка — единый реестр. Из него строятся шаги онбординга, редактирование ребёнка,
/// а ответы читает рекомендательный движок.
///
/// Новый вопрос: значение здесь (+ подписи в `UI/Common/ProfileQuestionTexts.swift`). Он сразу появится
/// в онбординге (если `inOnboarding`) и в профиле. Схема БД не меняется: ответы лежат в `children.profile`.
public enum ProfileQuestion: String, CaseIterable, Sendable {
    case knownAllergens = "known_allergens"
    case eczema
    case familyAllergy = "family_allergy"
    case milkFeeding = "milk_feeding"
    /// Готовность к прикорму (Android docs/product-rules.md «Онбординг»): держит голову, сидит с поддержкой.
    case headControl = "head_control"
    case sits = "sits_with_support"
    case foodInterest = "food_interest"

    public enum Kind: Sendable { case single, multi }

    /// Коды ответов (то, что хранится в БД).
    public enum Answer {
        public static let no = "no"
        public static let yes = "yes"
        public static let notSure = "not_sure"
        public static let breast = "breast"
        public static let formula = "formula"
        public static let mixed = "mixed"
    }

    public var key: String { rawValue }

    public var kind: Kind { self == .knownAllergens ? .multi : .single }

    /// Коды вариантов. Для `knownAllergens` варианты — аллергены каталога (динамические).
    public var options: [String] {
        switch self {
        case .knownAllergens: return []
        case .eczema, .familyAllergy: return [Answer.no, Answer.yes, Answer.notSure]
        case .milkFeeding: return [Answer.breast, Answer.formula, Answer.mixed]
        case .headControl, .sits, .foodInterest: return [Answer.yes, Answer.no, Answer.notSure]
        }
    }

    public var inOnboarding: Bool { true }

    /// Задавать в онбординге, только если прикорм ещё не начали (ничего не отмечено в «Что малыш уже ест?»).
    public var onlyBeforeStart: Bool { self == .headControl || self == .sits || self == .foodInterest }
}

/// Ответы на вопросы профиля. Хранится как словарь ключ → значение (MULTI — значения через запятую).
/// Неизвестные ключи (вопросы из будущих версий) сохраняются как есть.
public struct ChildProfile: Hashable, Sendable {
    public let answers: [String: String]

    public init(_ answers: [String: String] = [:]) { self.answers = answers }

    public func single(_ q: ProfileQuestion) -> String? {
        guard let v = answers[q.key], !v.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return v
    }

    public func multi(_ q: ProfileQuestion) -> Set<String> {
        guard let v = answers[q.key] else { return [] }
        return Set(v.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
    }

    public func isAnswered(_ q: ProfileQuestion) -> Bool { single(q) != nil }

    /// Выбрать вариант (повторный выбор того же снимает ответ).
    public func toggleSingle(_ q: ProfileQuestion, _ code: String) -> ChildProfile {
        with(q, single(q) == code ? nil : code)
    }

    public func toggleMulti(_ q: ProfileQuestion, _ code: String) -> ChildProfile {
        var set = multi(q)
        if set.contains(code) { set.remove(code) } else { set.insert(code) }
        let joined = set.sorted().joined(separator: ",")
        return with(q, joined.isEmpty ? nil : joined)
    }

    private func with(_ q: ProfileQuestion, _ value: String?) -> ChildProfile {
        var a = answers
        a[q.key] = value
        return ChildProfile(a)
    }

    // Удобные доступы для правил.
    public var knownAllergens: Set<String> { multi(.knownAllergens) }
    public var hasEczema: Bool { single(.eczema) == ProfileQuestion.Answer.yes }
    public var familyAllergy: Bool { single(.familyAllergy) == ProfileQuestion.Answer.yes }

    /// Итог онбординга (`FeedingReadiness.Result.rawValue`); nil — онбординг по старой схеме.
    public var feedingReadiness: String? { answers[ChildProfile.readinessKey] }
    public func withReadiness(_ code: String) -> ChildProfile {
        var a = answers; a[ChildProfile.readinessKey] = code; return ChildProfile(a)
    }
    public func without(_ qs: ProfileQuestion...) -> ChildProfile {
        var a = answers; for q in qs { a[q.key] = nil }; return ChildProfile(a)
    }
    public func with(_ q: ProfileQuestion, answer: String) -> ChildProfile { with(q, answer) }
    public static let readinessKey = "feeding_readiness"

    public func toMap() -> [String: String] { answers }
    public static func fromMap(_ map: [String: String]) -> ChildProfile { ChildProfile(map) }
}

import Foundation
