import SwiftUI
import Observation
import FirstSpoonCore

/// Шаги онбординга: основные поля ребёнка, «что уже ест», вопросы профиля из реестра `ProfileQuestion`, итог.
/// Новый вопрос в реестре сам становится шагом. Порт Android `OnboardingStep`.
enum OnboardingStep: Hashable {
    case name, sex, birthDate
    /// «Какие продукты малыш уже ест?» — основные продукты, сохраняются отметкой «Уже введён».
    case knownFoods
    case question(ProfileQuestion)
    /// Итог: готов ли малыш к прикорму (`FeedingReadiness`).
    case result

    /// Все возможные шаги.
    static let all: [OnboardingStep] =
        [.name, .sex, .birthDate, .knownFoods] + ProfileQuestion.allCases.filter(\.inOnboarding).map { .question($0) } + [.result]

    /// Шаги для текущих ответов (развилка, Android docs/product-rules.md «Онбординг»): если малыш уже что-то ест,
    /// вопросы о навыках и интересе к еде не задаём.
    static func forAnswers(alreadyEating: Bool) -> [OnboardingStep] {
        all.filter { step in
            if case .question(let q) = step, q.onlyBeforeStart, alreadyEating { return false }
            return true
        }
    }

    /// Ключ шага — тот же, что в Android (маршрут и параметр `step` события `onboarding_step`).
    var key: String {
        switch self {
        case .name: return "name"
        case .sex: return "sex"
        case .birthDate: return "birth"
        case .knownFoods: return "known_foods"
        case .question(let q): return "q_" + q.key
        case .result: return "result"
        }
    }

    /// Шаги, которые можно пропустить без ответа.
    var skippable: Bool {
        switch self {
        case .sex, .knownFoods: return true
        case .question(let q): return q.kind == .single
        default: return false
        }
    }

    var texts: (String, String) {
        switch self {
        case .name: return (L.s("onb_name_title"), L.s("onb_name_subtitle"))
        case .sex: return (L.s("onb_sex_title"), L.s("onb_sex_subtitle"))
        case .birthDate: return (L.s("onb_birth_title"), L.s("onb_birth_subtitle"))
        case .knownFoods: return ("", L.s("onb_known_subtitle"))
        case .question(let q): return (Labels.title(q), Labels.subtitle(q))
        case .result: return ("", "")
        }
    }
}

/// Общий VM всех шагов. Если ребёнок уже есть (повторный онбординг) — ответы предзаполняются и сохраняются в него.
@MainActor @Observable
final class OnboardingViewModel {
    var childId: String?
    var name = ""
    var sex: Sex?
    var birthDate: LocalDate?
    var profile = ChildProfile()
    /// Отмеченные основные продукты (`FeedingReadiness.knownFoodsChoices`).
    var knownFoods: Set<String> = []
    /// Что было отмечено «Уже введён» до онбординга (повторный онбординг) — чтобы снять снятые.
    private(set) var knownBefore: Set<String> = []
    /// Продукты, которые уже есть в дневнике (пробы): отмечены сами, отметку «Уже введён» им не ставим и снять нельзя.
    private(set) var inDiary: Set<String> = []
    /// История, которая сохраняется при снятии всех видимых отметок.
    private var hasOtherFoodHistory = false
    var saveFailed = false
    var saving = false

    @ObservationIgnored private let diary: DiaryRepository
    @ObservationIgnored private let store: OnboardingStore
    let allergens: [Allergen]
    /// Основные продукты для шага «уже ест»: id → название.
    let knownFoodChoices: [(String, String)]
    /// Фото ребёнка (по желанию, на шаге с именем).
    let photo: PhotoDraft

    init(diary: DiaryRepository, catalog: CatalogRepository, store: OnboardingStore) {
        self.diary = diary
        self.store = store
        allergens = catalog.base.allergens
        let products = catalog.base.productsById
        let blocked = Set(diary.marks.filter { $0.value == .allergy || $0.value == .excluded }.keys)
        knownFoodChoices = FeedingReadiness.knownFoodsChoices.filter { !blocked.contains($0) }
            .compactMap { id in products[id].map { (id, $0.name) } }
        let child = diary.activeChild
        if let child {
            childId = child.id; name = child.name; sex = child.sex; birthDate = child.birthDate; profile = child.profile
            let choices = Set(FeedingReadiness.knownFoodsChoices)
            let allKnown = Set(diary.marks.filter { $0.value == .known }.keys)
            let before = allKnown.intersection(choices)
            let fromDiary = Set(diary.entries.map(\.productId)).intersection(choices)
            knownBefore = before
            inDiary = fromDiary
            hasOtherFoodHistory = !diary.entries.isEmpty || !allKnown.isSubset(of: choices)
            knownFoods = before.union(fromDiary.subtracting(blocked))
        }
        photo = PhotoDraft(store: diary.photos, original: child?.photo)
    }

