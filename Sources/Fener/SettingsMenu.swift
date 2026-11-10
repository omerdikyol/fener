import AppKit

/// fener's own settings as a menu (`fener show preferences`, Setup > fener Settings): one row
/// per option with its current value, grouped as Panel, Search, Files, Apps, Clipboard,
/// Learning. Toggles flip in place, choices open a list, lists of
/// folders open config.toml. Every change is written with ConfigEditor, so the file keeps
/// its comments, and applied at once.

/// Writes one key to config.toml (or quicklinks.toml) and applies it now.
func setSetting(_ section: String?, _ key: String, _ value: ConfigEditor.Value, file: String = "config.toml") {
    let url = configDir.appendingPathComponent(file)
    let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    let out = ConfigEditor.set(text, section: section, key: key, value: value)
    do {
        try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        try out.write(to: url, atomically: true, encoding: .utf8)
        Log.info("settings: \(file) \(section.map { $0 + "." } ?? "")\(key) = \(value.toml)")
    } catch {
        Log.error("settings: cannot write \(file): \(error.localizedDescription)")
    }
    applySettings()
}

private func toggle(_ title: String, _ on: Bool, _ section: String?, _ key: String) -> Item {
    var i = Item(id: "pref:\(section ?? "").\(key)", title: title, subtitle: on ? "on" : "off",
                 icon: sf(on ? "nf-md-toggle_switch" : "nf-md-toggle_switch_off_outline"),
                 run: { setSetting(section, key, .bool(!on)) })
    i.then = .stay
    return i
}

/// A row that opens a list of choices; picking one writes it and goes back.
private func choice<T: Equatable>(_ title: String, _ current: T, _ options: [(label: String, value: T)],
                                  icon: String, write: @escaping (T) -> Void) -> Item {
    let currentLabel = options.first { $0.value == current }?.label ?? "\(current)"
    return Item(id: "pref:" + title, title: title, subtitle: currentLabel, accessory: "›", icon: sf(icon), submenu: {
        Mode(prompt: title + "…") { q in
            options.compactMap { o -> Item? in
                guard q.isEmpty || Fuzzy.score(q, o.label) != nil else { return nil }
                var i = Item(id: "pref:\(title):\(o.label)", title: o.label, subtitle: o.value == current ? "current" : "",
                             icon: sf(o.value == current ? "nf-md-radiobox_marked" : "nf-md-radiobox_blank"), run: { write(o.value) })
                i.then = .back
                return i
            }
        }
    })
}


private func days(_ n: [Int]) -> [(label: String, value: Int)] { n.map { ("\($0) day\($0 == 1 ? "" : "s")", $0) } }

