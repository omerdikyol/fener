import CoreText
import Foundation

/// Emoji and symbols, built from the Unicode names that ship with the OS (no data file):
/// emoji blocks, arrows, math, technical and geometric symbols, letterlike, currency,
/// Greek letters, plus country flags named by Locale.
/// ponytail: single code points and flags only; ZWJ sequences and skin tones are not listed.
enum Emoji {
    struct Entry { let char: String; let name: String; let folded: [Character]; let code: String }

    static let ranges: [ClosedRange<UInt32>] = [
        0x1F300...0x1FAFF, 0x2600...0x27BF,                   // emoji, misc symbols, dingbats
        0x2190...0x21FF, 0x2200...0x22FF, 0x2300...0x23FF,    // arrows, math, technical
        0x25A0...0x25FF, 0x2100...0x214F, 0x20A0...0x20CF,    // geometric, letterlike, currency
        0x0391...0x03C9, 0x00A9...0x00AE,                     // Greek, © ®
    ]

    /// True when some installed font has a glyph (CoreText falls back to LastResort otherwise).
    private static let base = CTFontCreateWithName("Helvetica" as CFString, 14, nil)
    static func renderable(_ s: String) -> Bool {
        let font = CTFontCreateForString(base, s as CFString, CFRange(location: 0, length: (s as NSString).length))
        return CTFontCopyPostScriptName(font) as String != "LastResort"
    }

    static let all: [Entry] = {
        var out: [Entry] = []
        for r in ranges {
            for v in r {
                guard let s = Unicode.Scalar(v), let name = s.properties.name, s.properties.generalCategory != .unassigned,
                      s.properties.generalCategory != .control, !name.isEmpty else { continue }
                let n = name.lowercased(), ch = String(Character(s))
                guard renderable(ch) else { continue }
                out.append(Entry(char: ch, name: n, folded: Fuzzy.fold(n), code: String(format: "U+%04X", v)))
            }
        }
        let en = Locale(identifier: "en")
        for region in Locale.Region.isoRegions where region.identifier.count == 2 {
            let code = region.identifier.uppercased()
            guard code.allSatisfy({ $0.isLetter }), let name = en.localizedString(forRegionCode: code) else { continue }
            let flag = String(String.UnicodeScalarView(code.unicodeScalars.compactMap { Unicode.Scalar(0x1F1A5 + $0.value) }))
            let n = "flag \(name.lowercased())"
            out.append(Entry(char: flag, name: n, folded: Fuzzy.fold(n), code: code))
        }
        return out
    }()

    static func search(_ q: String, limit: Int = 60) -> [Entry] {
        let fq = Fuzzy.fold(q).filter { $0 != " " }
        if fq.isEmpty { return Array(all.prefix(limit)) }
        return all.compactMap { e in
            Fuzzy.score(fq, folded: e.folded, original: Array(e.name)).map { (e, $0) }
        }.sorted { $0.1 > $1.1 }.prefix(limit).map(\.0)
    }
}
