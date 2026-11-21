import Foundation
import FirstSpoonCore

/// Подписи и эмодзи перечислений из БД. Один источник для всех экранов (как `ui/common/Labels.kt`).
enum Labels {
    static func label(_ a: Amount) -> String {
        switch a {
        case .halfTsp: return L.s("amount_half_tsp")
        case .tsp: return L.s("amount_tsp")
        case .twoTsp: return L.s("amount_two_tsp")
        case .tbsp: return L.s("amount_tbsp")
        }
    }

    static func label(_ m: Meal) -> String { L.s("meal_\(m.rawValue)") }

    static func emoji(_ m: Meal) -> String {
        switch m {
        case .breakfast: return "🌅"
        case .lunch: return "☀️"
        case .dinner: return "🌙"
        case .snack: return "🍎"
        }
    }

    static func label(_ s: Symptom) -> String { L.s("symptom_\(s.rawValue)") }

    static func label(_ s: Sex) -> String { L.s(s == .male ? "sex_male" : "sex_female") }

    static func emoji(_ s: Sex) -> String { s == .male ? "👦" : "👧" }

    /// Четыре реакции, которые выбирает пользователь (`.unknown` — «не отмечено»).
    static let reactionChoices: [Reaction] = [.good, .none, .unsure, .reaction]

    static func label(_ r: Reaction) -> String {
        switch r {
        case .good: return L.s("reaction_good")
        case .none: return L.s("reaction_no_change")
        case .unsure: return L.s("reaction_unsure")
        case .reaction: return L.s("reaction_bad")
        case .unknown: return L.s("entry_not_marked")
        }
    }

    static func emoji(_ r: Reaction) -> String {
        switch r {
        case .good: return "😊"
        case .none: return "😐"
        case .unsure: return "🤔"
        case .reaction: return "😣"
        case .unknown: return "⏳"
        }
    }

    static func ageText(_ child: Child, today: LocalDate = .today()) -> String {
        guard let m = child.ageMonths(today) else { return L.s("age_unknown") }
        return m < 12 ? L.s("age_months", m) : L.s("age_years_months", m / 12, m % 12)
    }

    /// «Сегодня», «Вчера», «14 ноября» (+ год, если не текущий).
    static func dayTitle(_ date: LocalDate, today: LocalDate = .today(), withYear: Bool = true) -> String {
        if date == today { return L.s("entry_today") }
        if date == today.minusDays(1) { return L.s("entry_yesterday") }
        return withYear && date.year != today.year ? UiLocale.dayMonthYear(date) : UiLocale.dayMonth(date)
    }

    // Вопросы профиля: заголовок шага онбординга, пояснение, короткая подпись для профиля.
    static func title(_ q: ProfileQuestion) -> String {
        switch q {
        case .knownAllergens: return L.s("onb_allergens_title")
        case .eczema: return L.s("onb_eczema_title")
        case .familyAllergy: return L.s("onb_family_title")
        case .milkFeeding: return L.s("onb_feeding_title")
        case .headControl: return L.s("onb_head_title")
        case .sits: return L.s("onb_sits_title")
        }
    }

    static func subtitle(_ q: ProfileQuestion) -> String {
        switch q {
        case .knownAllergens: return L.s("onb_allergens_subtitle")
        case .eczema: return L.s("onb_eczema_subtitle")
        case .familyAllergy: return L.s("onb_family_subtitle")
        case .milkFeeding: return L.s("onb_feeding_subtitle")
        case .headControl: return L.s("onb_head_subtitle")
        case .sits: return L.s("onb_sits_subtitle")
        }
    }

    static func shortLabel(_ q: ProfileQuestion) -> String {
        switch q {
        case .knownAllergens: return L.s("child_allergens")
        case .eczema: return L.s("child_eczema")
        case .familyAllergy: return L.s("child_family_allergy")
        case .milkFeeding: return L.s("child_feeding")
        case .headControl: return L.s("child_head_control")
        case .sits: return L.s("child_sits")
        }
    }

    /// Подпись и эмодзи варианта ответа (SINGLE-вопросы).
    static func option(_ code: String) -> (String, String) {
        switch code {
        case ProfileQuestion.Answer.no: return (L.s("answer_no"), "🙂")
        case ProfileQuestion.Answer.yes: return (L.s("answer_yes"), "✋")
        case ProfileQuestion.Answer.notSure: return (L.s("answer_not_sure"), "🤷")
        case ProfileQuestion.Answer.breast: return (L.s("feeding_breast"), "🤱")
        case ProfileQuestion.Answer.formula: return (L.s("feeding_formula"), "🍼")
        case ProfileQuestion.Answer.mixed: return (L.s("feeding_mixed"), "🔄")
        default: return (L.s("answer_not_sure"), "•")
        }
    }

    /// Варианты MULTI-вопроса: пока единственный — аллергены каталога.
    static func multiOptions(_ q: ProfileQuestion, allergens: [Allergen]) -> [(String, String)] {
        q == .knownAllergens ? allergens.map { ($0.id, $0.name) } : []
    }

    /// Симптомы спрашиваем только при «Сомнительно» / «Плохо».
    static func asksSymptoms(_ r: Reaction?) -> Bool { r == .unsure || r == .reaction }
}
