import Foundation

/// Calculator and unit conversions.
///   2 * (3 + 4)^2      sqrt 2 / 2      20% * 150      3,5 + 1,25 (decimal comma)
///   10 km to mi        72 f in c       1.5 gib to mb  90 min to h
enum Calc {
    struct Answer: Equatable { let value: String; let detail: String }

    /// Returns an answer only for input that looks like math: a plain number or a word alone
    /// is not a calculation, so app names like "1Password" never trigger it.
    static func answer(_ raw: String, forced: Bool = false) -> Answer? {
        let s = raw.trimmingCharacters(in: .whitespaces).lowercased()
        guard !s.isEmpty else { return nil }
        if let c = conversion(s) { return c }
        guard let v = evaluate(s), v.isFinite else { return nil }
        if !forced {
            // Two or more tokens that evaluate is math ("2pi", "sqrt 2"); one token is not ("2024", "e").
            guard (tokenize(s)?.count ?? 0) >= 2 else { return nil }
        }
        return Answer(value: format(v), detail: s)
    }

    static func format(_ v: Double) -> String {
        if v == v.rounded(), abs(v) < 1e15 { return String(Int64(v)) }
        var s = String(format: "%.10g", v)
        if s.contains("e") { return s }
        while s.contains("."), s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s
    }

    // MARK: expressions

    static let functions: [String: (Double) -> Double] = [
        "sqrt": { $0.squareRoot() }, "cbrt": cbrt, "abs": { Swift.abs($0) },
        "sin": sin, "cos": cos, "tan": tan, "asin": asin, "acos": acos, "atan": atan,
        "ln": log, "log": log10, "log2": log2, "exp": exp,
        "round": { $0.rounded() }, "floor": { $0.rounded(.down) }, "ceil": { $0.rounded(.up) },
    ]
    static let constants: [String: Double] = ["pi": .pi, "π": .pi, "tau": 2 * .pi, "e": M_E]

    private enum Token: Equatable { case num(Double), op(Character), ident(String), open, close }

    private static func tokenize(_ s: String) -> [Token]? {
        var out: [Token] = [], c = Array(s), i = 0
        while i < c.count {
            let ch = c[i]
            if ch.isWhitespace || ch == "_" { i += 1; continue }
            if ch.isNumber || ch == "." || (ch == "," && i + 1 < c.count && c[i + 1].isNumber) {
                var t = ""
                // A comma between digits is a decimal comma (3,5), as typed on Turkish layouts.
                while i < c.count, c[i].isNumber || c[i] == "." || c[i] == "_" || (c[i] == "," && i + 1 < c.count && c[i + 1].isNumber) {
                    if c[i] != "_" { t.append(c[i] == "," ? "." : c[i]) }
                    i += 1
                }
                guard let v = Double(t) else { return nil }
                out.append(.num(v)); continue
            }
            if ch.isLetter || ch == "π" {
                var t = ""
                while i < c.count, c[i].isLetter || c[i].isNumber || c[i] == "π" { t.append(c[i]); i += 1 }
                out.append(.ident(t)); continue
            }
            switch ch {
            case "+", "-", "*", "/", "^", "%": out.append(.op(ch))
            case "×": out.append(.op("*"))
            case "÷": out.append(.op("/"))
            case "√": out.append(.ident("sqrt"))
            case "(": out.append(.open)
            case ")": out.append(.close)
            default: return nil
            }
            i += 1
        }
        return out
    }

    /// Recursive descent: sum := product (± product)*; product := power ((*|/|implicit) power)*;
    /// unary := ± unary | power; power := atom %* (^ unary)?   (so -2^2 = -4 and 2^-1 = 0.5)
    static func evaluate(_ s: String) -> Double? {
        guard let tokens = tokenize(s), !tokens.isEmpty else { return nil }
        var p = 0
        func peek() -> Token? { p < tokens.count ? tokens[p] : nil }

        func sum() -> Double? {
            guard var v = product() else { return nil }
            while case .op(let o)? = peek(), o == "+" || o == "-" {
                p += 1
                guard let r = product() else { return nil }
                v = o == "+" ? v + r : v - r
            }
            return v
        }
        func product() -> Double? {
            guard var v = unary() else { return nil }
            while let t = peek() {
                if case .op(let o) = t, o == "*" || o == "/" {
                    p += 1
                    guard let r = unary() else { return nil }
                    v = o == "*" ? v * r : v / r
                } else if t == .open || { if case .ident = t { return true }; return false }() {
                    guard let r = power() else { return nil }  // implicit: 2pi, 2(3+1), 3 sqrt 4
                    v *= r
                } else { break }
            }
            return v
        }
        func unary() -> Double? {
            if case .op(let o)? = peek(), o == "-" || o == "+" {
                p += 1
                guard let v = unary() else { return nil }
                return o == "-" ? -v : v
            }
            return power()
        }
        func power() -> Double? {
            guard var b = atom() else { return nil }
            while case .op("%")? = peek() { p += 1; b /= 100 }
            if case .op("^")? = peek() {
                p += 1
                guard let e = unary() else { return nil }  // right associative
                return pow(b, e)
            }
            return b
        }
        func atom() -> Double? {
            guard let t = peek() else { return nil }
            p += 1
            switch t {
            case .num(let v): return v
            case .open:
                guard let v = sum(), peek() == .close else { return nil }
                p += 1
                return v
            case .ident(let name):
                if let c = constants[name] { return c }
                guard let f = functions[name], let arg = power() else { return nil }
                return f(arg)
            default: return nil
            }
        }

        guard let v = sum(), p == tokens.count else { return nil }
        return v
    }

