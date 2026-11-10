import AppKit

/// Built-in modes for `fener show <name>` and `menu = "<name>"`; a user menu with the same name wins.
func builtinMode(_ name: String) -> Mode? { builtins[name] }
let builtins: [String: Mode] = [
    "apps": Mode(prompt: "Apps…", search: apps.search),
    "clipboard": Mode(prompt: "Clipboard…", search: clipboardItems),
    "quit": Mode(prompt: "Quit…", search: quitItems),
    "snippets": Mode(prompt: "Snippets…", search: snippetItems),
    "used": Mode(prompt: "Recently Used…", width: 480, search: recentItems),
    "preferences": Mode(prompt: "fener Settings…", width: 560, search: settingsMenuItems),
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

/// The match quality non-app rows need in the global search: about a word start or a run of
/// consecutive letters per typed character, so one or two letters do not pull in scattered
/// matches from every bookmark and settings pane.
func minimumScore(_ query: String) -> Int {
    18 * min(8, query.filter { $0 != " " }.count)
}

/// Rows worth keeping in Recently Used and learning from: anything but changing values,
/// problems and the action/confirm rows themselves. Apps count here.
func remembered(_ id: String) -> Bool {
    !id.isEmpty && !["calc", "gen:", "color:", "define", "confirm:", "problem:", "action:", "quit:", "proc:", "link:", "alias:"]
        .contains(where: { id.hasPrefix($0) })
}

/// Recently Used: the last picks, looked up again in the current sources (an app by its
/// path, anything else through the main search by title). Rows that no longer exist are skipped.
func recentItems(_ q: String) -> [Item] {
    learning.recent.compactMap { r -> Item? in
        guard q.isEmpty || Fuzzy.score(q, r.title) != nil else { return nil }
        let found = r.id.hasPrefix("/") ? apps.search(r.title).first { $0.id == r.id }
                                        : root.search(r.title).first { $0.id == r.id }
        guard var item = found else { return nil }
        item.subtitle = ago.localizedString(for: Date(timeIntervalSince1970: r.time), relativeTo: Date())
        return item
    }
}

/// Ids worth remembering: not changing values (calculator, generated passwords) and not
/// apps, which keep their own launch counts.
func tracked(_ id: String) -> Bool {
    !id.isEmpty && !id.hasPrefix("/") && !["calc", "gen:", "color:", "define", "confirm:", "quit:", "proc:", "problem:", "action:"]
        .contains(where: { id.hasPrefix($0) })
}

func usageBoost(_ id: String) -> Int {
    guard tracked(id) else { return 0 }
    return Int(12 * log2(1 + apps.frecency.value(id)))
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
    // Apps compete on their own; every other source must clear a quality bar and then gets
    // the same usage boost apps have, so rows you pick often rise.
    func other(_ items: [Item], penalty: Int, subtitle: ((String) -> String)? = nil) -> [Item] {
        items.filter { $0.score >= minimumScore(raw) || learned[$0.id] != nil }.map { i in
            var i = i
            i.score += usageBoost(i.id) + (learned[i.id] ?? 0) - penalty
            if let subtitle { i.subtitle = subtitle(i.subtitle) }
            return i
        }
    }
    let learned = learning.boosts(for: raw)
    // Each source runs only when listed in [search] sources.
    func source(_ name: String, _ items: @autoclosure () -> [Item]) -> [Item] { config.sources.contains(name) ? items() : [] }
    let merged = merge(source("apps", apps.search(raw).map { var i = $0; i.score += learned[i.id] ?? 0; return i }), links,
                       other(source("menus", searchMenus(raw, entries: true)), penalty: 0),
                       other(source("system", systemItems(raw)), penalty: 0),
                       other(source("snippets", snippetItems(raw)), penalty: 2, subtitle: { _ in "snippet" }),
                       other(source("settings", settingsItems(raw)), penalty: 3),
                       other(source("projects", projectItems(raw)), penalty: 4, subtitle: { "\(Editors.current.name) · " + $0 }),
                       other(source("generators", generatorItems(raw)), penalty: 5),
                       other(source("bookmarks", bookmarkItems(raw)), penalty: 6),
                       other(source("windows", windows.search(raw, all: false)), penalty: 10))
    // Last row: search the web with the default engine (it only opens the browser).
    let web = config.webFallback ? quicklinks.defaultEngine.map { [linkItem($0, raw, score: Int.min)] } ?? [] : []
    return top + merged + web
}
