import AppKit

/// Built-in modes for `fener show <name>` and `menu = "<name>"`; a user menu with the same name wins.
func builtinMode(_ name: String) -> Mode? { builtins[name] }
let builtins: [String: Mode] = [
    "apps": Mode(prompt: "Apps…", search: apps.search),
    "clipboard": Mode(prompt: "Clipboard…", search: clipboardItems),
    "quit": Mode(prompt: "Quit…", search: quitItems),
    "snippets": Mode(prompt: "Snippets…", search: snippetItems),
    "settings": Mode(prompt: "Settings…", search: settingsItems),
    "audio": Mode(prompt: "Audio…", search: audioItems),
    "bookmarks": Mode(prompt: "Bookmarks…", width: 560, search: bookmarkItems),
    "projects": Mode(prompt: "Projects…", width: 480, search: projectItems),
    "recent": Mode(prompt: "Recent Files…", width: 560) { spotlightItems(recentFiles, $0, glyph: "nf-md-file_clock") },
    "screenshots": Mode(prompt: "Screenshots…", width: 560) { spotlightItems(screenshots, $0, glyph: "nf-md-image") },
    "generate": Mode(prompt: "Generate…", width: 560, search: generatorItems),
    "processes": Mode(prompt: "Processes… (:port)", width: 480, search: processItems),
    "dictionary": Mode(prompt: "Define…", width: 600, search: definitionItems),
    "system": Mode(prompt: "System…", search: systemItems),
    "emoji": Mode(prompt: "Emoji…", search: emojiItems),
    "files": Mode(prompt: "Files…", search: files.search),
    "windows": Mode(prompt: "Windows…") { windows.search($0, all: true) },
    "calc": Mode(prompt: "Calculate…") { q in Calc.answer(q, forced: true).map { [calcItem($0)] } ?? [] },
]

var prefixes: [(String, (String) -> [Item])] {
    let all: [(String, (String) -> [Item])] = [
        ("calc", { q in answerItem(q, forced: true).map { [$0] } ?? [] }),
        ("files", files.search),
        ("emoji", emojiItems),
        ("clipboard", { config.clipboardEnabled ? clipboardItems($0) : [] }),
        ("menus", { searchMenus($0, entries: true) }),
        ("windows", { windows.search($0, all: true) }),
        ("snippets", snippetItems),
    ]
    // Longest prefix first, so "::" could coexist with ":".
    return all.compactMap { name, f in config.prefixes[name].flatMap { $0.isEmpty ? nil : ($0, f) } }
        .sorted { $0.0.count > $1.0.count }
}

func problemItems() -> [Item] {
    problems.map { m in
        Item(id: "problem:" + m, title: m, subtitle: "", icon: sf("nf-md-alert"),
             run: { NSWorkspace.shared.open(configDir) })
    }
}

/// An alias typed exactly: opens its menu or built-in view, or launches the app of that name.
func aliasItem(_ word: String, _ target: String) -> Item? {
    if let m = menus.menus[target] {
        return Item(id: "alias:" + word, title: Menu.title(m.name), subtitle: "alias \(word)", accessory: "›",
                    icon: sf(m.icon.isEmpty ? "nf-md-format_list_bulleted" : m.icon), score: 20_000, submenu: { menuMode(m) })
    }
    if let b = builtinMode(target) {
        return Item(id: "alias:" + word, title: Menu.title(target), subtitle: "alias \(word)", accessory: "›",
                    icon: sf("nf-md-format_list_bulleted"), score: 20_000, submenu: { b })
    }
    guard var app = apps.search(target).first else { return nil }
    app.subtitle = "alias \(word)"; app.score = 20_000
    return app
}

/// The menu listed while the search is empty (config `home`), if it exists as a TOML menu.
var homeMenu: Menu? {
    guard !config.home.isEmpty, let m = menus.menus[config.home], m.executable == nil else { return nil }
    return m
}

let root = Mode(prompt: "Search…", dynamicWidth: { homeMenu?.width }) { raw in
    for (p, search) in prefixes where raw.hasPrefix(p) {
        return search(String(raw.dropFirst(p.count)).trimmingCharacters(in: .whitespaces))
    }
    if raw.isEmpty {
        guard let m = homeMenu else { return problemItems() + apps.search("") }
        return problemItems() + rank(m.entries, "").map { entryItem($0.0, of: m, score: $0.1) }
    }
    // Windows rank a bit below apps and menus: long titles match short queries by accident.
    var top: [Item] = [], links: [Item] = []
    if let target = config.aliases[raw.lowercased().trimmingCharacters(in: .whitespaces)], let a = aliasItem(raw, target) { top.append(a) }
    if let a = answerItem(raw, forced: false) { top.append(a) }
    // "define <word>": a row that opens the wide dictionary view for that word.
    if raw.lowercased().hasPrefix("define "), case let w = String(raw.dropFirst(7)).trimmingCharacters(in: .whitespaces), !w.isEmpty {
        var dict = builtins["dictionary"]!
        dict.query = w
        let first = Definitions.lookup(w).map { Definitions.header(Definitions.senses($0).first ?? "").sense } ?? "no definition found"
        top.append(Item(id: "define", title: "Define “\(w)”", subtitle: first, accessory: "›",
                        icon: sf("nf-md-book_open_variant"), score: 10_000, submenu: { dict }))
    }
    if let (link, q) = quicklinks.match(raw) {
        if q.isEmpty { links.append(linkItem(link, "", score: 0)) } else { top.append(linkItem(link, q, score: 10_000)) }
    }
    let merged = merge(apps.search(raw), searchMenus(raw, entries: true), systemItems(raw), links,
                       snippetItems(raw).map { var i = $0; i.score -= 2; i.subtitle = "snippet"; return i },
                       settingsItems(raw).map { var i = $0; i.score -= 3; return i },
                       projectItems(raw).map { var i = $0; i.score -= 4; i.subtitle = "VS Code · " + i.subtitle; return i },
                       bookmarkItems(raw).map { var i = $0; i.score -= 6; return i },
                       // Generators only for a clear word ("uuid", "password 24"), not stray letters.
                       (raw.count >= 3 ? generatorItems(raw) : []).filter { $0.score > 40 }.map { var i = $0; i.score -= 5; return i },
                       windows.search(raw, all: false).map { var i = $0; i.score -= 10; return i })
    // Last row: search the web with the default engine (it only opens the browser).
    let web = quicklinks.defaultEngine.map { [linkItem($0, raw, score: Int.min)] } ?? []
    return top + merged + web
}
