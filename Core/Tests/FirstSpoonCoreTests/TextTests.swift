import XCTest
@testable import FirstSpoonCore

/// Кейсы — `Resources/name-cases.json` (копия Android `shared/tests/name-cases.json`): одно и то же имя
/// склоняется одинаково на обеих платформах.
final class NameCasesTests: XCTestCase {
    private struct Case: Decodable { let name: String; let sex: String?; let forms: [String]? }
    private struct File: Decodable { let cases: [Case] }

    func testSharedCases() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Resources/name-cases.json")
        let file = try JSONDecoder().decode(File.self, from: Data(contentsOf: url))
        XCTAssertFalse(file.cases.isEmpty)
        XCTAssertFalse(NameCases.rules.suffixes.isEmpty, "petrovich-rules.json не загрузился")
        var failures: [String] = []
        for c in file.cases {
            let sex = c.sex.flatMap(Sex.init(rawValue:))
            for nameCase in NameCase.allCases {
                let actual = NameCases.inflect(c.name, sex: sex, case: nameCase)
                let expected = c.forms?[nameCase.rawValue]
                if actual != expected { failures.append("\(c.name) (\(c.sex ?? "nil")) \(nameCase): ожидали \(expected ?? "nil"), получили \(actual ?? "nil")") }
            }
        }
        XCTAssert(failures.isEmpty, failures.joined(separator: "\n"))
        print("NameCases: \(file.cases.count) кейсов")
    }
}

/// Неразрывные пробелы в строках (Android `docs/copy-rules.md`). Те же правила, что в Android `tools/typograph.py`
/// и `TypographyTest` — упал тест: `python3 tools/typograph.py` в репозитории Android, затем проверить дифф.
final class TypographyTests: XCTestCase {
    private static let shortWords = "в во к ко с со у о об от до по за из на не ни и а но да для без при про под над что как"
    private let shortRe = try! NSRegularExpression(
        pattern: #"(^|[\s«(])("# + shortWords.replacingOccurrences(of: " ", with: "|") + #") (?=\S)"#,
        options: [.caseInsensitive])
    private let numberRe = try! NSRegularExpression(pattern: #"(\d|%\d\$d) (?=[A-Za-zА-Яа-яЁё])"#)
    /// Название приложения — подпись иконки, его не трогаем.
    private let skipKeys: Set<String> = ["app_name", "CFBundleDisplayName", "CFBundleName"]

    private func texts(_ lang: String) throws -> [(String, String)] {
        let dir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("FirstSpoon/Resources")
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "xcstrings" }
        XCTAssertGreaterThanOrEqual(files.count, 3)
        var out: [(String, String)] = []
        func walk(_ key: String, _ obj: Any) {
            if let d = obj as? [String: Any] {
                if let unit = d["stringUnit"] as? [String: Any], let v = unit["value"] as? String { out.append((key, v)) }
                d.values.forEach { walk(key, $0) }
            } else if let a = obj as? [Any] { a.forEach { walk(key, $0) } }
        }
        for f in files {
            let json = try JSONSerialization.jsonObject(with: Data(contentsOf: f)) as! [String: Any]
            for (key, entry) in json["strings"] as! [String: Any] where !skipKeys.contains(key) {
                if let loc = ((entry as? [String: Any])?["localizations"] as? [String: Any])?[lang] { walk(key, loc) }
            }
        }
        return out
    }

    private func has(_ re: NSRegularExpression, _ s: String) -> Bool {
        re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }

    func testRuHasNoHangingPrepositions() throws {
        let all = try texts("ru")
        XCTAssertGreaterThan(all.count, 100)
        let bad = all.filter { has(shortRe, $0.1) || has(numberRe, $0.1) || $0.1.contains(" —") }
        XCTAssert(bad.isEmpty, "Обычный пробел вместо неразрывного (U+00A0):\n" + bad.map { "\($0.0): \($0.1)" }.joined(separator: "\n"))
    }

    func testEnKeepsNumberAndUnitTogether() throws {
        let bad = try texts("en").filter { has(numberRe, $0.1) }
        XCTAssert(bad.isEmpty, "Число и слово через обычный пробел:\n" + bad.map { "\($0.0): \($0.1)" }.joined(separator: "\n"))
    }
}
