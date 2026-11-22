import SwiftUI
import FirstSpoonCore

/// Дети и вход в настройки. Аккаунт, выход и удаление — на экране настроек.
/// Подписка «Плюс» на iOS пока не подключена (StoreKit — следующий этап), карточку не показываем.
struct ProfileView: View {
    @Environment(AppContainer.self) private var app
    @Environment(Navigator.self) private var nav
    @State private var exported: URL?
    @State private var exportFailed = false
    @State private var askPhotos = false
    /// Последний выбор «Фото в отчёте» (по умолчанию «При реакции»).
    @AppStorage("export_photos") private var photoChoice = DiaryPdfExporter.PhotoMode.reactions.rawValue

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(L.s("profile_children"))
                ForEach(app.diary.children) { child in
                    ChildCard(child: child, active: child.id == app.diary.activeChild?.id,
                              onTap: { app.diary.selectChild(child.id) }, onEdit: { nav.open(.child(child.id)) })
                }
                AppButton(L.s("child_add"), kind: .soft, icon: "ic_plus") { nav.open(.child(nil)) }
                Spacer().frame(height: 12)
                if app.diary.activeChild != nil {
                    ActionRow(title: L.s("export_row"), icon: "ic_document") {
                        // Есть фото проб — сначала спрашиваем, какие класть в отчёт; нет — сразу без фото.
                        if app.diary.entries.contains(where: { !$0.photos.isEmpty }) { askPhotos = true } else { exportDiary(.none) }
                    }
                }
                ActionRow(title: L.s("settings"), icon: "ic_settings") { nav.open(.settings) }
            }
            .padding(.horizontal, screenPadding)
            .padding(.bottom, 24)
        }
        .appScreen()
        .navigationTitle(L.s("profile_title"))
        .sheet(item: $exported) { ShareSheet(items: [$0]).ignoresSafeArea() }
        .sheet(isPresented: $askPhotos) {
            ExportPhotosSheet(choice: $photoChoice) { mode in
                askPhotos = false
                // Лист «Поделиться» — после того как закроется этот.
                Task { try? await Task.sleep(for: .milliseconds(450)); exportDiary(mode) }
            }
            .presentationDetents([.medium, .large])
            .presentationBackground(AppColors.background)
        }
        .alert(L.s("export_failed"), isPresented: $exportFailed) { Button(L.s("ok"), role: .cancel) {} }
    }

    /// PDF дневника активного ребёнка → системный лист «Поделиться» (в нём же «Сохранить в Файлы»).
    private func exportDiary(_ mode: DiaryPdfExporter.PhotoMode) {
        guard let child = app.diary.activeChild else { return }
        let input = DiaryPdfExporter.Input(child: child, entries: app.diary.entries, marks: app.diary.marks,
                                           catalog: app.catalog.catalog, today: .today(), photoMode: mode, photos: app.photos)
        do {
            exported = try DiaryPdfExporter.export(input)
            Analytics.track(.diaryExported(photos: mode.rawValue))
        } catch {
            exportFailed = true
        }
    }
}

/// Системный лист «Поделиться» (UIActivityViewController): отправить, сохранить в Файлы, распечатать.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

/// Карточка ребёнка: тап — сделать активным (фиолетовая рамка), карандаш — редактировать.
private struct ChildCard: View {
    let child: Child
    let active: Bool
    let onTap: () -> Void
    let onEdit: () -> Void
    var body: some View {
        AppCard(padding: EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16), selected: active, onTap: onTap) {
            HStack(spacing: 16) {
                ChildAvatar(child: child)
                VStack(alignment: .leading, spacing: 4) {
                    Text(child.name).font(AppFont.titleMedium).foregroundStyle(AppColors.ink)
                    Text(Labels.ageText(child)).font(AppFont.bodyMedium).foregroundStyle(AppColors.inkMuted)
                }
                Spacer()
                Button(action: onEdit) {
                    Image("ic_edit").font(.system(size: 20, weight: .semibold)).foregroundStyle(AppColors.inkMuted)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L.s("child_edit_title"))
            }
        }
    }
}

/// Новый ребёнок (`childId` = nil) или редактирование: имя, дата рождения, пол, вопросы профиля, удаление.
struct ChildEditView: View {
    @Environment(AppContainer.self) private var app
    @Environment(Navigator.self) private var nav
    let childId: String?
    @State private var loaded = false
    @State private var name = ""
    @State private var birthDate: LocalDate?
    @State private var sex: Sex?
    @State private var profile = ChildProfile()
    @State private var pickDate = false
    @State private var confirmDelete = false
    @State private var photo: PhotoDraft?

