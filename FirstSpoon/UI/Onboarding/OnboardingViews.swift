import SwiftUI
import Observation
import FirstSpoonCore

/// Шаги онбординга: сначала основные поля ребёнка, затем вопросы профиля из реестра `ProfileQuestion`.
/// Новый вопрос в реестре сам становится шагом.
enum OnboardingStep: Hashable {
    case name, sex, birthDate
    case question(ProfileQuestion)

    static let all: [OnboardingStep] = [.name, .sex, .birthDate] + ProfileQuestion.allCases.filter(\.inOnboarding).map { .question($0) }

    /// Шаги, которые можно пропустить без ответа.
    var skippable: Bool {
        switch self {
        case .sex: return true
        case .question(let q): return q.kind == .single
        default: return false
        }
    }

    var texts: (String, String) {
        switch self {
        case .name: return (L.s("onb_name_title"), L.s("onb_name_subtitle"))
        case .sex: return (L.s("onb_sex_title"), L.s("onb_sex_subtitle"))
        case .birthDate: return (L.s("onb_birth_title"), L.s("onb_birth_subtitle"))
        case .question(let q): return (Labels.title(q), Labels.subtitle(q))
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
    var saving = false

    @ObservationIgnored private let diary: DiaryRepository
    @ObservationIgnored private let store: OnboardingStore
    let allergens: [Allergen]

    init(diary: DiaryRepository, catalog: CatalogRepository, store: OnboardingStore) {
        self.diary = diary
        self.store = store
        allergens = catalog.base.allergens
        if let child = diary.activeChild {
            childId = child.id; name = child.name; sex = child.sex; birthDate = child.birthDate; profile = child.profile
        }
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
        case .question(let q): return profile.isAnswered(q)
        default: return true
        }
    }

    func setSex(_ v: Sex) { sex = sex == v ? nil : v }

    /// Сохраняет ребёнка и отмечает онбординг пройденным — корневой граф сам переключится на главный экран.
    func finish() {
        guard !saving, canContinue(.name) else { return }
        saving = true
        do {
            let id = try diary.saveChild(id: childId, name: name, birthDate: birthDate, sex: sex, profile: profile)
            diary.selectChild(id)
            store.set(true)
        } catch {
            saving = false
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
    @State private var path: [Int] = []

    var body: some View {
        NavigationStack(path: $path) {
            OnboardingStepView(model: model, index: 0, path: $path)
                .navigationDestination(for: Int.self) { OnboardingStepView(model: model, index: $0, path: $path) }
        }
    }
}

/// Один шаг: прогресс, крупный вопрос, ответ, «Далее» внизу.
struct OnboardingStepView: View {
    @Bindable var model: OnboardingViewModel
    let index: Int
    @Binding var path: [Int]
    @Environment(\.dismiss) private var dismiss

    private var step: OnboardingStep { OnboardingStep.all[index] }
    private var isLast: Bool { index == OnboardingStep.all.count - 1 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                StepIndicator(current: index, total: OnboardingStep.all.count)
                ScreenTitle(text: step.texts.0, subtitle: step.texts.1)
                content
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
            if step.skippable && !model.hasAnswer(step) {
                ToolbarItem(placement: .primaryAction) { Button(L.s("onb_skip"), action: next) }
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch step {
        case .name:
            AppTextField(text: Binding(get: { model.name }, set: { model.name = String($0.prefix(40)) }),
                         placeholder: L.s("child_name"), capitalization: .words,
                         onSubmit: { if model.canContinue(step) { next() } })
        case .sex:
            BigTiles(options: Sex.allCases, selected: model.sex, label: Labels.label, emoji: Labels.emoji) { model.setSex($0) }
        case .birthDate:
            BirthDatePicker(value: $model.birthDate, name: model.name)
        case .question(let q):
            QuestionInput(question: q, profile: model.profile, allergens: model.allergens,
                          onSingle: { model.profile = model.profile.toggleSingle(q, $0) },
                          onMulti: { model.profile = model.profile.toggleMulti(q, $0) })
        }
    }

    private func next() {
        if isLast { model.finish() } else { path.append(index + 1) }
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
