import AppKit

// `fener` runs the resident agent app; `fener toggle|show|hide|reload|ping` talks to it
// over a Unix socket. App flags: `--show` opens the panel at launch, `--demo` adds a plain
// gradient backdrop for screenshots, `--query <text>` prefills the search, `--bench`
// prints scan and search timings and exits.

let args = CommandLine.arguments
if args.count > 1, IPC.commands.contains(args[1]) {
    exit(IPC.send(Array(args.dropFirst())))  // client: never touches NSApplication
}

if IPC.isRunning() {
    print("fener is already running")
    exit(0)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)  // same effect as LSUIElement: no Dock icon, no menu bar
setvbuf(stdout, nil, _IOLBF, 0)

let theme = Theme.tokyoNight
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
    let box = Box(m.entries)
    if m.executable != nil {
        menus.list(m) { box.value = $0; launcher.refilter() }
    }
    return Mode(prompt: m.prompt) { q in rank(box.value, q).map { entryItem($0.0, of: m, score: $0.1) } }
}

func entryItem(_ e: MenuEntry, of m: Menu, score: Int) -> Item {
    var item = Item(id: "menu:\(m.name):\(e.name)", title: e.name, subtitle: e.subtitle,
                    accessory: e.menu.isEmpty ? "" : "›", icon: Icons.named(e.icon, theme: theme), score: score)
    let choice = e.value.isEmpty ? e.name : e.value
    let env = ["FENER_MENU": m.name, "FENER_CHOICE": choice]
    if !e.menu.isEmpty {
        item.submenu = { menus.menus[e.menu].map(menuMode) ?? message("No menu named \(e.menu)") }
    } else if !e.command.isEmpty {
        item.run = { Shell.sh(e.command, extraEnv: env) }
    } else if let exe = m.executable {
        item.run = { Shell.run(exe.path, [choice], extraEnv: env) }  // dmenu style: chosen entry comes back as $1
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
                            icon: Icons.named(m.icon.isEmpty ? "list.bullet" : m.icon, theme: theme),
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

// ponytail: prefixes are fixed here; stage 6 reads them from config.toml.
let root = Mode(prompt: "Apps…") { raw in
    if raw.hasPrefix(">") { return searchMenus(String(raw.dropFirst()).trimmingCharacters(in: .whitespaces), entries: true) }
    if raw.hasPrefix(";") { return windows.search(String(raw.dropFirst()).trimmingCharacters(in: .whitespaces), all: true) }
    if raw.isEmpty { return apps.search("") }
    // Windows rank a bit below apps and menus: long titles match short queries by accident.
    return merge(apps.search(raw), searchMenus(raw, entries: true),
                 windows.search(raw, all: false).map { var i = $0; i.score -= 10; return i })
}

let launcher = Launcher(theme: theme, root: root)
launcher.onShow = { apps.refresh(); windows.refresh(); menus.load() }
windows.onChange = { launcher.refilter() }
windows.refresh()
launcher.prewarm()

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
            guard let m = menus.menus[words[1]] else { return "error: no menu named \(words[1]) in \(menus.dir.path)" }
            launcher.show(menuMode(m))
        } else { launcher.show() }
    case "hide": launcher.hide()
    case "reload":
        apps.refresh(); menus.load()
        if !menus.errors.isEmpty { return "error: " + menus.errors.joined(separator: "; ") }
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
