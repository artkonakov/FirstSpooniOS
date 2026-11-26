import SwiftUI
import Observation
import FirstSpoonCore

/// Черновик пробы: новая (`entryId` = nil) или редактирование существующей.
@MainActor @Observable
final class EntryViewModel {
    var entryId: String?
    var date = LocalDate.today()
    var time = LocalDateTime.now().time
    var productId: String?
    var meal: Meal?
    var amount: Amount? = .tsp
    var reaction: Reaction?
    var symptoms: Set<Symptom> = []
    var note = ""
    var saving = false
    /// Фото пробы (черновик: в пробу попадают только при «Сохранить»).
    let photos: EntryPhotosDraft

    @ObservationIgnored private let diary: DiaryRepository

    init(diary: DiaryRepository, entryId: String?, productId: String?) {
        self.diary = diary
        self.productId = productId
        let existing = entryId.flatMap { diary.getEntry($0) }
        if let e = existing {
            self.entryId = e.id; date = e.date; time = e.time ?? LocalTime(12, 0); self.productId = e.productId
            meal = e.meal; amount = e.amount; reaction = e.reaction == .unknown ? nil : e.reaction
            symptoms = Set(e.symptoms); note = e.note ?? ""
        }
        photos = EntryPhotosDraft(store: diary.photos, original: existing?.photos ?? [])
    }

    var isEditing: Bool { entryId != nil }

    /// Повторный тап по выбранному варианту снимает выбор.
    func toggleMeal(_ m: Meal) { meal = meal == m ? nil : m }
    func toggleReaction(_ r: Reaction) { reaction = reaction == r ? nil : r }
    func toggleSymptom(_ s: Symptom) { if symptoms.contains(s) { symptoms.remove(s) } else { symptoms.insert(s) } }

    /// true — сохранено, экран закрывается.
    func save() -> Bool {
        guard let productId, !saving, !photos.processing else { return false }
        saving = true
        let r = reaction ?? .unknown
        // Симптомы имеют смысл только при «Сомнительно»/«Плохо»: при смене реакции не храним старые.
        let s = Labels.asksSymptoms(r) ? Symptom.allCases.filter(symptoms.contains) : []
        let files = photos.photos
        do {
            if let entryId {
                try diary.updateEntry(DiaryEntry(id: entryId, productId: productId, date: date, time: time, meal: meal,
                                                 amount: amount, reaction: r, symptoms: s, note: note, photos: files))
            } else {
                try diary.addEntry(productId: productId, date: date, time: time, meal: meal, amount: amount,
                                   reaction: r, symptoms: s, note: note, photos: files)
            }
            // По событию на каждое новое фото — только сохранённые (брошенные черновики не считаются).
            for _ in 0..<photos.commit() { Analytics.track(.entryPhotoAdded) }
            return true
        } catch {
            saving = false
            return false
        }
    }

    func delete() {
        guard let entryId else { return }
        try? diary.deleteEntry(entryId)
    }
}

/// Форма пробы: новая или редактирование существующей (тот же экран).
struct EntryView: View {
    @Environment(AppContainer.self) private var app
    @Environment(Navigator.self) private var nav
    let entryId: String?
    let productId: String?
    @State private var model: EntryViewModel?
    @State private var pickProduct = false
    @State private var pickDate = false
    @State private var confirmDelete = false

