import AppKit
import CoreServices

/// Text snippets: one file per snippet in ~/.config/fener/snippets (any extension), named
/// after the file. Return expands placeholders and copies the result; paste with Cmd+V.
/// (Typing it for you would need the Accessibility permission.)
///
///   {clipboard}  current clipboard text     {uuid}      a new UUID
///   {date}       2026-11-11                 {time}      14:05
///   {datetime}   2026-11-11 14:05           {date:EEE d MMM}  any DateFormatter pattern
/// Unknown {words} are left as they are.
final class Snippets {
    struct Snippet: Equatable { let name: String; let text: String; var url = URL(fileURLWithPath: "/") }
    let dir: URL
    private(set) var all: [Snippet] = []

    init(dir: URL) { self.dir = dir; load() }

    func load() {
        let fm = FileManager.default
        all = ((try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
            .filter { !$0.lastPathComponent.hasPrefix(".") && !$0.hasDirectoryPath }
            .compactMap { u in (try? String(contentsOf: u, encoding: .utf8)).map { Snippet(name: u.deletingPathExtension().lastPathComponent, text: $0, url: u) } }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func expand(_ text: String, now: Date = Date(), clipboard: String? = NSPasteboard.general.string(forType: .string),
                       uuid: () -> String = { UUID().uuidString }) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        func date(_ pattern: String) -> String { f.dateFormat = pattern; return f.string(from: now) }
        return text.replacing(#/\{(clipboard|uuid|date|time|datetime)(?::([^}]+))?\}/#) { m in
            switch m.1 {
            case "clipboard": return clipboard ?? ""
            case "uuid": return uuid()
            case "time": return date(m.2.map(String.init) ?? "HH:mm")
            case "datetime": return date(m.2.map(String.init) ?? "yyyy-MM-dd HH:mm")
            default: return date(m.2.map(String.init) ?? "yyyy-MM-dd")
            }
        }
    }
}

/// Definitions from the dictionaries enabled in Dictionary.app (offline), e.g. the built-in
/// English and Turkish ones.
enum Definitions {
    static func lookup(_ word: String) -> String? {
        let w = word.trimmingCharacters(in: .whitespaces)
        guard !w.isEmpty, let r = DCSCopyTextDefinition(nil, w as CFString, CFRange(location: 0, length: (w as NSString).length))
        else { return nil }
        return r.takeRetainedValue() as String
    }

    /// Splits a definition into its header (pronunciation, word class, first sense) and the
    /// following senses: numbered "2 …", bulleted "• …", and the ORIGIN note.
    static func senses(_ text: String) -> [String] {
        var parts: [String] = [], cur = ""
        let tokens = text.split(whereSeparator: \.isWhitespace).map(String.init)  // the text uses no-break spaces too
        for (i, t) in tokens.enumerated() {
            let numbered = Int(t).map { $0 >= 2 && $0 <= 30 } == true && i + 1 < tokens.count && !cur.isEmpty
            if (numbered || t == "•" || t == "ORIGIN"), !cur.trimmingCharacters(in: .whitespaces).isEmpty {
                parts.append(cur.trimmingCharacters(in: .whitespaces)); cur = ""
            }
            cur += (cur.isEmpty ? "" : " ") + (t == "•" ? "" : t)
        }
        if !cur.trimmingCharacters(in: .whitespaces).isEmpty { parts.append(cur.trimmingCharacters(in: .whitespaces)) }
        return parts
    }

    static let wordClasses: Set = ["noun", "verb", "adjective", "adverb", "pronoun", "preposition", "conjunction",
                                   "exclamation", "determiner", "abbreviation", "prefix", "suffix", "plural", "symbol"]

    /// The first part split into header (spelling, pronunciation, word class) and first sense:
    /// "x ser·en·dip | ˌserən | noun the occurrence…" or "kitap a. Ar. 1 esk. basılı…".
    static func header(_ first: String) -> (header: String, sense: String) {
        let words = first.split(whereSeparator: \.isWhitespace).map(String.init)
        // The word class follows the pronunciation, after the first "|" (examples later use "|" too).
        if let bar = words.firstIndex(of: "|"), let cls = words[(bar + 1)...].firstIndex(where: { wordClasses.contains($0) }) {
            return (words[...cls].joined(separator: " "), words[(cls + 1)...].joined(separator: " "))
        }
        if let one = words.firstIndex(of: "1"), one > 0 {
            return (words[..<one].joined(separator: " "), words[one...].joined(separator: " "))
        }
        return ("", first)
    }
}
