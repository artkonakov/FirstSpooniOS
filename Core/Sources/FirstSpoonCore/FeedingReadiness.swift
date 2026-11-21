/// Готов ли малыш к прикорму — итог онбординга (Android docs/product-rules.md «Онбординг»). Чистая функция,
/// та же, что Android `domain/FeedingReadiness.kt`.
/// Признаки готовности — по базе знаний (`docs/complementary-feeding`, CF-01): держит голову, сидит с поддержкой.
/// Минимальный возраст — 6 месяцев (решение пользователя 2026-11-20; совпадает с минимальным возрастом продуктов каталога).
public enum FeedingReadiness {
    public enum Result: String, Sendable, CaseIterable {
        /// Уже что-то пробовали — прикорм идёт.
        case alreadyStarted = "started"
        /// Младше `minMonths` месяцев.
        case tooEarly = "too_early"
        /// Не держит голову или не сидит.
        case notYet = "not_yet"
        /// «Не уверены» или нет ответа про навыки.
        case checkWithDoctor = "check"
        /// `minMonths` месяцев и старше, навыки есть.
        case ready = "ready"
    }

    public static let minMonths = 6

    public static func evaluate(birthDate: LocalDate?, profile: ChildProfile, knownFoods: Set<String>, today: LocalDate) -> Result {
        if !knownFoods.isEmpty { return .alreadyStarted }
        if let months = Child(id: "", name: "", birthDate: birthDate).ageMonths(today), months < minMonths { return .tooEarly }
        let head = profile.single(.headControl)
        let sits = profile.single(.sits)
        if head == ProfileQuestion.Answer.no || sits == ProfileQuestion.Answer.no { return .notYet }
        if head != ProfileQuestion.Answer.yes || sits != ProfileQuestion.Answer.yes { return .checkWithDoctor }
        return .ready
    }

    /// Можно ли предлагать новые продукты (Android docs/product-rules.md «Новые продукты — только когда малыш готов»).
    /// Уже ест (пробы или отметки «Уже введён») — да. Нет ответов на вопросы готовности (старый онбординг) — да.
    /// Иначе — только `.ready`. Возраст считается на сегодня, поэтому «рано» само сменится на «готов»,
    /// когда малышу исполнится 6 месяцев (если навыки отмечены).
    public static func current(birthDate: LocalDate?, profile: ChildProfile, started: Bool, today: LocalDate) -> Result? {
        if started { return .alreadyStarted }
        let asked = profile.isAnswered(.headControl) || profile.isAnswered(.sits) || profile.feedingReadiness != nil
        guard asked else { return nil }
        return evaluate(birthDate: birthDate, profile: profile, knownFoods: [], today: today)
    }

    public static func canOfferNewFoods(_ r: Result?) -> Bool {
        r == nil || r == .alreadyStarted || r == .ready
    }

    /// Начал ли малыш прикорм: есть пробы или отметки «Уже введён».
    public static func started(entries: [DiaryEntry], marks: [String: ProductMark]) -> Bool {
        !entries.isEmpty || marks.values.contains(.known)
    }

    /// Основные продукты для «Какие продукты малыш уже ест?» — не весь каталог, остальное отмечают потом в «Продуктах».
    /// Порядок = порядок чипов.
    public static let knownFoodsChoices = [
        "zucchini", "broccoli", "cauliflower", "pumpkin", "carrot", "potato",
        "buckwheat-groats", "rice", "oat-groats", "corn-grits",
        "apple", "pear", "banana",
        "beef", "turkey", "rabbit", "chicken",
        "yogurt", "egg-yolk",
    ]
}
