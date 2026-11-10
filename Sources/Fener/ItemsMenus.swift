import AppKit

/// Fuzzy-ranks menu entries; empty query keeps file order. Subtitles count inside a menu,
/// but not in the global search, where they surfaced unrelated rows.
func rank(_ entries: [MenuEntry], _ q: String, subtitles: Bool = true) -> [(MenuEntry, Int)] {
    if q.isEmpty { return entries.enumerated().map { ($1, -$0) } }
    return entries.compactMap { e in
        [Fuzzy.score(q, e.name), subtitles ? Fuzzy.score(q, e.subtitle) : nil].compactMap { $0 }.max().map { (e, $0) }
    }.sorted { $0.1 > $1.1 }
}

func message(_ text: String) -> Mode {
    Mode(prompt: text) { _ in [] }
}

func menuMode(_ m: Menu) -> Mode {
    let box = Box(m.entries), key = UUID().uuidString
    func load() {
        menus.list(m) { entries, refresh in
            box.value = entries
            launcher.refilter()
            // Keep refreshing only while this very menu is the one on screen.
            if let refresh {
                DispatchQueue.main.asyncAfter(deadline: .now() + refresh) {
                    if launcher.isVisible, launcher.openMenu?.key == key { load() }
                }
            }
        }
    }
    if m.executable != nil { load() }
    return Mode(prompt: m.prompt, width: m.width, key: key) { q in rank(box.value, q).map { entryItem($0.0, of: m, score: $0.1) } }
}

func entryItem(_ e: MenuEntry, of m: Menu, score: Int) -> Item {
    var item = Item(id: "menu:\(m.name):\(e.name)", title: e.name, subtitle: e.subtitle,
                    accessory: e.menu.isEmpty ? "" : "›", icon: Icons.named(e.icon, theme: theme), score: score)
    if let file = m.file {
        item.actions = {
            var a = [Act.make("Edit Menu File", "nf-md-pencil") { Shell.run("/usr/bin/open", ["-t", file.path]) }]
            if !e.command.isEmpty { a.append(Act.copy("Copy Command", e.command)) }
            return a
        }
    }
    let choice = e.value.isEmpty ? e.name : e.value
    let env = ["FENER_MENU": m.name, "FENER_CHOICE": choice]
    if !e.menu.isEmpty {
        item.submenu = { menus.menus[e.menu].map(menuMode) ?? builtinMode(e.menu) ?? message("No menu named \(e.menu)") }
        return item
    }
    if !e.command.isEmpty {
        item.run = e.terminal ? { Shell.inTerminal(e.command, template: config.terminal, extraEnv: env) }
                              : { Shell.sh(e.command, extraEnv: env) }
    } else if let exe = m.executable, e.value != "\u{0}" {
        item.run = { Shell.run(exe.path, [choice], extraEnv: env) }  // dmenu style: chosen entry comes back as $1
    }
    if e.confirm {
        let run = item.run
        item.accessory = "›"
        item.submenu = { Mode(prompt: "\(e.name)?", width: m.width) { _ in [
            Item(id: "confirm:yes", title: "Yes", icon: sf("nf-md-check"), run: run),
            Item(id: "confirm:no", title: "Cancel", icon: sf("nf-md-close")),
        ] } }
    }
    return item
}

/// The menus themselves, plus (when `entries`) every static entry, matched against `q`.
func searchMenus(_ q: String, entries: Bool) -> [Item] {
    var out: [Item] = []
    for m in menus.menus.values.sorted(by: { $0.name < $1.name }) {
        let title = Menu.title(m.name)
        if let s = q.isEmpty ? 0 : Fuzzy.score(q, title) {
            out.append(Item(id: "menu:\(m.name)", title: title, subtitle: "menu", accessory: "›",
                            icon: Icons.named(m.icon.isEmpty ? "nf-md-format_list_bulleted" : m.icon, theme: theme),
                            score: s, submenu: { menuMode(m) }))
        }
        guard entries, !q.isEmpty else { continue }
        for (e, s) in rank(m.entries, q, subtitles: false) {
            var item = entryItem(e, of: m, score: s - 4)
            if item.subtitle.isEmpty { item.subtitle = title }
            out.append(item)
        }
    }
    return out
}

/// Merges sources by score; on ties keeps the order sources were given in.
func merge(_ lists: [Item]...) -> [Item] {
    lists.joined().enumerated().sorted { a, b in
        a.element.score != b.element.score ? a.element.score > b.element.score : a.offset < b.offset
    }.map(\.element)
}
