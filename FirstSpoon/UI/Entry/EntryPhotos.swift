import SwiftUI
import PhotosUI
import UIKit
import Observation
import FirstSpoonCore

/// Фото пробы на экране редактирования. Файл пишется сразу при выборе (уменьшенный, без обрезки), но в пробу попадает
/// только при «Сохранить»: `commit()` возвращает итоговый список и стирает выбранные здесь, но убранные снимки;
/// `discard()` при уходе без сохранения стирает всё, что выбрали на этом экране. Прежние файлы, убранные из пробы,
/// стирает репозиторий при сохранении.
@MainActor @Observable
final class EntryPhotosDraft {
    private(set) var photos: [String]
    private(set) var processing = false
    @ObservationIgnored private var importTask: Task<Void, Never>?
    @ObservationIgnored private var created: Set<String> = []
    @ObservationIgnored private var done = false
    @ObservationIgnored let store: PhotoStore

    init(store: PhotoStore, original: [String]) {
        self.store = store
        photos = original
    }

    var remaining: Int { max(0, DiaryEntry.maxPhotos - photos.count) }

    func importPhotos(_ items: [PhotosPickerItem], onDone: @escaping (Bool) -> Void) {
        guard !items.isEmpty, !processing, !done else { return }
        processing = true
        importTask = Task {
            var ok = true
            for item in items {
                let data = try? await item.loadTransferable(type: Data.self)
                guard !Task.isCancelled else { return }
                ok = (data.map { add($0) } ?? false) && ok
            }
            processing = false
            importTask = nil
            onDone(ok)
        }
    }

    private func add(_ data: Data) -> Bool {
        guard remaining > 0, let name = store.saveEntryPhoto(data) else { return false }
        created.insert(name)
        photos.append(name)
        return true
    }

    func remove(_ name: String) {
        photos.removeAll { $0 == name }
        if created.remove(name) != nil { store.delete(name) }
    }

    /// После записи в БД возвращает число новых фото для аналитики.
    func commit() -> Int {
        done = true
        let added = photos.filter(created.contains).count
        created = []
        return added
    }

    func discard() {
        guard !done else { return }
        importTask?.cancel()
        importTask = nil
        processing = false
        photos.removeAll { created.contains($0) }
        for name in created { store.delete(name) }
        created = []
    }
}

/// Секция «Фото (необязательно)»: только из галереи (PhotosPicker, без разрешения; камеры нет — решение пользователя).
/// Без фото — кнопка «Добавить фото»; с фото — миниатюры с ✕ и плитка «+» в конце ряда (сразу открывает выбор,
/// спиннер во время обработки, на 5 фото исчезает). Тап по фото — на весь экран.
struct EntryPhotosSection: View {
    let draft: EntryPhotosDraft
    @State private var items: [PhotosPickerItem] = []
    @State private var viewer: Int?
    @State private var failed = false
    @State private var library = false
    /// Выбранные фото уменьшаются и пишутся на диск — в плитке «+» спиннер.
    private var processing: Bool { draft.processing }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L.s("entry_photos_hint")).font(AppFont.bodyMedium).foregroundStyle(AppColors.inkMuted).padding(.leading, 6)
            if draft.photos.isEmpty && !processing {
                AppButton(L.s("photo_pick"), kind: .soft, size: .medium, icon: "ic_image_fill") { library = true }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(Array(draft.photos.enumerated()), id: \.element) { i, name in
                            thumbnail(name).onTapGesture { viewer = i }
                        }
                        if processing || draft.remaining > 0 { addTile }
                    }
                    .padding(.vertical, 6)
                }
            }
            if failed {
                Text(L.s("photo_error")).font(AppFont.bodyMedium).foregroundStyle(AppColors.alert).padding(.leading, 6)
            }
        }
        // Мультивыбор, не больше оставшихся мест (5 − уже добавленные).
        .photosPicker(isPresented: $library, selection: $items, maxSelectionCount: max(draft.remaining, 1),
                      matching: .images, photoLibrary: .shared())
        .onChange(of: items) { _, picked in
            guard !picked.isEmpty else { return }
            items = []
            failed = false
            draft.importPhotos(picked) { failed = !$0 }
        }
        // Только sheet, не fullScreenCover: полноэкранное окно вызывает onDisappear у экрана пробы, а он стирает черновик фото.
        .sheet(item: Binding(get: { viewer.map(ViewerIndex.init) }, set: { viewer = $0?.value })) { start in
            PhotoViewer(store: draft.store, photos: draft.photos, start: start.value) { viewer = nil }
                .presentationDetents([.large])
                .presentationBackground(.black)
        }
    }

    /// Плитка «+»: размер и скругление как у миниатюры, светло-фиолетовая; сразу открывает выбор фото.
    private var addTile: some View {
        Button { library = true } label: {
            ZStack {
                RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous).fill(AppColors.primarySoft)
                if processing {
                    ProgressView().tint(AppColors.primary)
                } else {
                    Image("ic_plus").font(.system(size: 28, weight: .semibold)).foregroundStyle(AppColors.primary)
                }
            }
            .frame(width: 88, height: 88)
        }
        .buttonStyle(PressableStyle())
        .disabled(processing)
        .accessibilityLabel(L.s("photo_pick"))
    }

    private func thumbnail(_ name: String) -> some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let image = draft.store.image(name) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    AppColors.surfaceSoft
                }
            }
            .frame(width: 88, height: 88)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))

            Button { draft.remove(name) } label: {
                Image("ic_close")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(.black.opacity(0.55), in: Circle())
            }
            .buttonStyle(.plain)
            .padding(4)
            .accessibilityLabel(L.s("entry_photo_remove"))
        }
    }
}

private struct ViewerIndex: Identifiable { let value: Int; var id: Int { value } }

/// Фото на весь экран, листаются; закрыть — крестик.
struct PhotoViewer: View {
    let store: PhotoStore
    let photos: [String]
    let start: Int
    let onClose: () -> Void
    @State private var index = 0

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            TabView(selection: $index) {
                ForEach(Array(photos.enumerated()), id: \.element) { i, name in
                    Group {
                        if let image = store.image(name) {
                            Image(uiImage: image).resizable().scaledToFit()
                        }
                    }
                    .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: photos.count > 1 ? .always : .never))
            Button(action: onClose) {
                Image("ic_close").font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 44, height: 44).background(.white.opacity(0.2), in: Circle())
            }
            .padding(16)
            .accessibilityLabel(L.s("close"))
        }
        .onAppear { index = start }
    }
}

/// Маленькая миниатюра первого фото пробы (+ число, если их несколько) — в дневнике и на странице продукта.
struct EntryPhotoBadge: View {
    let store: PhotoStore
    let photos: [String]
    var body: some View {
        if let first = photos.first {
            HStack(spacing: 4) {
                Group {
                    if let image = store.image(first) { Image(uiImage: image).resizable().scaledToFill() } else { AppColors.surfaceSoft }
                }
                .frame(width: 30, height: 30)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                if photos.count > 1 {
                    Text("📷 \(photos.count)").font(AppFont.labelSmall).foregroundStyle(AppColors.inkMuted)
                }
            }
        }
    }
}
