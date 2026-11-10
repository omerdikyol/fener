import AppKit

// `fener` runs the resident agent app; `fener toggle|show|hide|reload|ping` talks to it
// over a Unix socket. App flags: `--show` opens the panel at launch, `--demo` adds a plain
// gradient backdrop for screenshots, `--query <text>` prefills the search, `--bench`
// prints scan and search timings and exits.

let args = CommandLine.arguments
if args.count > 1, IPC.commands.contains(args[1]) {
    exit(IPC.send(Array(args.dropFirst())))  // client: never touches NSApplication
}

if !args.contains("--bench"), IPC.isRunning() {
    print("fener is already running")
    exit(0)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)  // same effect as LSUIElement: no Dock icon, no menu bar
setvbuf(stdout, nil, _IOLBF, 0)

var theme = Theme()
let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("fener")
let t0 = CACurrentMediaTime()
let apps = AppProvider(frecency: Frecency(url: cacheDir.appendingPathComponent("frecency.json")))
let scanMs = (CACurrentMediaTime() - t0) * 1000

if args.contains("--bench") {
    print(String(format: "scanned %d apps in %.1f ms", apps.apps.count, scanMs))
    for q in ["", "s", "saf", "sys set", "actmon", "xyzzy"] {
        let t = CACurrentMediaTime()
        var r: [Item] = []
        for _ in 0..<100 { r = apps.search(q) }
        print(String(format: "search %-9@ %4d results, %.2f ms each, top: %@", "\"\(q)\"" as NSString, r.count,
                     (CACurrentMediaTime() - t) * 10, r.prefix(3).map(\.title).joined(separator: ", ") as NSString))
    }
    var t = CACurrentMediaTime()
    let n = Emoji.all.count
    print(String(format: "emoji index: %d entries in %.1f ms", n, (CACurrentMediaTime() - t) * 1000))
    t = CACurrentMediaTime()
    for _ in 0..<20 { _ = Emoji.search("heart") }
    print(String(format: "emoji search \"heart\": %.2f ms each", (CACurrentMediaTime() - t) * 50))
    t = CACurrentMediaTime()
    for _ in 0..<1000 { _ = Calc.answer("10 km to mi"); _ = Calc.answer("2 * (3 + 4)^2") }
    print(String(format: "calc: %.3f ms per answer", (CACurrentMediaTime() - t) / 2))
    exit(0)
}

let configDir = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".config/fener")
let menus = MenuStore(dir: configDir.appendingPathComponent("menus"))
let windows = WindowProvider()

final class Box<T> { var value: T; init(_ v: T) { value = v } }

