import Foundation
import UIKit
import FirstSpoonCore

/// Экспорт дневника активного ребёнка в PDF (A4, генерация на устройстве, как в Android).
/// Содержимое: шапка (имя, дата рождения и возраст, дата выгрузки), сводка (введено X из 100, в процессе N),
/// списки «Аллергия» / «Исключены» / «Была реакция», все пробы по дням по возрастанию даты, «стр. N из M» внизу каждой страницы.
/// Вёрстка в два прохода: сначала раскладываем блоки по страницам (чтобы знать M), потом рисуем.
enum DiaryPdfExporter {
    static let pageSize = CGSize(width: 595.2, height: 841.8) // A4 в пунктах
    static let margin: CGFloat = 48
    static let footerHeight: CGFloat = 24

    /// Какие фото проб класть в отчёт (выбор «Фото в отчёте»); `rawValue` — параметр аналитики `photos`.
    enum PhotoMode: String, CaseIterable {
        case none, reactions, all

        func includes(_ reaction: Reaction) -> Bool {
            switch self {
            case .none: return false
            case .reactions: return reaction == .unsure || reaction == .reaction
            case .all: return true
            }
        }
    }

    struct Input {
        let child: Child
        let entries: [DiaryEntry]
        let marks: [String: ProductMark]
        let catalog: Catalog
        let today: LocalDate
        var photoMode: PhotoMode = .none
        var photos: PhotoStore?
        var recipeMeals: [RecipeMeal] = []
    }

    /// Миниатюры фото в PDF: высота ~4 см, пропорции сохраняются, уменьшены до ~1000 px JPEG, чтобы файл был в пределах МБ.
    static let photoHeight: CGFloat = 113
    static let photoGap: CGFloat = 6
    static let photoPixels: CGFloat = 1000

    /// Имя файла: «Дневник прикорма — <Имя> — yyyy-MM-dd.pdf» / «Baby food diary — <Name> — yyyy-MM-dd.pdf».
    static func fileName(child: Child, today: LocalDate) -> String {
        let safeName = child.name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        return L.s("export_file_name", safeName, today.iso)
    }

