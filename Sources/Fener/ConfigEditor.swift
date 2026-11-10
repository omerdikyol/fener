import Foundation

/// Changes one key in config.toml text and leaves every other line as it was: comments,
/// blank lines, order and other keys. A key that is missing is added to its table (or the
/// table is added at the end); a trailing "# comment" on a replaced line is kept.
enum ConfigEditor {
    enum Value: Equatable {
        case string(String), bool(Bool), int(Int), double(Double), strings([String])

        var toml: String {
            func quote(_ s: String) -> String {
                "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
                    .replacingOccurrences(of: "\n", with: "\\n") + "\""
            }
            switch self {
            case .string(let s): return quote(s)
            case .bool(let b): return b ? "true" : "false"
            case .int(let i): return String(i)
            case .double(let d): return d == d.rounded() ? String(Int(d)) : String(d)
            case .strings(let a): return "[" + a.map(quote).joined(separator: ", ") + "]"
            }
        }
    }

    /// The table a line opens ("[panel]" -> "panel"), nil for other lines; "[[x]]" counts as "x".
    static func header(_ line: String) -> String? {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.hasPrefix("[") else { return nil }
        let inner = t.drop(while: { $0 == "[" })
        guard let end = inner.firstIndex(of: "]") else { return nil }
        return inner[..<end].trimmingCharacters(in: .whitespaces)
    }

    /// Where a "# comment" starts on a line, ignoring "#" inside quotes.
    static func commentStart(_ line: String) -> String.Index? {
        var quote: Character? = nil, escaped = false
        for i in line.indices {
            let c = line[i]
            if escaped { escaped = false; continue }
            if quote == "\"" && c == "\\" { escaped = true; continue }
            if let q = quote { if c == q { quote = nil }; continue }
            if c == "\"" || c == "'" { quote = c } else if c == "#" { return i }
        }
        return nil
    }

    static func isKey(_ line: String, _ key: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.hasPrefix(key) else { return false }
        return t.dropFirst(key.count).trimmingCharacters(in: .whitespaces).hasPrefix("=")
    }

    static func set(_ text: String, section: String?, key: String, value: Value) -> String {
        var lines = text.isEmpty ? [] : text.components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }   // re-added at the end
        let newLine = "\(key) = \(value.toml)"

        // The section's region: its lines up to the next table header.
        let headers = lines.indices.filter { header(lines[$0]) != nil }
        let start: Int, end: Int
        if let section {
            guard let h = headers.first(where: { header(lines[$0]) == section && !lines[$0].contains("[[") }) else {
                if let last = lines.last, !last.trimmingCharacters(in: .whitespaces).isEmpty { lines.append("") }
                lines += ["[\(section)]", newLine]
                return lines.joined(separator: "\n") + "\n"
            }
            start = h + 1
            end = headers.first(where: { $0 > h }) ?? lines.count
        } else {
            start = 0
            end = headers.first ?? lines.count
        }

        if let i = (start..<end).first(where: { isKey(lines[$0], key) }) {
            let indent = String(lines[i].prefix(while: { $0 == " " || $0 == "\t" }))
            let comment = commentStart(lines[i]).map { "  " + lines[i][$0...] } ?? ""
            lines[i] = indent + newLine + comment
        } else {
            // After the last key of the region, or before its trailing blank lines.
            let keyLines = (start..<end).filter {
                let t = lines[$0].trimmingCharacters(in: .whitespaces)
                return !t.isEmpty && !t.hasPrefix("#")
            }
            var at = keyLines.last.map { $0 + 1 } ?? start
            if keyLines.isEmpty { while at < end, !lines[at].trimmingCharacters(in: .whitespaces).isEmpty { at += 1 } }
            lines.insert(newLine, at: at)
            if section == nil, at == end, end < lines.count - 1 { lines.insert("", at: at + 1) }   // keep a gap before the first table
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
