import Foundation
import UIKit

/// Фото ребёнка и своих продуктов — **только на устройстве**: `Application Support/photos/<uuid>.jpg`
/// (папка исключена из резервной копии, как и БД). В БД хранится только имя файла (`children.photo`, `custom_products.photo`).
/// Обработка как в Android: квадрат по центру, сторона 512 px, JPEG.
/// Файл удаляется при замене/удалении фото, удалении ребёнка или продукта, выходе из аккаунта и удалении данных.
final class PhotoStore: @unchecked Sendable {
    static let side: CGFloat = 512
    private let dir: URL
    private let cache = NSCache<NSString, UIImage>()

    init(dir: URL? = nil) {
        let base = dir ?? ((try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                         appropriateFor: nil, create: true)) ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("photos", isDirectory: true)
        self.dir = base
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var url = base
        try? url.setResourceValues(values)
    }

    /// Сохранить выбранное изображение (данные из PhotosPicker). Возвращает имя файла; nil — не картинка.
    func save(_ data: Data) -> String? {
        guard let image = UIImage(data: data), let jpeg = Self.squareJPEG(image) else { return nil }
        let name = UUID().uuidString.lowercased() + ".jpg"
        do {
            try jpeg.write(to: dir.appendingPathComponent(name), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            return name
        } catch {
            return nil
        }
    }

    func image(_ name: String?) -> UIImage? {
        guard let name, !name.isEmpty else { return nil }
        if let cached = cache.object(forKey: name as NSString) { return cached }
        guard let image = UIImage(contentsOfFile: dir.appendingPathComponent(name).path) else { return nil }
        cache.setObject(image, forKey: name as NSString)
        return image
    }

    func delete(_ name: String?) {
        guard let name, !name.isEmpty, !name.contains("/") else { return }
        cache.removeObject(forKey: name as NSString)
        try? FileManager.default.removeItem(at: dir.appendingPathComponent(name))
    }

    /// Стереть все фото (выход из аккаунта, удаление данных).
    func deleteAll() {
        cache.removeAllObjects()
        for url in (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [] {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Квадрат по центру → 512×512 → JPEG 0.85 (ориентация из EXIF учитывается при отрисовке).
    static func squareJPEG(_ image: UIImage) -> Data? {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        let crop = min(size.width, size.height)
        let target = min(side, crop * image.scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: target, height: target), format: format)
        let scaled = target / crop
        let drawSize = CGSize(width: size.width * scaled, height: size.height * scaled)
        let result = renderer.image { _ in
            image.draw(in: CGRect(x: (target - drawSize.width) / 2, y: (target - drawSize.height) / 2,
                                  width: drawSize.width, height: drawSize.height))
        }
        return result.jpegData(compressionQuality: 0.85)
    }
}
