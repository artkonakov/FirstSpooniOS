import SwiftUI
import PhotosUI
import Observation

/// Черновик фото на экране редактирования: выбранные, но не сохранённые снимки не должны оставаться на диске.
/// `commit()` — при сохранении (стирает лишние новые файлы), `discard()` — при уходе без сохранения.
/// Прежний сохранённый файл стирает репозиторий, когда фото в записи меняется.
@MainActor @Observable
final class PhotoDraft {
    private(set) var current: String?
    @ObservationIgnored private let original: String?
    @ObservationIgnored private var created: [String] = []
    @ObservationIgnored private var done = false
    @ObservationIgnored let store: PhotoStore

    init(store: PhotoStore, original: String?) {
        self.store = store
        self.original = original
        current = original
    }

    func pick(_ data: Data) -> Bool {
        guard let name = store.save(data) else { return false }
        created.append(name)
        current = name
        return true
    }

    func remove() { current = nil }

    /// Сохранено: оставить только итоговый файл.
    func commit() -> String? {
        done = true
        for name in created where name != current { store.delete(name) }
        created = []
        return current
    }

    /// Ушли без сохранения: стереть всё, что выбрали на этом экране.
    func discard() {
        guard !done else { return }
        for name in created { store.delete(name) }
        created = []
        current = original
    }
}

/// Фото с кнопками «Выбрать / Изменить фото» и «Удалить фото». PhotosPicker работает без разрешения на доступ к медиатеке.
struct PhotoPickerField: View {
    let draft: PhotoDraft
    /// Заглушка, когда фото нет (аватар-эмодзи или буква продукта).
    let placeholder: AnyView
    var size: CGFloat = 96
    @State private var item: PhotosPickerItem?
    @State private var failed = false

    var body: some View {
        HStack(spacing: 16) {
            Group {
                if let image = draft.store.image(draft.current) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    placeholder
                }
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.32, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                let pickerLabel = L.s(draft.current == nil ? "photo_pick" : "photo_change")
                PhotosPicker(selection: $item, matching: .images, photoLibrary: .shared()) {
                    Text(pickerLabel)
                        .font(AppFont.labelLarge).foregroundStyle(AppColors.primary)
                        .frame(minHeight: 44)
                }
                if draft.current != nil {
                    Button { draft.remove() } label: {
                        Text(L.s("photo_remove")).font(AppFont.labelLarge).foregroundStyle(AppColors.alert).frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                }
                if failed {
                    Text(L.s("photo_error")).font(AppFont.bodyMedium).foregroundStyle(AppColors.alert)
                }
            }
            Spacer(minLength: 0)
        }
        .onChange(of: item) { _, newItem in
            guard let newItem else { return }
            Task {
                let data = try? await newItem.loadTransferable(type: Data.self)
                failed = !(data.map { draft.pick($0) } ?? false)
                item = nil
            }
        }
    }
}