/// Fuzzy-ranks menu entries; empty query keeps file order.
func rank(_ entries: [MenuEntry], _ q: String) -> [(MenuEntry, Int)] {
    if q.isEmpty { return entries.enumerated().map { ($1, -$0) } }
    return entries.compactMap { e in
        [Fuzzy.score(q, e.name), Fuzzy.score(q, e.subtitle)].compactMap { $0 }.max().map { (e, $0) }
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
        for (e, s) in rank(m.entries, q) {
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

let clipboard = Clipboard(dir: cacheDir.appendingPathComponent("clipboard"))
let files = FileSearch()
DispatchQueue.global(qos: .utility).async { _ = Emoji.all.count }  // build the emoji index early

func sf(_ name: String) -> NSImage? { Icons.named(name, theme: theme) }

func calcItem(_ a: Calc.Answer) -> Item {
    Item(id: "calc", title: a.value, subtitle: a.detail + "  ·  ⏎ copies", icon: sf("nf-md-calculator"),
         run: { Clipboard.copyText(a.value) }, score: 10_000)
}

func confirm(_ a: SystemAction) -> Mode {
    Mode(prompt: "\(a.name)?") { _ in [
        Item(id: "confirm:yes", title: "Yes, \(a.name.lowercased())", icon: sf(a.icon), run: a.run),
        Item(id: "confirm:no", title: "Cancel", icon: sf("nf-md-close")),
    ] }
}

func systemItems(_ q: String) -> [Item] {
    SystemAction.all.compactMap { a in
        guard let s = q.isEmpty ? 0 : Fuzzy.score(q, a.name) else { return nil }
        var item = Item(id: "system:" + a.name, title: a.name, subtitle: a.subtitle, icon: sf(a.icon), score: s)
        if a.confirm { item.submenu = { confirm(a) }; item.accessory = "›" } else { item.run = a.run }
        return item
    }
}

let ago = { () -> RelativeDateTimeFormatter in let f = RelativeDateTimeFormatter(); f.unitsStyle = .abbreviated; return f }()

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

/// Built-in modes for `fener show <name>` and `menu = "<name>"`; a user menu with the same name wins.
func builtinMode(_ name: String) -> Mode? { builtins[name] }
let builtins: [String: Mode] = [
    "apps": Mode(prompt: "Apps…", search: apps.search),
    "clipboard": Mode(prompt: "Clipboard…", search: clipboardItems),
    "system": Mode(prompt: "System…", search: systemItems),
    "emoji": Mode(prompt: "Emoji…", search: emojiItems),
    "files": Mode(prompt: "Files…", search: files.search),
    "windows": Mode(prompt: "Windows…") { windows.search($0, all: true) },
    "calc": Mode(prompt: "Calculate…") { q in Calc.answer(q, forced: true).map { [calcItem($0)] } ?? [] },
]

// MARK: settings (config.toml, themes/, menus/), hot reloaded

var config = Config()
var problems: [String] = []   // config, theme and menu errors, shown at the top of the empty search

/// Reads config.toml and the selected theme. Missing files mean defaults.
func loadSettings() -> (Config, Theme, [String]) {
    var p: [String] = []
    let cfgURL = configDir.appendingPathComponent("config.toml")
    let c = (try? String(contentsOf: cfgURL, encoding: .utf8)).map { Config.parse($0, problems: &p) } ?? Config()
    var th = Theme()
    let themeURL = configDir.appendingPathComponent("themes/\(c.theme).toml")
    if let text = try? String(contentsOf: themeURL, encoding: .utf8) {
        th = Theme.parse(text, name: c.theme, problems: &p)
    } else if c.theme != "tokyo-night" {
        p.append("config.toml: theme \(c.theme) not found in \(themeURL.deletingLastPathComponent().path); using tokyo-night")
    }
    if !Icons.fontHasNerdGlyphs(th) {
        p.append("themes/\(c.theme).toml: font \"\(th.fontFamily)\" has no Nerd Font glyphs; menu icons show as dots")
    }
    return (c, th, p)
}

func applySettings() {
    let (c, th, p) = loadSettings()
    menus.load()
    config = c
    problems = p + menus.errors
    clipboard.maxItems = c.clipboardMaxItems
    clipboard.maxItemBytes = c.clipboardMaxItemBytes
    if c.clipboardEnabled { clipboard.start() } else { clipboard.stop() }
    if th != theme {
        theme = th
        Icons.clearCache()
        let wasVisible = launcher.isVisible, open = launcher.openMenu
        launcher.tearDown()
        launcher = makeLauncher()
        if wasVisible { launcher.show(open) }
    } else {
        launcher.refilter()
    }
}

var prefixes: [(String, (String) -> [Item])] {
    let all: [(String, (String) -> [Item])] = [
        ("calc", { q in Calc.answer(q, forced: true).map { [calcItem($0)] } ?? [] }),
        ("files", files.search),
        ("emoji", emojiItems),
        ("clipboard", { config.clipboardEnabled ? clipboardItems($0) : [] }),
        ("menus", { searchMenus($0, entries: true) }),
        ("windows", { windows.search($0, all: true) }),
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
    let merged = merge(apps.search(raw), searchMenus(raw, entries: true), systemItems(raw),
                       windows.search(raw, all: false).map { var i = $0; i.score -= 10; return i })
    return (Calc.answer(raw).map { [calcItem($0)] } ?? []) + merged
}

func makeLauncher() -> Launcher {
    let l = Launcher(theme: theme, root: root)
    l.onShow = { apps.refresh(); windows.refresh(); menus.load() }
    l.prewarm()
    return l
}

do {
    let (c, th, p) = loadSettings()
    config = c; theme = th; problems = p + menus.errors
    clipboard.maxItems = c.clipboardMaxItems
    clipboard.maxItemBytes = c.clipboardMaxItemBytes
    if c.clipboardEnabled { clipboard.start() }
}
var launcher = makeLauncher()
windows.onChange = { launcher.refilter() }
files.onChange = { launcher.refilter() }
windows.refresh()

try? FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
let watcher = FolderWatcher(configDir.resolvingSymlinksInPath()) { applySettings() }

if args.contains("--demo") {
    let screen = NSScreen.main!
    let backdrop = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
    backdrop.level = .floating
    backdrop.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle]
    let g = CAGradientLayer()
    g.colors = [NSColor(hex: 0x1a1b26), NSColor(hex: 0x2a2f4a), NSColor(hex: 0x3b2f55), NSColor(hex: 0x7aa2f7)].map(\.cgColor)
    g.startPoint = CGPoint(x: 0, y: 0)
    g.endPoint = CGPoint(x: 1, y: 1)
    let v = NSView()
    v.wantsLayer = true
    v.layer = g
    backdrop.contentView = v
    backdrop.orderFrontRegardless()
}

// Keep App Nap from parking the idle agent; a napped process answers the hotkey late.
let activity = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep,
                                                     reason: "launcher must respond instantly")

let server = IPC.Server(path: IPC.socketPath) { words in
    switch words[0] {
    case "toggle": launcher.toggle()
    case "show":
        if words.count > 1 {
            menus.load()
            if let m = menus.menus[words[1]] { launcher.show(menuMode(m)) }
            else if let b = builtinMode(words[1]) { launcher.show(b) }
            else { return "error: no menu named \(words[1]) in \(menus.dir.path) (built in: \(builtins.keys.sorted().joined(separator: ", ")))" }
            if words.count > 2 { launcher.setQuery(words.dropFirst(2).joined(separator: " ")) }
        } else { launcher.show() }
    case "hide": launcher.hide()
    case "reload":
        apps.refresh(); applySettings()
        if !problems.isEmpty { return "error: " + problems.joined(separator: "; ") }
    case "ping": break
    case "query":  // prints what the launcher would list: id, title, subtitle (tab-separated)
        let rows = root.search(words.dropFirst().joined(separator: " ")).prefix(20)
        return (["ok"] + rows.map { "\($0.id)\t\($0.title)\t\($0.subtitle)" }).joined(separator: "\n")
    default: return "error: unknown command \(words[0])"
    }
    // Reply once the frame is committed, so the client's timing includes the render.
    launcher.panel.displayIfNeeded()
    CATransaction.flush()
    return "ok"
}
if server == nil { exit(0) }  // lost a start-up race with another instance

DispatchQueue.main.async {
    guard args.contains("--show") || args.contains("--demo") else { return }
    launcher.show()
    if let i = args.firstIndex(of: "--query"), i + 1 < args.count {
        launcher.setQuery(args[i + 1])
    }
    if args.contains("--demo") {
        // Capture rect in top-left global coordinates, for `screencapture -R`.
        let f = launcher.panel.frame, h = NSScreen.screens[0].frame.height
        print("panel \(Int(f.minX)),\(Int(h - f.maxY)),\(Int(f.width)),\(Int(f.height)) window \(launcher.panel.windowNumber)")
    }
}

app.run()
