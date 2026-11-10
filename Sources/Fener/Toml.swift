import Foundation

/// Strict parser for the TOML subset fener's files use: comments, `key = value`,
/// `[table]`, `[a.b]`, `[[array of tables]]`, basic and literal strings, integers, floats,
/// booleans and single-line arrays of those. Anything else is an error with a line number,
/// never a silent misparse. Tables come back as [String: Any].
enum Toml {
    struct ParseError: Error, CustomStringConvertible {
        let line: Int, message: String
        var description: String { "line \(line): \(message)" }
    }

    static func parse(_ text: String) throws -> [String: Any] {
        var root: [String: Any] = [:]
        var path: [String] = []          // current table path
        var arrayIndex: Int? = nil       // set when the current table is an element of [[...]]

        func fail(_ n: Int, _ m: String) -> ParseError { ParseError(line: n, message: m) }

        for (i, raw) in text.components(separatedBy: "\n").enumerated() {
            let n = i + 1
            var s = Scanner(Array(raw), line: n)
            s.skipSpace()
            if s.atEnd || s.peek == "#" { continue }

            if s.peek == "[" {
                let isArray = s.peek(1) == "["
                s.pos += isArray ? 2 : 1
                let keys = try s.keyPath(until: "]")
                guard s.eat("]"), !isArray || s.eat("]") else { throw fail(n, "expected ]") }
                try s.endOfLine()
                path = keys
                if isArray {
                    var list = (get(root, keys) as? [[String: Any]]) ?? []
                    if get(root, keys) != nil && !(get(root, keys) is [[String: Any]]) { throw fail(n, "\(keys.joined(separator: ".")) is not an array of tables") }
                    list.append([:])
                    try set(&root, keys, list, n)
                    arrayIndex = list.count - 1
                } else {
                    if get(root, keys) != nil { throw fail(n, "table \(keys.joined(separator: ".")) defined twice") }
                    try set(&root, keys, [String: Any](), n)
                    arrayIndex = nil
                }
                continue
            }

            let keys = try s.keyPath(until: "=")
            guard s.eat("=") else { throw fail(n, "expected =") }
            s.skipSpace()
            let value = try s.value()
            try s.endOfLine()

            // Write into the current table (or the last element of the current [[array]]).
            var table: [String: Any]
            if let idx = arrayIndex { table = (get(root, path) as! [[String: Any]])[idx] }
            else { table = path.isEmpty ? root : (get(root, path) as? [String: Any]) ?? [:] }
            if get(table, keys) != nil { throw fail(n, "key \(keys.joined(separator: ".")) defined twice") }
            try set(&table, keys, value, n)
            if let idx = arrayIndex {
                var list = get(root, path) as! [[String: Any]]
                list[idx] = table
                try set(&root, path, list, n)
            } else if path.isEmpty { root = table }
            else { try set(&root, path, table, n) }
        }
        return root
    }

    private static func get(_ t: [String: Any], _ keys: [String]) -> Any? {
        var cur: Any = t
        for k in keys {
            if let d = cur as? [String: Any], let v = d[k] { cur = v }
            else if let l = cur as? [[String: Any]], let last = l.last, let v = last[k] { cur = v }
            else { return nil }
        }
        return cur
    }

    private static func set(_ t: inout [String: Any], _ keys: [String], _ value: Any, _ line: Int) throws {
        guard let k = keys.first else { return }
        if keys.count == 1 { t[k] = value; return }
        if var list = t[k] as? [[String: Any]] {  // [[a]] then [a.b]: extend the last element
            var last = list.removeLast()
            try set(&last, Array(keys.dropFirst()), value, line)
            list.append(last)
            t[k] = list
            return
        }
        guard var sub = (t[k] ?? [String: Any]()) as? [String: Any] else {
            throw ParseError(line: line, message: "\(k) is not a table")
        }
        try set(&sub, Array(keys.dropFirst()), value, line)
        t[k] = sub
    }

    private struct Scanner {
        let c: [Character], line: Int
        var pos = 0
        init(_ c: [Character], line: Int) { self.c = c; self.line = line }

        var atEnd: Bool { pos >= c.count }
        var peek: Character? { pos < c.count ? c[pos] : nil }
        func peek(_ k: Int) -> Character? { pos + k < c.count ? c[pos + k] : nil }
        func fail(_ m: String) -> ParseError { ParseError(line: line, message: m) }

        mutating func skipSpace() { while let p = peek, p == " " || p == "\t" || p == "\r" { pos += 1 } }
        mutating func eat(_ ch: Character) -> Bool {
            skipSpace()
            if peek == ch { pos += 1; return true }
            return false
        }
        mutating func endOfLine() throws {
            skipSpace()
            if atEnd || peek == "#" { return }
            throw fail("unexpected text after value")
        }

        mutating func keyPath(until end: Character) throws -> [String] {
            var keys: [String] = []
            while true {
                skipSpace()
                if peek == "\"" || peek == "'" { keys.append(try string()) }
                else {
                    var k = ""
                    while let p = peek, p.isLetter || p.isNumber || p == "_" || p == "-" { k.append(p); pos += 1 }
                    if k.isEmpty { throw fail("expected a key") }
                    keys.append(k)
                }
                skipSpace()
                if peek == "." { pos += 1; continue }
                if peek == end { return keys }
                throw fail("expected \(end) after key")
            }
        }

        mutating func value() throws -> Any {
            guard let p = peek else { throw fail("missing value") }
            switch p {
            case "\"", "'":
                if peek(1) == p && peek(2) == p { throw fail("multi-line strings are not supported") }
                return try string()
            case "[": return try array()
            case "{": throw fail("inline tables are not supported; use a [table]")
            default: break
            }
            var word = ""
            while let q = peek, q != " " && q != "\t" && q != "," && q != "]" && q != "#" && q != "\r" { word.append(q); pos += 1 }
            if word == "true" { return true }
            if word == "false" { return false }
            let digits = word.replacingOccurrences(of: "_", with: "")
            if let i = Int(digits) { return i }
            if digits.contains(where: { $0 == "." || $0 == "e" || $0 == "E" }), let d = Double(digits) { return d }
            throw fail("invalid value \(word.isEmpty ? "(empty)" : word)")
        }

        mutating func array() throws -> [Any] {
            pos += 1
            var out: [Any] = []
            while true {
                skipSpace()
                if peek == "]" { pos += 1; return out }
                if atEnd { throw fail("arrays must close on the same line") }
                out.append(try value())
                skipSpace()
                if peek == "," { pos += 1; continue }
                if peek == "]" { pos += 1; return out }
                throw fail("expected , or ] in array")
            }
        }

        mutating func string() throws -> String {
            let quote = c[pos]
            pos += 1
            var s = ""
            while let ch = peek {
                pos += 1
                if ch == quote { return s }
                if ch == "\\" && quote == "\"" {
                    guard let e = peek else { break }
                    pos += 1
                    switch e {
                    case "n": s.append("\n")
                    case "t": s.append("\t")
                    case "r": s.append("\r")
                    case "\"": s.append("\"")
                    case "\\": s.append("\\")
                    case "u", "U":
                        let len = e == "u" ? 4 : 8
                        guard pos + len <= c.count, let v = UInt32(String(c[pos..<pos + len]), radix: 16),
                              let u = Unicode.Scalar(v) else { throw fail("bad unicode escape") }
                        s.unicodeScalars.append(u)
                        pos += len
                    default: throw fail("unknown escape \\\(e)")
                    }
                } else { s.append(ch) }
            }
            throw fail("unterminated string")
        }
    }
}