    /// Для развилки: уже ест — по отметкам в шаге или по дневнику.
    var alreadyEating: Bool { !knownFoods.isEmpty || hasOtherFoodHistory }
    var steps: [OnboardingStep] { OnboardingStep.forAnswers(alreadyEating: alreadyEating) }
    func next(after step: OnboardingStep) -> OnboardingStep? {
        guard let i = steps.firstIndex(of: step), i + 1 < steps.count else { return nil }
        return steps[i + 1]
    }

    func readiness(today: LocalDate = .today()) -> FeedingReadiness.Result {
        if alreadyEating { return .alreadyStarted }
        return FeedingReadiness.evaluate(birthDate: birthDate, profile: profile, knownFoods: [], today: today)
    }

    /// Обязательны имя и дата рождения (от неё зависит фильтр по возрасту), остальное можно пропустить.
    func canContinue(_ step: OnboardingStep) -> Bool {
        switch step {
        case .name: return !name.trimmingCharacters(in: .whitespaces).isEmpty
        case .birthDate: return birthDate != nil
        default: return true
        }
    }

    func hasAnswer(_ step: OnboardingStep) -> Bool {
        switch step {
        case .sex: return sex != nil
        case .knownFoods: return !knownFoods.isEmpty
        case .question(let q): return profile.isAnswered(q)
        default: return true
        }
    }

    func setSex(_ v: Sex) {
        sex = sex == v ? nil : v
        Analytics.track(.onboardingOptionChanged(option: .sex(v), selected: sex == v))
    }

    func toggleSingle(_ question: ProfileQuestion, _ code: String) {
        profile = profile.toggleSingle(question, code)
        if question == .milkFeeding, let choice = AnalyticsEvent.OnboardingOption.MilkFeeding(rawValue: code) {
            Analytics.track(.onboardingOptionChanged(option: .milkFeeding(choice), selected: profile.single(question) == code))
        }
    }

    func toggleKnownFood(_ id: String) {
        // Продукт из дневника снять нельзя — его пробы уже записаны.
        guard !inDiary.contains(id), knownFoodChoices.contains(where: { $0.0 == id }) else { return }
        if knownFoods.contains(id) { knownFoods.remove(id) } else { knownFoods.insert(id) }
        Analytics.track(.onboardingOptionChanged(option: .knownFood(id), selected: knownFoods.contains(id)))
    }

    /// Шаг показан — воронка онбординга.
    func onStepShown(_ step: OnboardingStep) { Analytics.track(.onboardingStep(step: step.key)) }

    /// Сохраняет ребёнка и отмечает онбординг пройденным — корневой граф сам переключится на главный экран.
    func finish() {
        guard !saving, canContinue(.name) else { return }
        saving = true
        saveFailed = false
        do {
            let readiness = readiness()
            // Уже ест — вопросы готовности не задавали: старые ответы на них не храним.
            let base = alreadyEating ? profile.without(.headControl, .sits, .foodInterest) : profile
            let id = try diary.saveChild(id: childId, name: name, birthDate: birthDate, sex: sex,
                                         profile: base.withReadiness(readiness.rawValue), photo: .some(photo.current),
                                         addKnown: knownFoods.subtracting(inDiary).subtracting(knownBefore),
                                         removeKnown: knownBefore.subtracting(knownFoods))
            _ = photo.commit()
            diary.selectChild(id)
            Analytics.track(.onboardingCompleted(readiness: readiness, knownFoods: knownFoods.count))
            store.set(true)
        } catch {
            saving = false
            saveFailed = true
        }
    }
}

struct OnboardingFlow: View {
    @Environment(AppContainer.self) private var app

    var body: some View {
        OnboardingStack(model: OnboardingViewModel(diary: app.diary, catalog: app.catalog, store: app.onboarding))
    }
}