    /// Готовый файл во временной папке (для «Поделиться» / «Сохранить в Файлы»).
    static func export(_ input: Input) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("export", isDirectory: true)
        try? FileManager.default.removeItem(at: dir) // старые выгрузки не копим
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(fileName(child: input.child, today: input.today))
        try render(input).write(to: url, options: .atomic)
        return url
    }

    // MARK: - Вёрстка

    private struct Block {
        var text = NSAttributedString()
        /// Ряд миниатюр фото (вместо текста): картинка и её ширина при высоте `photoHeight`.
        var images: [(UIImage, CGFloat)] = []
        var spaceBefore: CGFloat = 0
        /// Не отрывать от следующего блока (заголовок дня/раздела).
        var keepWithNext = false
        var height: CGFloat = 0
    }

    static func render(_ input: Input) -> Data {
        let width = pageSize.width - margin * 2
        var blocks = content(input).map { b -> Block in
            var b = b
            b.height = b.images.isEmpty
                ? ceil(b.text.boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
                                           options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil).height)
                : photoHeight
            return b
        }
        // Проход 1: раскладка по страницам.
        let bottom = pageSize.height - margin - footerHeight
        var pages: [[(Block, CGFloat)]] = [[]]
        var y = margin
        var i = 0
        while i < blocks.count {
            let b = blocks[i]
            let before = pages[pages.count - 1].isEmpty ? 0 : b.spaceBefore
            var needed = before + b.height
            if b.keepWithNext, i + 1 < blocks.count { needed += blocks[i + 1].spaceBefore + blocks[i + 1].height }
            if y + needed > bottom && !pages[pages.count - 1].isEmpty {
                pages.append([])
                y = margin
                continue
            }
            y += before
            pages[pages.count - 1].append((b, y))
            y += b.height
            i += 1
        }
        blocks.removeAll()

        // Проход 2: рисуем, теперь известно число страниц.
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize), format: {
            let f = UIGraphicsPDFRendererFormat()
            f.documentInfo = [kCGPDFContextTitle as String: fileName(child: input.child, today: input.today),
                              kCGPDFContextCreator as String: L.s("app_name")]
            return f
        }())
        return renderer.pdfData { ctx in
            for (n, page) in pages.enumerated() {
                ctx.beginPage()
                for (block, top) in page {
                    if block.images.isEmpty {
                        block.text.draw(with: CGRect(x: margin, y: top, width: width, height: block.height),
                                        options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
                    } else {
                        var x = margin
                        for (image, w) in block.images {
                            image.draw(in: CGRect(x: x, y: top, width: w, height: photoHeight))
                            x += w + photoGap
                        }
                    }
                }
                let footer = NSAttributedString(string: L.s("export_page", n + 1, pages.count), attributes: style(10, 400, muted: true, center: true))
                footer.draw(in: CGRect(x: margin, y: pageSize.height - margin - 12, width: width, height: 16))
            }
        }
    }

    private static func content(_ input: Input) -> [Block] {
        let child = input.child, catalog = input.catalog
        func name(_ id: String) -> String { catalog.productsById[id]?.name ?? id }
        var out: [Block] = []

        // Шапка
        out.append(Block(text: text(L.s("export_title"), style(24, 800))))
        out.append(Block(text: text(child.name, style(18, 700)), spaceBefore: 6))
        let birth = child.birthDate.map { L.s("export_birth", UiLocale.dayMonthYear($0), Labels.ageText(child, today: input.today)) }
            ?? L.s("age_unknown")
        out.append(Block(text: text(birth, style(12, 400, muted: true)), spaceBefore: 4))
        out.append(Block(text: text(L.s("export_generated", UiLocale.dayMonthYear(input.today)), style(12, 400, muted: true)), spaceBefore: 2))

        // Сводка
        let progress = FeedingRules.progressByProduct(input.entries, marks: input.marks)
        let introduced = progress.values.filter { $0.status == .introduced }.count
        let inProgress = progress.values.filter { $0.status == .inProgress }.count
        let hasMeals = !input.recipeMeals.isEmpty
        let summary = hasMeals ? "export_summary_with_meals" : "export_summary"
        out.append(Block(text: text(L.s(summary, introduced, FeedingRules.introductionGoal, inProgress, input.entries.count + input.recipeMeals.count), style(13, 600)),
                         spaceBefore: 16))

        // Списки по статусам — названия по алфавиту.
        // Ключи как в Android: «Аллергия: %1$@» и т.д.; пустые списки — «—».
        for (status, key) in [(ProductStatus.allergy, "export_allergy"), (.excluded, "export_excluded"), (.reaction, "export_reaction")] {
            let names = progress.values.filter { $0.status == status }.map { name($0.productId) }
                .sorted { $0.compare($1, locale: UiLocale.locale) == .orderedAscending }
            out.append(Block(text: text(L.s(key, names.isEmpty ? "—" : names.joined(separator: ", ")), style(12, 400)), spaceBefore: 6))
        }

        // Записи по дням, по возрастанию даты и времени.
        out.append(Block(text: text(L.s(hasMeals ? "diary_title" : "product_tries"), style(18, 700)), spaceBefore: 20, keepWithNext: true))
        let sorted = DiaryTimelineItem.newestFirst(entries: input.entries, meals: input.recipeMeals).reversed()
        if sorted.isEmpty {
            out.append(Block(text: text(L.s("export_empty"), style(12, 400, muted: true)), spaceBefore: 6))
        }
        var day: LocalDate?
        for record in sorted {
            if record.date != day {
                day = record.date
                out.append(Block(text: text(UiLocale.dayMonthYear(record.date), style(14, 700)), spaceBefore: 12, keepWithNext: true))
            }
            let title: String, contents: String?, meal: Meal?, amount: Amount?, reaction: Reaction
            let symptoms: [Symptom], note: String?, photos: [String]
            switch record {
            case .product(let entry):
                title = name(entry.productId)
                contents = nil
                (meal, amount, reaction, symptoms, note, photos) = (entry.meal, entry.amount, entry.reaction, entry.symptoms, entry.note, entry.photos)
            case .meal(let entry):
                title = entry.snapshot.title.value()
                let eaten = entry.eatenIngredients.map { input.catalog.productsById[$0.productId]?.name ?? $0.name }
                contents = L.s("recipe_meal_contents", eaten.joined(separator: ", "))
                (meal, amount, reaction, symptoms, note, photos) = (entry.meal, entry.amount, entry.reaction, [], entry.note, entry.photos)
            }
            let line = NSMutableAttributedString(string: (record.time.map { UiLocale.time($0) + "  " } ?? ""), attributes: style(12, 400, muted: true))
            line.append(NSAttributedString(string: title, attributes: style(12, 700)))
            let details = [amount.map(Labels.label), meal.map(Labels.label), L.s("export_reaction_value", Labels.label(reaction))].compactMap { $0 }
            line.append(NSAttributedString(string: " — " + details.joined(separator: ", "), attributes: style(12, 400)))
            if let contents {
                line.append(NSAttributedString(string: "\n" + contents, attributes: style(11, 400, muted: true)))
            }
            if !symptoms.isEmpty {
                line.append(NSAttributedString(string: "\n" + L.s("export_symptoms", symptoms.map(Labels.label).joined(separator: ", ")),
                                               attributes: style(11, 400, muted: true)))
            }
            if let note, !note.isEmpty {
                line.append(NSAttributedString(string: "\n" + L.s("export_note", note), attributes: style(11, 400, muted: true)))
            }
            out.append(Block(text: line, spaceBefore: 4))
            if input.photoMode.includes(reaction), let store = input.photos {
                out += photoRows(photos.compactMap { store.image($0) })
            }
        }
        return out
    }

    /// Миниатюры фото пробы рядами: пропорции сохраняются, не влезает в строку — переносится на следующую (и страницу).
    private static func photoRows(_ images: [UIImage]) -> [Block] {
        let width = pageSize.width - margin * 2
        var rows: [Block] = []
        var row: [(UIImage, CGFloat)] = []
        var used: CGFloat = 0
        for original in images {
            // Уменьшаем до ~1000 px и пережимаем в JPEG — в PDF уходит сжатая картинка, а не исходник.
            guard let data = PhotoStore.scaledJPEG(original, longest: photoPixels, quality: 0.75),
                  let image = UIImage(data: data), image.size.height > 0 else { continue }
            let w = min(width, photoHeight * image.size.width / image.size.height)
            if !row.isEmpty && used + photoGap + w > width {
                rows.append(Block(images: row, spaceBefore: 6))
                row = []; used = 0
            }
            used += (row.isEmpty ? 0 : photoGap) + w
            row.append((image, w))
        }
        if !row.isEmpty { rows.append(Block(images: row, spaceBefore: 6)) }
        return rows
    }

    private static func text(_ s: String, _ attrs: [NSAttributedString.Key: Any]) -> NSAttributedString {
        NSAttributedString(string: s, attributes: attrs)
    }

    /// Печать всегда в светлых цветах, независимо от темы телефона.
    private static func style(_ size: CGFloat, _ weight: CGFloat, muted: Bool = false, center: Bool = false) -> [NSAttributedString.Key: Any] {
        let p = NSMutableParagraphStyle()
        p.lineSpacing = 2
        p.alignment = center ? .center : .natural
        return [.font: AppFont.uiFont(size, weight),
                .foregroundColor: muted ? UIColor(hex: 0x5E5866) : UIColor(hex: 0x1F1B24),
                .paragraphStyle: p]
    }
}