    // MARK: units

    private enum Kind { case length, mass, time, data, volume, speed, temperature }
    /// Factor to the base unit of each kind (m, kg, s, byte, l, m/s).
    private static let units: [String: (Kind, Double)] = {
        var u: [String: (Kind, Double)] = [:]
        func add(_ k: Kind, _ f: Double, _ names: String...) { names.forEach { u[$0] = (k, f) } }
        add(.length, 1, "m", "meter", "meters", "metre", "metres")
        add(.length, 1000, "km", "kilometer", "kilometers")
        add(.length, 0.01, "cm"); add(.length, 0.001, "mm")
        add(.length, 1609.344, "mi", "mile", "miles"); add(.length, 0.3048, "ft", "foot", "feet")
        add(.length, 0.0254, "inch", "inches", "\""); add(.length, 0.9144, "yd", "yard", "yards")
        add(.mass, 1, "kg", "kilo", "kilos"); add(.mass, 0.001, "g", "gram", "grams"); add(.mass, 1e-6, "mg")
        add(.mass, 1000, "t", "ton", "tonne", "tonnes")
        add(.mass, 0.45359237, "lb", "lbs", "pound", "pounds"); add(.mass, 0.028349523125, "oz", "ounce", "ounces")
        add(.time, 1, "s", "sec", "secs", "second", "seconds"); add(.time, 60, "min", "mins", "minute", "minutes")
        add(.time, 3600, "h", "hr", "hrs", "hour", "hours"); add(.time, 86400, "d", "day", "days")
        add(.time, 604800, "wk", "week", "weeks"); add(.time, 0.001, "ms")
        add(.data, 1, "b", "byte", "bytes")
        add(.data, 1e3, "kb"); add(.data, 1e6, "mb"); add(.data, 1e9, "gb"); add(.data, 1e12, "tb")
        add(.data, 1024, "kib"); add(.data, 1048576, "mib"); add(.data, 1073741824, "gib"); add(.data, 1099511627776, "tib")
        add(.volume, 1, "l", "liter", "liters", "litre", "litres"); add(.volume, 0.001, "ml")
        add(.volume, 3.785411784, "gal", "gallon", "gallons")
        add(.speed, 1, "m/s", "mps"); add(.speed, 1 / 3.6, "km/h", "kmh", "kph"); add(.speed, 0.44704, "mph")
        add(.temperature, 0, "c", "°c", "celsius"); add(.temperature, 0, "f", "°f", "fahrenheit")
        add(.temperature, 0, "k", "kelvin")
        return u
    }()

    private static func conversion(_ s: String) -> Answer? {
        // "<expr> <unit> (to|in|as|->|=) <unit>", the number part may be an expression.
        let parts = s.replacingOccurrences(of: "->", with: " to ").split(separator: " ").map(String.init)
        guard parts.count >= 3, let sep = parts.lastIndex(where: { ["to", "in", "as", "="].contains($0) }),
              sep == parts.count - 2, sep >= 1 else { return nil }
        var fromUnit = parts[sep - 1], numberText = parts[..<(sep - 1)].joined(separator: " ")
        let toUnit = parts[sep + 1]
        if numberText.isEmpty {  // "10km to mi": split the number off the unit
            guard let i = fromUnit.firstIndex(where: { $0.isLetter || $0 == "°" || $0 == "\"" }) else { return nil }
            numberText = String(fromUnit[..<i]); fromUnit = String(fromUnit[i...])
        }
        guard let (fk, ff) = units[fromUnit], let (tk, tf) = units[toUnit], fk == tk,
              let n = evaluate(numberText) else { return nil }
        let v: Double
        if fk == .temperature {
            let kelvin: Double = ["c", "°c", "celsius"].contains(fromUnit) ? n + 273.15
                : ["f", "°f", "fahrenheit"].contains(fromUnit) ? (n - 32) * 5 / 9 + 273.15 : n
            v = ["c", "°c", "celsius"].contains(toUnit) ? kelvin - 273.15
                : ["f", "°f", "fahrenheit"].contains(toUnit) ? (kelvin - 273.15) * 9 / 5 + 32 : kelvin
        } else {
            v = n * ff / tf
        }
        return Answer(value: format(v), detail: "\(format(n)) \(fromUnit) → \(toUnit)")
    }
}
