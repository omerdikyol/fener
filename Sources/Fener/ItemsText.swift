import AppKit

// MARK: snippets and definitions

let snippets = Snippets(dir: configDir.appendingPathComponent("snippets"))

func snippetItems(_ q: String) -> [Item] {
    snippets.all.compactMap { sn in
        guard let s = q.isEmpty ? 0 : Fuzzy.score(q, sn.name) else { return nil }
        let first = sn.text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        return Item(id: "snippet:" + sn.name, title: sn.name, subtitle: first, icon: sf("nf-md-text_box_edit"),
                    run: { Clipboard.copyText(Snippets.expand(sn.text)) }, score: s)
    }.sorted { $0.score > $1.score }
}

func definitionItems(_ q: String) -> [Item] {
    let word = q.trimmingCharacters(in: .whitespaces)
    guard let text = Definitions.lookup(word) else {
        return word.isEmpty ? [] : [Item(id: "define:none", title: "No definition for “\(word)”",
                                         subtitle: "dictionaries enabled in Dictionary.app", icon: sf("nf-md-book_open_variant"))]
    }
    var senses = Definitions.senses(text)
    let (header, firstSense) = Definitions.header(senses.first ?? "")
    if !senses.isEmpty { senses[0] = firstSense }
    let open = Item(id: "define:open", title: word, subtitle: (header.isEmpty ? "" : header + "  ·  ") + "⏎ opens Dictionary",
                    icon: sf("nf-md-book_open_variant"),
                    run: { if let u = URL(string: "dict://" + Quicklink.encode(word)) { NSWorkspace.shared.open(u) } })
    return [open] + senses.filter { !$0.isEmpty }.enumerated().map { i, s in
        Item(id: "define:\(i)", title: s, subtitle: "⏎ copies", icon: sf("nf-md-format_quote_close"), run: { Clipboard.copyText(s) })
    }
}

func clipboardItems(_ q: String) -> [Item] {
    var out: [Item] = []
    for c in clipboard.clips {
        let when = ago.localizedString(for: c.date, relativeTo: Date())
        var title: String, sub: String, icon: NSImage?
        switch c.kind {
        case .text:
            title = String(c.text.split(whereSeparator: \.isNewline).first.map { $0.trimmingCharacters(in: .whitespaces) } ?? "").prefix(200).description
            let lines = c.text.split(whereSeparator: \.isNewline).count
            sub = (lines > 1 ? "\(lines) lines · " : "") + when
            icon = sf("nf-md-text_box_outline")
        case .files:
            let paths = c.text.split(separator: "\n")
            title = paths.map { ($0 as NSString).lastPathComponent }.joined(separator: ", ")
            sub = (paths.count > 1 ? "\(paths.count) files · " : "file · ") + when
            icon = paths.first.map { NSWorkspace.shared.icon(forFile: String($0)) }
        case .image:
            title = "Image \(c.width)×\(c.height)"
            sub = when
            icon = clipboard.imageURL(c).flatMap { Icons.named($0.path, theme: theme) }
        }
        var score = 0
        if !q.isEmpty {
            guard let s = Fuzzy.score(q, c.kind == .image ? title : String(c.text.prefix(300))) else { continue }
            score = s
        }
        out.append(Item(id: "clip:" + c.id, title: title, subtitle: sub, icon: icon, run: { clipboard.copy(c) }, score: score))
    }
    if q.isEmpty {
        if !clipboard.clips.isEmpty {
            let clear = SystemAction(name: "Clear Clipboard History", subtitle: "", icon: "nf-md-delete", confirm: true) { clipboard.clear() }
            out.append(Item(id: "clip:clear", title: clear.name, icon: sf("nf-md-delete"), submenu: { confirm(clear) }))
        }
        return out
    }
    return out.sorted { $0.score > $1.score }
}

func emojiItems(_ q: String) -> [Item] {
    Emoji.search(q).map { e in
        Item(id: "emoji:" + e.code, title: e.name, subtitle: e.code, icon: Icons.named(e.char, theme: theme),
             run: { Clipboard.copyText(e.char) })
    }
}

/// "password 32", "pin 6", "lorem 3": the number sets the length.
func generatorItems(_ q: String) -> [Item] {
    let parts = q.lowercased().split(separator: " ")
    let n = parts.count > 1 ? Int(parts[1]) : nil, word = parts.first.map(String.init) ?? ""
    let sentences = Generators.lorem.split(separator: ".").map { $0.trimmingCharacters(in: .whitespaces) + "." }
    let all: [(String, String, String)] = [
        ("UUID", UUID().uuidString.lowercased(), "nf-md-identifier"),
        ("Password", Generators.password(length: n ?? 20, symbols: true), "nf-md-form_textbox_password"),
        ("Password (letters and digits)", Generators.password(length: n ?? 20, symbols: false), "nf-md-form_textbox_password"),
        ("PIN", Generators.pin(n ?? 6), "nf-md-numeric"),
        ("Lorem Ipsum", sentences.prefix(max(1, min(n ?? 3, sentences.count))).joined(separator: " "), "nf-md-format_paragraph"),
    ]
    return all.compactMap { title, value, icon in
        guard let s = word.isEmpty ? 0 : Fuzzy.score(word, title) else { return nil }
        return Item(id: "gen:" + title, title: value, subtitle: title + "  ·  ⏎ copies", icon: sf(icon),
                    run: { Clipboard.copyText(value) }, score: s)
    }.sorted { $0.score > $1.score }
}
