import SwiftUI
import FirstSpoonCore

/// Дети и вход в настройки. Аккаунт, выход и удаление — на экране настроек.
/// Подписка «Плюс» на iOS пока не подключена (StoreKit — следующий этап), карточку не показываем.
struct ProfileView: View {
    @Environment(AppContainer.self) private var app
    @Environment(Navigator.self) private var nav

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(L.s("profile_children"))
                ForEach(app.diary.children) { child in
                    ChildCard(child: child, active: child.id == app.diary.activeChild?.id,
                              onTap: { app.diary.selectChild(child.id) }, onEdit: { nav.open(.child(child.id)) })
                }
                AppButton(L.s("child_add"), kind: .soft, icon: "plus") { nav.open(.child(nil)) }
                Spacer().frame(height: 12)
                ActionRow(title: L.s("settings"), icon: "gearshape.fill") { nav.open(.settings) }
            }
            .padding(.horizontal, screenPadding)
            .padding(.bottom, 24)
        }
        .appScreen()
        .navigationTitle(L.s("profile_title"))
    }
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
                    Image(systemName: "pencil").font(.system(size: 20, weight: .semibold)).foregroundStyle(AppColors.inkMuted)
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

    var body: some View {
        ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    FieldLabel(L.s("child_name")).padding(.top, 8)
                    AppTextField(text: Binding(get: { name }, set: { name = String($0.prefix(40)) }),
                                 placeholder: L.s("child_name"), capitalization: .words)
                    FieldLabel(L.s("child_birth_date")).padding(.top, 8)
                    ActionRow(title: birthDate.map { UiLocale.dayMonthYear($0) } ?? L.s("child_birth_date_pick"),
                              value: birthDate.map { Labels.ageText(Child(id: "", name: name, birthDate: $0)) },
                              icon: "calendar") { pickDate = true }
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
                if (try? app.diary.saveChild(id: childId, name: name, birthDate: birthDate, sex: sex, profile: profile)) != nil { nav.back() }
            }
            .padding(.horizontal, screenPadding)
            .padding(.vertical, 12)
        }
        .appScreen()
        .navigationTitle(L.s(childId == nil ? "child_new_title" : "child_edit_title"))
        .onAppear {
            guard !loaded else { return }
            loaded = true
            if let id = childId, let c = app.diary.getChild(id) {
                name = c.name; birthDate = c.birthDate; sex = c.sex; profile = c.profile
            }
        }
        .sheet(isPresented: $pickDate) {
            VStack(spacing: 16) {
                BirthDatePicker(value: $birthDate, name: name)
                AppButton(L.s("ok")) { pickDate = false }
            }
            .padding(screenPadding)
            .presentationDetents([.large])
            .presentationBackground(AppColors.background)
        }
        .alert(L.s("child_delete_confirm", name), isPresented: $confirmDelete) {
            Button(L.s("delete"), role: .destructive) {
                if let id = childId { try? app.diary.deleteChild(id) }
                nav.back()
            }
            Button(L.s("cancel"), role: .cancel) {}
        }
    }
}