    var body: some View {
        ZStack {
            if let model { form(model) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .bottomAction {
            if let model {
                AppButton(L.s(model.isEditing ? "entry_save_changes" : "entry_save"),
                          enabled: model.productId != nil && !model.photos.processing, loading: model.saving || model.photos.processing) {
                    if model.save() { nav.back() }
                }
                .padding(.horizontal, screenPadding)
                .padding(.vertical, 12)
            }
        }
        .appScreen()
        .navigationTitle(L.s(entryId != nil ? "entry_edit_title" : "entry_title"))
        .onAppear {
            guard model == nil else { return }
            let m = EntryViewModel(diary: app.diary, entryId: entryId, productId: productId)
            #if DEBUG
            // Скриншоты (`-demo_screen entry`): дневное время и «Обед», как в Android, а не текущее время.
            if DemoScreen.current == "entry" && entryId == nil { m.time = LocalTime(12, 30); m.meal = .lunch }
            #endif
            model = m
        }
        // Ушли без «Сохранить» — снимки, выбранные на этом экране, не нужны.
        .onDisappear { model?.photos.discard() }
        .sheet(isPresented: $pickProduct) {
            ProductPicker { id in model?.productId = id; pickProduct = false } onClose: { pickProduct = false }
        }
        .sheet(isPresented: $pickDate) {
            if let model { DateTimeSheet(date: Bindable(model).date, time: Bindable(model).time) { pickDate = false } }
        }
        .alert(L.s("entry_delete_confirm"), isPresented: $confirmDelete) {
            Button(L.s("delete"), role: .destructive) { model?.delete(); nav.back() }
            Button(L.s("cancel"), role: .cancel) {}
        }
    }

    private func form(_ model: EntryViewModel) -> some View {
        @Bindable var model = model
        let product = model.productId.flatMap { app.catalog.catalog.productsById[$0] }
        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                section("entry_product") {
                    if let product {
                        ProductCard(productId: product.id, name: product.name) { pickProduct = true }
                    } else {
                        ActionRow(title: L.s("entry_product_pick"), titleColor: AppColors.inkMuted) { pickProduct = true }
                    }
                }
                section("entry_datetime") {
                    ActionRow(title: "\(dayText(model.date)), \(UiLocale.time(model.time))", icon: "ic_tab_diary") { pickDate = true }
                }
                section("entry_meal") {
                    TileGrid(items: Meal.allCases) { m in
                        ChoiceTile(label: Labels.label(m), selected: model.meal == m, emoji: Labels.emoji(m)) { model.toggleMeal(m) }
                    }
                }
                section("entry_amount") {
                    SegmentedControl(options: Amount.allCases, selected: model.amount, label: Labels.label) { model.amount = $0 }
                }
                section("entry_reaction") {
                    TileGrid(items: Labels.reactionChoices) { r in
                        ChoiceTile(label: Labels.label(r), selected: model.reaction == r, emoji: Labels.emoji(r)) { model.toggleReaction(r) }
                    }
                }
                if Labels.asksSymptoms(model.reaction) {
                    section("entry_symptoms") {
                        FlowLayout(spacing: 8) {
                            ForEach(Symptom.allCases, id: \.self) { s in
                                AppChip(label: Labels.label(s), selected: model.symptoms.contains(s)) { model.toggleSymptom(s) }
                            }
                        }
                        Text(L.s("entry_photos_reaction_hint")).font(AppFont.bodyMedium).foregroundStyle(AppColors.inkMuted)
                            .padding(.leading, 6)
                    }
                }
                section(L.s("entry_note") + " " + L.s("entry_optional"), raw: true) {
                    AppTextField(text: Binding(get: { model.note }, set: { model.note = String($0.prefix(500)) }),
                                 placeholder: L.s("entry_note_hint"), multiline: true)
                }
                section(L.s("entry_photos") + " " + L.s("entry_optional"), raw: true) {
                    EntryPhotosSection(draft: model.photos)
                }
                if model.isEditing {
                    AppButton(L.s("entry_delete"), kind: .danger) { confirmDelete = true }.padding(.top, 12)
                }
            }
            .padding(.horizontal, screenPadding)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    /// `raw` — заголовок уже готовым текстом, иначе это ключ строки.
    private func section<C: View>(_ title: String, raw: Bool = false, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            FieldLabel(raw ? title : L.s(title))
            content()
        }
        .padding(.top, 8)
    }

    private func dayText(_ d: LocalDate) -> String {
        let today = LocalDate.today()
        if d == today { return L.s("entry_today") }
        if d == today.minusDays(1) { return L.s("entry_yesterday") }
        return UiLocale.dayMonthShort(d)
    }
}

/// Сетка 2 колонки из плиток выбора.
struct TileGrid<T: Hashable, Tile: View>: View {
    let items: [T]
    @ViewBuilder let tile: (T) -> Tile
    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            ForEach(items, id: \.self) { tile($0) }
        }
    }
}

/// Дата и время пробы. Будущее недоступно.
struct DateTimeSheet: View {
    @Binding var date: LocalDate
    @Binding var time: LocalTime
    let onDone: () -> Void

    var body: some View {
        let combined = Binding<Date>(
            get: { Calendar.current.date(from: DateComponents(year: date.year, month: date.month, day: date.day, hour: time.hour, minute: time.minute)) ?? Date() },
            set: { d in
                date = .today(d)
                let c = Calendar.current.dateComponents([.hour, .minute], from: d)
                time = LocalTime(c.hour ?? 12, c.minute ?? 0)
            })
        VStack(spacing: 16) {
            DatePicker("", selection: combined, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                .datePickerStyle(.graphical)
                .labelsHidden()
                .environment(\.locale, UiLocale.locale)
            AppButton(L.s("ok"), action: onDone)
        }
        .padding(screenPadding)
        .presentationDetents([.large])
        .presentationBackground(AppColors.background)
    }
}

/// Выбор продукта для пробы: каталог в режиме выбора; «+» создаёт свой продукт и сразу выбирает его.
private struct ProductPicker: View {
    let onPick: (String) -> Void
    let onClose: () -> Void
    @State private var nav = Navigator()
    @State private var state = CatalogViewState()

    var body: some View {
        NavigationStack(path: $nav.path) {
            CatalogView(state: state, pickMode: true, onBack: onClose, onPick: onPick)
                .navigationDestination(for: Route.self) { route in
                    if case .customProduct(let query) = route { CustomProductView(initialName: query, onCreated: onPick) }
                }
        }
        .environment(nav)
    }
}
