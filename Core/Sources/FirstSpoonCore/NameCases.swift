import Foundation

/// Падежи для подстановки имени в русские строки. Именительный — само имя.
public enum NameCase: Int, CaseIterable, Sendable { case genitive, dative, accusative, instrumental, prepositional }

/// Склонение имени ребёнка (ru) по правилам petrovich-rules (MIT, `Resources/petrovich-rules.json` — копия
/// `shared/petrovich/` из репозитория Android). Порт Android `domain/NameCases.kt`, кейсы — общий
/// `shared/tests/name-cases.json` (`NameCasesTests`). Правила текстов — Android `docs/copy-rules.md` («Как называем ребёнка»).
///
/// `inflect` возвращает `nil`, если надёжно склонить нельзя — тогда в тексте «малыш» или фраза без падежа:
/// пустое имя, несколько слов, пол не указан и нет общего для обоих полов правила, нет подходящего правила.
/// Имя без кириллицы (латиница) не склоняем — возвращаем как есть.
public enum NameCases {
    struct Rule { let gender: String; let tests: [String]; let mods: [String]; let firstWordOnly: Bool }

    static let rules: (exceptions: [Rule], suffixes: [Rule]) = load()

    public static func inflect(_ name: String, sex: Sex?, case nameCase: NameCase) -> String? {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if n.isEmpty || n.contains(where: \.isWhitespace) { return nil }
        if !n.contains(where: isCyrillic) { return n }
        let parts = n.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        if parts.contains(where: \.isEmpty) { return nil }
        var out: [String] = []
        for part in parts {
            guard let word = inflectWord(part, sex: sex, case: nameCase) else { return nil }
            out.append(word)
        }
        return out.joined(separator: "-")
    }

    private static func isCyrillic(_ c: Character) -> Bool {
        ("а"..."я").contains(c) || ("А"..."Я").contains(c) || c == "ё" || c == "Ё"
    }

    private static func inflectWord(_ word: String, sex: Sex?, case nameCase: NameCase) -> String? {
        let lower = word.lowercased()
        let gender = sex?.rawValue  // "male" / "female" — как в petrovich
        func fits(_ r: Rule) -> Bool { !r.firstWordOnly && (r.gender == "androgynous" || r.gender == gender) }
        let rule = rules.exceptions.first { fits($0) && $0.tests.contains(lower) }
            ?? rules.suffixes.first { r in fits(r) && r.tests.contains { lower.hasSuffix($0) } }
        guard let rule else { return nil }
        return apply(word, rule.mods[nameCase.rawValue])
    }

    /// `.` — без изменений; иначе каждый `-` убирает букву с конца, остальное дописывается.
    private static func apply(_ word: String, _ mod: String) -> String {
        if mod == "." { return word }
        let cut = mod.prefix { $0 == "-" }.count
        return String(word.dropLast(cut)) + mod.dropFirst(cut)
    }

    private struct RawRule: Decodable { let gender: String; let test: [String]; let mods: [String]; let tags: [String]? }
    private struct Section: Decodable { let exceptions: [RawRule]; let suffixes: [RawRule] }
    private struct File: Decodable { let firstname: Section }

    private static func load() -> ([Rule], [Rule]) {
        guard let url = Bundle.module.url(forResource: "petrovich-rules", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(File.self, from: data) else { return ([], []) }
        // Правила только для первого слова двойной фамилии/имени — для имён детей не применяем.
        func map(_ raw: [RawRule]) -> [Rule] {
            raw.map { Rule(gender: $0.gender, tests: $0.test, mods: $0.mods, firstWordOnly: $0.tags?.contains("first_word") == true) }
        }
        return (map(file.firstname.exceptions), map(file.firstname.suffixes))
    }
}