/// Модель создаётся один раз (`@State` хранит первое значение), шаги — в стеке навигации.
private struct OnboardingStack: View {
    @State var model: OnboardingViewModel
    @State private var path: [OnboardingStep] = []

    var body: some View {
        NavigationStack(path: $path) {
            OnboardingStepView(model: model, step: OnboardingStep.all[0], path: $path)
                .navigationDestination(for: OnboardingStep.self) { OnboardingStepView(model: model, step: $0, path: $path) }
        }
        .alert(L.s("error_generic"), isPresented: $model.saveFailed) {
            Button(L.s("retry")) { model.finish() }
            Button(L.s("cancel"), role: .cancel) {}
        }
    }
}

/// Один шаг: прогресс, крупный вопрос, ответ, «Далее» внизу.
struct OnboardingStepView: View {
    @Bindable var model: OnboardingViewModel
    let step: OnboardingStep
    @Binding var path: [OnboardingStep]
    @Environment(AppContainer.self) private var app

    private var isLast: Bool { step == .result }
    private var isFirst: Bool { step == OnboardingStep.all[0] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if step == .result {
                    ReadinessResult(model: model)
                } else {
                    let steps = model.steps
                    StepIndicator(current: max(0, steps.firstIndex(of: step) ?? 0), total: steps.count - 1)
                    ScreenTitle(text: title, subtitle: step.texts.1)
                    content
                }
            }
            .padding(.horizontal, screenPadding)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .bottomAction {
            AppButton(L.s(isLast ? "onb_done" : "onb_next"), enabled: model.canContinue(step), loading: model.saving, action: next)
                .padding(.horizontal, screenPadding)
                .padding(.vertical, 12)
        }
        .appScreen()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // «Назад» с первого шага — на приветствие: только гость при первом знакомстве (`canReturnToWelcome`).
            if isFirst && app.canReturnToWelcome {
                ToolbarItem(placement: .topBarLeading) {
                    Button { app.auth.returnToWelcome() } label: {
                        HStack(spacing: 4) { Image("ic_chevron_left").fontWeight(.semibold); Text(L.s("back")) }
                    }
                }
            }
            if step.skippable && !model.hasAnswer(step) {
                ToolbarItem(placement: .primaryAction) { Button(L.s("onb_skip"), action: next) }
            }
        }
        .onAppear { model.onStepShown(step) }
    }

    private var title: String {
        guard step == .knownFoods else { return step.texts.0 }
        let n = model.name.trimmingCharacters(in: .whitespaces)
        return L.s("onb_known_title", n.isEmpty ? L.s("default_child_name").lowercased(with: UiLocale.locale) : n)
    }

    @ViewBuilder private var content: some View {
        switch step {
        case .name:
            AppTextField(text: Binding(get: { model.name }, set: { model.name = String($0.prefix(40)) }),
                         placeholder: L.s("child_name"), capitalization: .words,
                         onSubmit: { if model.canContinue(step) { next() } })
            PhotoPickerField(draft: model.photo, placeholder: AnyView(ChildAvatarPlaceholder(sex: model.sex, size: 96)))
        case .sex:
            BigTiles(options: Sex.allCases, selected: model.sex, label: Labels.label, emoji: Labels.emoji) { model.setSex($0) }
        case .birthDate:
            BirthDatePicker(value: $model.birthDate, name: model.name)
        case .knownFoods:
            FlowLayout(spacing: 8) {
                ForEach(model.knownFoodChoices, id: \.0) { id, label in
                    AppChip(label: label, selected: model.knownFoods.contains(id)) { model.toggleKnownFood(id) }
                }
            }
        case .question(let q):
            QuestionInput(question: q, profile: model.profile, allergens: model.allergens,
                          onSingle: { model.toggleSingle(q, $0) },
                          onMulti: { model.profile = model.profile.toggleMulti(q, $0) })
        case .result:
            EmptyView()
        }
    }

    private func next() {
        if isLast { model.finish() } else if let n = model.next(after: step) { path.append(n) }
    }
}

/// Итог онбординга (Android docs/product-rules.md «Онбординг»): готов ли малыш к прикорму. Имя — как есть
/// (именительный), род — по полу; без имени или пола — нейтральная фраза.
private struct ReadinessResult: View {
    let model: OnboardingViewModel