    var body: some View {
        ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let photo {
                        PhotoPickerField(draft: photo, placeholder: AnyView(ChildAvatarPlaceholder(sex: sex, size: 96)))
                            .padding(.top, 8)
                    }
                    FieldLabel(L.s("child_name")).padding(.top, 8)
                    AppTextField(text: Binding(get: { name }, set: { name = String($0.prefix(40)) }),
                                 placeholder: L.s("child_name"), capitalization: .words)
                    FieldLabel(L.s("child_birth_date")).padding(.top, 8)
                    ActionRow(title: birthDate.map { UiLocale.dayMonthYear($0) } ?? L.s("child_birth_date_pick"),
                              value: birthDate.map { Labels.ageText(Child(id: "", name: name, birthDate: $0)) },
                              icon: "ic_tab_diary") { pickDate = true }
                    FieldLabel(L.s("child_sex")).padding(.top, 8)
                    SegmentedControl(options: Sex.allCases, selected: sex, label: Labels.label) { sex = sex == $0 ? nil : $0 }
                    ForEach(ProfileQuestion.allCases, id: \.self) { q in
                        FieldLabel(Labels.shortLabel(q)).padding(.top, 12)
                        QuestionInput(question: q, profile: profile, allergens: app.catalog.base.allergens,
                                      onSingle: { profile = profile.toggleSingle(q, $0) },
                                      onMulti: { profile = profile.toggleMulti(q, $0) })
                    }
                    if childId != nil && app.diary.children.count > 1 {
                        AppButton(L.s("child_delete"), kind: .danger) { confirmDelete = true }.padding(.top, 16)
                    }
                }
                .padding(.horizontal, screenPadding)
                .padding(.bottom, 24)
            }
        .scrollDismissesKeyboard(.interactively)
        .bottomAction {
            AppButton(L.s("save"), enabled: !name.trimmingCharacters(in: .whitespaces).isEmpty) {
                let newPhoto = photo?.commit()
                if (try? app.diary.saveChild(id: childId, name: name, birthDate: birthDate, sex: sex, profile: profile,
                                             photo: .some(newPhoto))) != nil { nav.back() }
            }
            .padding(.horizontal, screenPadding)
            .padding(.vertical, 12)
        }
        .appScreen()
        .navigationTitle(L.s(childId == nil ? "child_new_title" : "child_edit_title"))
        .onAppear {
            guard !loaded else { return }
            loaded = true
            let existing = childId.flatMap { app.diary.getChild($0) }
            if let c = existing {
                name = c.name; birthDate = c.birthDate; sex = c.sex; profile = c.profile
            }
            photo = PhotoDraft(store: app.photos, original: existing?.photo)
        }
        // Ушли без «Сохранить» — выбранные здесь снимки не нужны.
        .onDisappear { photo?.discard() }
        .sheet(isPresented: $pickDate) {
            VStack(spacing: 16) {
                BirthDatePicker(value: $birthDate, name: name)
                AppButton(L.s("ok")) { pickDate = false }
            }
            .padding(screenPadding)
            .presentationDetents([.large])
            .presentationBackground(AppColors.background)
        }
        .alert(L.s("child_delete_confirm", childName(name, sex: sex, case: .genitive, fallback: "child_profile_fallback")), isPresented: $confirmDelete) {
            Button(L.s("delete"), role: .destructive) {
                if let id = childId { try? app.diary.deleteChild(id) }
                nav.back()
            }
            Button(L.s("cancel"), role: .cancel) {}
        }
    }
}

/// «Фото в отчёте»: без фото / при реакции / все. Фото попадут в файл, который пользователь отправит сам.
private struct ExportPhotosSheet: View {
    @Binding var choice: String
    let onExport: (DiaryPdfExporter.PhotoMode) -> Void

    private let options: [(DiaryPdfExporter.PhotoMode, String, String)] = [
        (.none, "export_photos_none", "🚫"), (.reactions, "export_photos_reactions", "🤔"), (.all, "export_photos_all", "📷"),
    ]

    var body: some View {
        let current = DiaryPdfExporter.PhotoMode(rawValue: choice) ?? .reactions
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(L.s("export_photos_title")).font(AppFont.headlineSmall).foregroundStyle(AppColors.ink).padding(.top, 24)
                ForEach(options, id: \.0) { mode, key, emoji in
                    ChoiceRow(label: L.s(key), selected: current == mode, emoji: emoji) { choice = mode.rawValue }
                }
                Text(L.s("export_photos_note")).font(AppFont.bodyMedium).foregroundStyle(AppColors.inkMuted).padding(.leading, 6)
                AppButton(L.s("export_row"), icon: "ic_document") { onExport(current) }.padding(.top, 8)
            }
            .padding(.horizontal, screenPadding)
            .padding(.bottom, 24)
        }
    }
}