func settingsMenuItems(_ q: String) -> [Item] {
    let c = config
    let themes = (["tokyo-night"] + ((try? FileManager.default.contentsOfDirectory(atPath: configDir.appendingPathComponent("themes").path)) ?? [])
        .filter { $0.hasSuffix(".toml") }.map { String($0.dropLast(5)) })
    let terminalIds = ["Ghostty": "com.mitchellh.ghostty", "Terminal": "com.apple.Terminal", "iTerm": "com.googlecode.iterm2",
                       "WezTerm": "com.github.wez.wezterm", "kitty": "net.kovidgoyal.kitty", "Alacritty": "org.alacritty", "Warp": "dev.warp.Warp-Stable"]
    let terminals = ["Ghostty", "Terminal", "iTerm", "WezTerm", "kitty", "Alacritty", "Warp"].filter {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: terminalIds[$0]!) != nil || $0 == c.terminalApp
    }
    let editors = Editors.all.filter { $0.app != nil || $0.key == c.editor }
    let browsers = ["helium", "chrome", "brave", "arc", "edge", "vivaldi", "chromium"].filter {
        FileManager.default.fileExists(atPath: NSHomeDirectory() + "/Library/Application Support/" + Bookmarks.folders[$0]!) || $0 == c.browser
    } + ["none"]
    func editFile(_ title: String, _ subtitle: String) -> Item {
        Item(id: "pref:edit:" + title, title: title, subtitle: subtitle, icon: sf("nf-md-pencil"),
             run: { Editors.current.open(configDir.appendingPathComponent("config.toml").path) })
    }

    let groups: [(String, [Item])] = [
        ("Panel", [
            choice("Position", c.panelPosition, [("Center", "center"), ("Upper third", "upper"), ("Top", "top")], icon: "nf-md-arrow_expand_vertical") {
                setSetting("panel", "position", .string($0)) },
            choice("Screen", c.panelScreen, [("Where the mouse is", "mouse"), ("Where the front window is", "focused"), ("With the menu bar", "main")],
                   icon: "nf-md-monitor") { setSetting("panel", "screen", .string($0)) },
            toggle("Close when focus leaves", c.closeOnBlur, "panel", "close_on_blur"),
            toggle("Animation", c.animation, "panel", "animation"),
            choice("Animation speed", c.animationMs, [("Fast (80 ms)", 80), ("Normal (120 ms)", 120), ("Relaxed (200 ms)", 200)],
                   icon: "nf-md-speedometer") { setSetting("panel", "animation_ms", .int($0)) },
            choice("Theme", c.theme, themes.map { ($0, $0) }, icon: "nf-md-palette") { setSetting(nil, "theme", .string($0)) },
            choice("Empty search shows", c.home, [("Main menu", "menu"), ("Apps", "")], icon: "nf-md-home") {
                setSetting(nil, "home", .string($0)) },
        ]),
        ("Search", [
            Item(id: "pref:sources", title: "Sources in the main search", subtitle: "\(c.sources.count) of \(Config.allSources.count)",
                 accessory: "›", icon: sf("nf-md-format_list_checks"), submenu: { sourcesMode() }),
            toggle("Web search row", c.webFallback, "search", "web_fallback"),
            choice("Web search engine", quicklinks.defaultKeyword, quicklinks.links.map { ($0.name, $0.keyword) }, icon: "nf-md-web") {
                setSetting(nil, "default", .string($0), file: "quicklinks.toml") },
            toggle("Learn from searches", c.learnQueries, nil, "learn_queries"),
            toggle("Currency conversion (ECB rates)", c.currencyEnabled, "currency", "enabled"),
        ]),
        ("Files", [
            choice("File search results", c.fileLimit, [("30", 30), ("60", 60), ("120", 120), ("250", 250)], icon: "nf-md-file_search") {
                setSetting("files", "limit", .int($0)) },
            choice("Recent Files go back", c.recentDays, days([3, 7, 14, 30, 90]), icon: "nf-md-file_clock") {
                setSetting("files", "recent_days", .int($0)) },
            choice("Screenshot thumbnails", c.screenshotThumbnails, [("None", 0), ("20", 20), ("40", 40), ("80", 80)], icon: "nf-md-image") {
                setSetting("files", "screenshot_thumbnails", .int($0)) },
            editFile("Search folders", c.fileRoots.joined(separator: ", ") + " · edit in config.toml [files] roots"),
        ]),
        ("Apps", [
            choice("Bookmarks from", c.browser, browsers.map { ($0 == "none" ? "None" : $0.prefix(1).uppercased() + $0.dropFirst(), $0) },
                   icon: "nf-md-bookmark") { setSetting("apps", "browser", .string($0)) },
            choice("Editor", c.editor, editors.map { ($0.name, $0.key) }, icon: "nf-md-pencil") { setSetting("apps", "editor", .string($0)) },
            choice("Terminal", c.terminalApp, terminals.map { ($0, $0) }, icon: "nf-md-console_line") { setSetting("apps", "terminal", .string($0)) },
            editFile("App folders", "\(c.appFolders.count) folders · edit in config.toml [apps] folders"),
        ]),
        ("Clipboard", [
            toggle("Clipboard history", c.clipboardEnabled, "clipboard", "enabled"),
            choice("Keep clipboard items", c.clipboardKeepDays, days([1, 7, 30, 90, 365]), icon: "nf-md-clipboard_text") {
                setSetting("clipboard", "keep_days", .int($0)) },
            choice("Clipboard history size", c.clipboardMaxItems, [("50", 50), ("200", 200), ("500", 500), ("1000", 1000)], icon: "nf-md-counter") {
                setSetting("clipboard", "max_items", .int($0)) },
            editFile("Apps never recorded", (c.clipboardIgnoreApps.isEmpty ? "none" : c.clipboardIgnoreApps.joined(separator: ", "))
                     + " · edit in config.toml [clipboard] ignore_apps"),
        ]),
        ("Learning", [
            choice("Usage fades after", c.usageHalfLifeDays, [3.0, 7, 14, 30].map { ("\(Int($0)) days", $0) }, icon: "nf-md-history") {
                setSetting("learning", "usage_half_life_days", .double($0)) },
            choice("Learned searches fade after", c.searchHalfLifeDays, [7.0, 14, 30, 60].map { ("\(Int($0)) days", $0) }, icon: "nf-md-history") {
                setSetting("learning", "search_half_life_days", .double($0)) },
        ]),
        ("Files fener uses", [
            Item(id: "pref:open-config", title: "Open config.toml", subtitle: "every option, with comments", icon: sf("nf-md-file_cog"),
                 run: { Editors.current.open(configDir.appendingPathComponent("config.toml").path) }),
            Item(id: "pref:open-folder", title: "Open the config folder", subtitle: "menus, themes, snippets, quicklinks", icon: sf("nf-fa-folder"),
                 run: { NSWorkspace.shared.open(configDir) }),
            Item(id: "pref:open-log", title: "Show the log", icon: sf("nf-md-text_box_search"), run: { Editors.current.open(Log.file.path) }),
        ]),
    ]
    // Each row shows its group after its value: "center · Panel".
    let all = groups.flatMap { g, rows in rows.map { var r = $0; r.subtitle = r.subtitle.isEmpty ? g : r.subtitle + " · " + g; return r } }
    // Rows match on their title or current value.
    return q.isEmpty ? all : all.filter { Fuzzy.score(q, $0.title) != nil || Fuzzy.score(q, $0.subtitle) != nil }
}

/// Each main-search source as a check row; Return flips it and stays.
private func sourcesMode() -> Mode {
    let names = ["apps": "Apps", "menus": "Menus", "system": "System actions", "snippets": "Snippets", "settings": "Settings panes",
                 "projects": "Editor projects", "generators": "Generators (UUID, password…)", "bookmarks": "Bookmarks", "windows": "Windows"]
    return Mode(prompt: "Sources…") { q in
        Config.allSources.filter { q.isEmpty || Fuzzy.score(q, names[$0] ?? $0) != nil }.map { s in
            let on = config.sources.contains(s)
            var i = Item(id: "pref:source:" + s, title: names[s] ?? s, subtitle: on ? "on" : "off",
                         icon: sf(on ? "nf-md-checkbox_marked" : "nf-md-checkbox_blank_outline"), run: {
                var next = config.sources
                if on { next.remove(s) } else { next.insert(s) }
                setSetting("search", "sources", .strings(Config.allSources.filter(next.contains)))
            })
            i.then = .stay
            return i
        }
    }
}