    var body: some View {
        let (emoji, title, text) = content
        VStack(alignment: .leading, spacing: 16) {
            Text(emoji).font(.system(size: 56))
            ScreenTitle(text: title, subtitle: nil)
            Text(text).font(AppFont.bodyLarge).foregroundStyle(AppColors.inkMuted).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 48)
    }

    private var name: String { model.name.trimmingCharacters(in: .whitespaces) }

    private var content: (String, String, String) {
        switch model.readiness() {
        case .ready:
            return ("🎉", byGender("onb_result_ready_m", "onb_result_ready_f", "onb_result_ready_n"), L.s("onb_result_ready_text"))
        case .notYet:
            return ("🌱", byGender("onb_result_not_yet_m", "onb_result_not_yet_f", "onb_result_not_yet_n"), L.s("onb_result_not_yet_text"))
        case .tooEarly:
            return ("🌱", L.s("onb_result_too_early_title"), L.s("onb_result_too_early_text"))
        case .checkWithDoctor:
            return ("👀", name.isEmpty ? L.s("onb_result_check_title_n") : L.s("onb_result_check_title", name), L.s("onb_result_check_text"))
        case .alreadyStarted:
            return ("🥄", name.isEmpty ? L.s("onb_result_started_title_n") : L.s("onb_result_started_title", name), L.s("onb_result_started_text"))
        }
    }

    /// Заголовок с именем по роду; без имени или пола — нейтральный вариант.
    private func byGender(_ male: String, _ female: String, _ neutral: String) -> String {
        guard !name.isEmpty, let sex = model.sex else { return L.s(neutral) }
        return L.s(sex == .male ? male : female, name)
    }
}

/// Ответ на вопрос профиля по его типу: SINGLE — плитки/строки, MULTI — чипы. Используется и в редактировании ребёнка.
struct QuestionInput: View {
    let question: ProfileQuestion
    let profile: ChildProfile
    let allergens: [Allergen]
    let onSingle: (String) -> Void
    let onMulti: (String) -> Void

    var body: some View {
        switch question.kind {
        case .single:
            BigTiles(options: question.options, selected: profile.single(question),
                     label: { Labels.option($0).0 }, emoji: { Labels.option($0).1 }, onSelect: onSingle)
        case .multi:
            FlowLayout(spacing: 8) {
                ForEach(Labels.multiOptions(question, allergens: allergens), id: \.0) { code, label in
                    AppChip(label: label, selected: profile.multi(question).contains(code)) { onMulti(code) }
                }
            }
        }
    }
}

/// Два варианта — крупные плитки в ряд; больше — строки на всю ширину.
struct BigTiles<T: Hashable>: View {
    let options: [T]
    let selected: T?
    let label: (T) -> String
    let emoji: (T) -> String
    let onSelect: (T) -> Void

    var body: some View {
        if options.count <= 2 {
            HStack(spacing: 12) {
                ForEach(options, id: \.self) { o in
                    ChoiceTile(label: label(o), selected: selected == o, emoji: emoji(o)) { onSelect(o) }.frame(height: 150)
                }
            }
        } else {
            VStack(spacing: 12) {
                ForEach(options, id: \.self) { o in
                    ChoiceRow(label: label(o), selected: selected == o, emoji: emoji(o)) { onSelect(o) }
                }
            }
        }
    }
}

/// Встроенный календарь + подпись с возрастом. Будущие даты недоступны; открывается на полгода назад.
struct BirthDatePicker: View {
    @Binding var value: LocalDate?
    let name: String

    var body: some View {
        let today = LocalDate.today()
        VStack(alignment: .leading, spacing: 16) {
            if let value {
                Text(Labels.ageText(Child(id: "", name: name, birthDate: value)))
                    .font(AppFont.titleLarge).foregroundStyle(AppColors.primary)
            }
            AppCard(padding: EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12)) {
                DatePicker("", selection: Binding(
                    get: { (value ?? today.minusMonths(6)).toDate() },
                    set: { value = LocalDate.today($0) }),
                           in: today.minusMonths(48).toDate()...today.toDate(), displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .environment(\.locale, UiLocale.locale)
                    .tint(AppColors.primary)
            }
        }
        .onAppear {
            // Календарь всегда показывает выбранную дату — сохраняем её сразу, чтобы «Далее» было доступно только после выбора.
        }
    }
}

extension LocalDate {
    /// Полдень этой даты в часовом поясе устройства — для системных пикеров.
    func toDate(calendar: Calendar = .current) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? Date()
    }
}
