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

    struct Input {
        let child: Child
        let entries: [DiaryEntry]
        let marks: [String: ProductMark]
        let catalog: Catalog
        let today: LocalDate
    }

    /// Имя файла: «Дневник прикорма — <Имя> — yyyy-MM-dd.pdf».
    static func fileName(child: Child, today: LocalDate) -> String {
        let safeName = child.name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        return "\(L.s("pdf_title")) — \(safeName) — \(today.iso).pdf"
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
        let text: NSAttributedString
        var spaceBefore: CGFloat = 0
        /// Не отрывать от следующего блока (заголовок дня/раздела).
        var keepWithNext = false
        var height: CGFloat = 0
    }

    static func render(_ input: Input) -> Data {
        let width = pageSize.width - margin * 2
        var blocks = content(input).map { b -> Block in
            var b = b
            b.height = ceil(b.text.boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
                                                options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil).height)
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
                    block.text.draw(with: CGRect(x: margin, y: top, width: width, height: block.height),
                                    options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
                }
                let footer = NSAttributedString(string: L.s("pdf_page_of", n + 1, pages.count), attributes: style(10, 400, muted: true, center: true))
                footer.draw(in: CGRect(x: margin, y: pageSize.height - margin - 12, width: width, height: 16))
            }
        }
    }

    private static func content(_ input: Input) -> [Block] {
        let child = input.child, catalog = input.catalog
        func name(_ id: String) -> String { catalog.productsById[id]?.name ?? id }
        var out: [Block] = []

        // Шапка
        out.append(Block(text: text(L.s("pdf_title"), style(24, 800))))
        out.append(Block(text: text(child.name, style(18, 700)), spaceBefore: 6))
        let birth = child.birthDate.map { L.s("pdf_birth_date", UiLocale.dayMonthYear($0), Labels.ageText(child, today: input.today)) }
            ?? L.s("age_unknown")
        out.append(Block(text: text(birth, style(12, 400, muted: true)), spaceBefore: 4))
        out.append(Block(text: text(L.s("pdf_exported_at", UiLocale.dayMonthYear(input.today)), style(12, 400, muted: true)), spaceBefore: 2))

        // Сводка
        let progress = FeedingRules.progressByProduct(input.entries, marks: input.marks)
        let introduced = progress.values.filter { $0.status == .introduced }.count
        let inProgress = progress.values.filter { $0.status == .inProgress }.count
        out.append(Block(text: text(L.s("pdf_summary", introduced, FeedingRules.introductionGoal, inProgress), style(13, 600)),
                         spaceBefore: 16))

        // Списки по статусам — названия по алфавиту.
        for (status, title) in [(ProductStatus.allergy, "status_allergy"), (.excluded, "pdf_excluded"), (.reaction, "status_reaction")] {
            let names = progress.values.filter { $0.status == status }.map { name($0.productId) }
                .sorted { $0.compare($1, locale: UiLocale.locale) == .orderedAscending }
            let line = NSMutableAttributedString(string: L.s(title) + ": ", attributes: style(12, 700))
            line.append(NSAttributedString(string: names.isEmpty ? "—" : names.joined(separator: ", "), attributes: style(12, 400)))
            out.append(Block(text: line, spaceBefore: 6))
        }

        // Пробы по дням, по возрастанию даты и времени.
        out.append(Block(text: text(L.s("product_tries"), style(18, 700)), spaceBefore: 20, keepWithNext: true))
        let sorted = input.entries.enumerated().sorted { a, b in
            let (x, y) = (a.element, b.element)
            if x.date != y.date { return x.date < y.date }
            let tx = x.time?.minuteOfDay ?? -1, ty = y.time?.minuteOfDay ?? -1
            if tx != ty { return tx < ty }
            if x.createdAt != y.createdAt { return x.createdAt < y.createdAt }
            return a.offset > b.offset
        }.map(\.element)
        if sorted.isEmpty {
            out.append(Block(text: text(L.s("pdf_no_entries"), style(12, 400, muted: true)), spaceBefore: 6))
        }
        var day: LocalDate?
        for e in sorted {
            if e.date != day {
                day = e.date
                out.append(Block(text: text(UiLocale.dayMonthYear(e.date), style(14, 700)), spaceBefore: 12, keepWithNext: true))
            }
            let line = NSMutableAttributedString(string: (e.time.map { "\($0)  " } ?? ""), attributes: style(12, 400, muted: true))
            line.append(NSAttributedString(string: name(e.productId), attributes: style(12, 700)))
            let details = [e.amount.map(Labels.label), e.meal.map(Labels.label), Labels.label(e.reaction)].compactMap { $0 }
            line.append(NSAttributedString(string: " — " + details.joined(separator: ", "), attributes: style(12, 400)))
            if !e.symptoms.isEmpty {
                line.append(NSAttributedString(string: "\n" + L.s("pdf_symptoms", e.symptoms.map(Labels.label).joined(separator: ", ")),
                                               attributes: style(11, 400, muted: true)))
            }
            if let note = e.note, !note.isEmpty {
                line.append(NSAttributedString(string: "\n" + L.s("pdf_note", note), attributes: style(11, 400, muted: true)))
            }
            out.append(Block(text: line, spaceBefore: 4))
        }
        return out
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
