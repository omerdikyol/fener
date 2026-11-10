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

func calcItem(_ a: Calc.Answer, icon: String = "nf-md-calculator") -> Item {
    Item(id: "calc", title: a.value, subtitle: a.detail + "  ·  ⏎ copies", icon: sf(icon),
         run: { Clipboard.copyText(a.value) }, score: 10_000)
}

let rates = Currency(cacheDir: cacheDir)

/// "100 usd to try" with ECB rates; fetches them (at most daily) only when asked.
func currencyItem(_ s: String) -> Item? {
    guard config.currencyEnabled, let q = Currency.query(s.lowercased()), let amount = Calc.evaluate(q.amount) else { return nil }
    rates.refreshIfStale()
    guard let v = rates.convert(amount, from: q.from, to: q.to) else {
        return Item(id: "calc", title: rates.rates.isEmpty ? "Fetching exchange rates…" : "No rate for \(q.from) or \(q.to)",
                    subtitle: "ECB reference rates", icon: sf("nf-md-cash_multiple"), score: 10_000)
    }
    let value = abs(v) >= 1 ? String(format: "%.2f", v) : String(format: "%.4g", v)
    return calcItem(Calc.Answer(value: value, detail: "\(Calc.format(amount)) \(q.from) → \(q.to) · ECB \(rates.date)"),
                    icon: "nf-md-cash_multiple")
}

/// Calculator, currency, then time and dates: the first that understands the input.
func answerItem(_ s: String, forced: Bool) -> Item? {
    if let a = Calc.answer(s, forced: forced) { return calcItem(a) }
    if let c = currencyItem(s) { return c }
    if let a = TimeCalc.answer(s) { return calcItem(a, icon: "nf-md-calendar_clock") }
    return nil
}

var quicklinks = Quicklinks()

func linkItem(_ link: Quicklink, _ q: String, score: Int) -> Item {
    Item(id: "link:" + link.keyword, title: q.isEmpty ? link.name : "Search \(link.name) for “\(q)”",
         subtitle: q.isEmpty ? "\(link.keyword) <query>" : link.keyword, icon: sf(link.icon),
         run: { if let u = link.url(for: q) { NSWorkspace.shared.open(u) } }, score: score)
}

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

// MARK: running apps and colors

func quitItems(_ q: String) -> [Item] {
    NSWorkspace.shared.runningApplications.compactMap { app in
        guard app.activationPolicy == .regular, app != NSRunningApplication.current, let name = app.localizedName,
              let s = q.isEmpty ? 0 : Fuzzy.score(q, name) else { return nil }
        return Item(id: "quit:\(app.processIdentifier)", title: name, accessory: "›", icon: app.icon, score: s, submenu: {
            Mode(prompt: "Quit \(name)?") { _ in [
                Item(id: "quit:yes", title: "Quit", icon: sf("nf-md-close_circle"), run: { app.terminate() }),
                Item(id: "quit:force", title: "Force Quit", subtitle: "unsaved changes are lost", icon: sf("nf-md-alert"),
                     run: { app.forceTerminate() }),
                Item(id: "quit:no", title: "Cancel", icon: sf("nf-md-close")),
            ] }
        })
    }.sorted { $0.score != $1.score ? $0.score > $1.score : $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
}

/// Opens the system color sampler; the picked color's hex is copied, and the panel lists
/// it as HEX, RGB and HSL to copy another format.
func pickColor() {
    launcher.hide()
    NSColorSampler().show { picked in
        guard let c = picked?.usingColorSpace(.sRGB) else { return }
        let r = Int((c.redComponent * 255).rounded()), g = Int((c.greenComponent * 255).rounded()), b = Int((c.blueComponent * 255).rounded())
        let hex = String(format: "#%02x%02x%02x", r, g, b)
        Clipboard.copyText(hex)
        var h: CGFloat = 0, s: CGFloat = 0, br: CGFloat = 0, a: CGFloat = 0
        c.getHue(&h, saturation: &s, brightness: &br, alpha: &a)
        let l = (2 - s) * br / 2, sl = l > 0 && l < 1 ? s * br / (1 - abs(2 * l - 1)) : 0
        let swatch = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            c.setFill(); NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4).fill(); return true
        }
        let formats = [hex, "rgb(\(r), \(g), \(b))",
                       String(format: "hsl(%.0f, %.0f%%, %.0f%%)", h * 360, sl * 100, l * 100)]
        launcher.show(Mode(prompt: "Color…") { _ in
            formats.enumerated().map { i, f in
                Item(id: "color:\(i)", title: f, subtitle: i == 0 ? "copied" : "", icon: swatch, run: { Clipboard.copyText(f) })
            }
        })
    }
}

func confirm(_ a: SystemAction) -> Mode {
    Mode(prompt: "\(a.name)?") { _ in [
        Item(id: "confirm:yes", title: "Yes, \(a.name.lowercased())", icon: sf(a.icon), run: a.run),
        Item(id: "confirm:no", title: "Cancel", icon: sf("nf-md-close")),
    ] }
}

func systemItems(_ q: String) -> [Item] {
    let actions: [Item] = SystemAction.all.compactMap { a in
        guard let s = q.isEmpty ? 0 : Fuzzy.score(q, a.name) else { return nil }
        var item = Item(id: "system:" + a.name, title: a.name, subtitle: a.subtitle, icon: sf(a.icon), score: s)
        if a.confirm { item.submenu = { confirm(a) }; item.accessory = "›" } else { item.run = a.run }
        return item
    }
    func view(_ title: String, _ icon: String, _ name: String) -> Item {
        Item(id: "system:" + name, title: title, subtitle: "", accessory: "›", icon: sf(icon), submenu: { builtins[name]! })
    }
    // The System view (empty query) lists actions and the two process views; the other
    // views live in the Find and Trigger menus and are reached here only by typing.
    let inSystemView: Set = ["system:quit", "system:processes"]
    let extra = [
        view("Quit Apps", "nf-md-application_cog", "quit"),
        Item(id: "system:color", title: "Pick Color", subtitle: "system", icon: sf("nf-md-eyedropper"), run: pickColor),
        view("Audio Devices", "nf-md-volume_high", "audio"),
        view("Kill Process", "nf-md-chip", "processes"),
        view("Recent Files", "nf-md-file_clock", "recent"),
        view("Screenshots", "nf-md-image_search", "screenshots"),
        view("System Settings", "nf-fa-cog", "settings"),
        view("Generate (UUID, password, lorem)", "nf-md-dice_multiple", "generate"),
        view("Bookmarks", "nf-md-bookmark", "bookmarks"),
        view("VS Code Projects", "nf-md-microsoft_visual_studio_code", "projects"),
    ].compactMap { i -> Item? in
        if q.isEmpty, !inSystemView.contains(i.id) { return nil }
        guard let s = q.isEmpty ? 0 : Fuzzy.score(q, i.title) else { return nil }
        var i = i; i.score = s; return i
    }
    return actions + extra
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

// MARK: settings panes, audio, bookmarks, projects, recents, generators, processes

func settingsItems(_ q: String) -> [Item] {
    SettingsPanes.all.compactMap { p in
        guard let s = q.isEmpty ? 0 : Fuzzy.score(q, p.name) else { return nil }
        return Item(id: "pane:" + p.id, title: p.name, subtitle: "System Settings", icon: sf(p.icon),
                    run: { SettingsPanes.open(p.id) }, score: s)
    }.sorted { $0.score > $1.score }
}

func audioItems(_ q: String) -> [Item] {
    let devices = Audio.devices()
    var out: [Item] = []
    for input in [false, true] {
        let current = Audio.defaultDevice(input: input)
        for d in devices where input ? d.input : d.output {
            let label = (input ? "Input: " : "Output: ") + d.name
            guard let s = q.isEmpty ? 0 : Fuzzy.score(q, label) else { continue }
            out.append(Item(id: "audio:\(input):\(d.id)", title: label, subtitle: d.id == current ? "current" : "",
                            icon: sf(Audio.icon(d, input: input)), run: { Audio.setDefault(d.id, input: input) }, score: s))
        }
    }
    return q.isEmpty ? out : out.sorted { $0.score > $1.score }
}

let bookmarks = Box<[Bookmarks.Bookmark]>([])
let projects = Box<[URL]>([])
/// Re-reads Helium bookmarks and VS Code recents off the main thread (both small files).
func refreshBrowserAndProjects() {
    DispatchQueue.global(qos: .utility).async {
        let b = Bookmarks.helium(), p = VSCodeRecents.load()
        DispatchQueue.main.async { bookmarks.value = b; projects.value = p }
    }
}

func bookmarkItems(_ q: String) -> [Item] {
    bookmarks.value.compactMap { b in
        let host = URL(string: b.url)?.host ?? b.url
        guard let s = q.isEmpty ? 0 : [Fuzzy.score(q, b.name), Fuzzy.score(q, host)].compactMap({ $0 }).max() else { return nil }
        return Item(id: "bookmark:" + b.url, title: b.name, subtitle: b.folder.isEmpty ? host : "\(b.folder) · \(host)",
                    icon: sf("nf-md-bookmark"), run: { if let u = URL(string: b.url) { NSWorkspace.shared.open(u) } }, score: s)
    }.sorted { $0.score > $1.score }
}

let vscode = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.microsoft.VSCode")
func projectItems(_ q: String) -> [Item] {
    let home = NSHomeDirectory()
    return projects.value.enumerated().compactMap { i, u in
        let name = u.deletingPathExtension().lastPathComponent
        guard let s = q.isEmpty ? -i : Fuzzy.score(q, name) else { return nil }
        let dir = u.deletingLastPathComponent().path
        let remote = u.isFileURL ? nil : (u.host ?? "remote").replacingOccurrences(of: "ssh-remote+", with: "ssh ")
        let place = remote.map { "\($0) · \(dir)" } ?? (dir.hasPrefix(home) ? "~" + dir.dropFirst(home.count) : dir)
        return Item(id: "project:" + u.absoluteString, title: name, subtitle: place,
                    icon: sf("nf-md-microsoft_visual_studio_code"), run: {
                        if let vscode, !u.isFileURL {  // remote folders open through VS Code's own CLI
                            let cli = vscode.appendingPathComponent("Contents/Resources/app/bin/code").path
                            Shell.run(cli, [u.hasDirectoryPath || u.pathExtension.isEmpty ? "--folder-uri" : "--file-uri", u.absoluteString])
                        } else if let vscode { NSWorkspace.shared.open([u], withApplicationAt: vscode, configuration: NSWorkspace.OpenConfiguration()) }
                        else { NSWorkspace.shared.open(u) }
                    }, score: s)
    }.sorted { $0.score > $1.score }
}

let recentFiles = SpotlightList(query: "kMDItemLastUsedDate >= $time.today(-14)", dateAttribute: kMDItemLastUsedDate)
let screenshots = SpotlightList(query: "kMDItemIsScreenCapture == 1", dateAttribute: kMDItemContentCreationDate, thumbnails: 40)

func spotlightItems(_ list: SpotlightList, _ q: String, glyph: String) -> [Item] {
    list.refresh(iconSide: theme.iconSize)
    let home = NSHomeDirectory()
    return list.entries.compactMap { e in
        let name = (e.path as NSString).lastPathComponent
        guard let s = q.isEmpty ? 0 : Fuzzy.score(q, name) else { return nil }
        let dir = (e.path as NSString).deletingLastPathComponent
        let when = ago.localizedString(for: e.date, relativeTo: Date())
        return Item(id: "spot:" + e.path, title: name,
                    subtitle: "\(when) · " + (dir.hasPrefix(home) ? "~" + dir.dropFirst(home.count) : dir),
                    icon: list.thumbs[e.path] ?? (list.thumbnails > 0 ? sf(glyph) : NSWorkspace.shared.icon(forFile: e.path)),
                    run: { NSWorkspace.shared.open(URL(fileURLWithPath: e.path)) }, score: s)
    }.sorted { q.isEmpty ? false : $0.score > $1.score }
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

let procCache = Box<(Date, [Processes.Proc])>((.distantPast, []))
/// Name search, or ":3000" for whatever listens on that TCP port.
func processItems(_ q: String) -> [Item] {
    if Date().timeIntervalSince(procCache.value.0) > 2 { procCache.value = (Date(), Processes.list()) }
    let port = q.hasPrefix(":") ? Int(q.dropFirst()) : nil
    let pids = port.map(Processes.listening(port:))
    return procCache.value.1.compactMap { p in
        if let pids { guard pids.contains(p.pid) else { return nil } }
        guard p.pid != getpid(), let s = (q.isEmpty || pids != nil) ? 0 : Fuzzy.score(q, p.name) else { return nil }
        return Item(id: "proc:\(p.pid)", title: p.name, subtitle: String(format: "pid %d · %.1f%% CPU · %d MB", p.pid, p.cpu, p.memMB),
                    accessory: "›", icon: sf("nf-md-chip"), score: s, submenu: {
            Mode(prompt: "Stop \(p.name)?") { _ in [
                Item(id: "proc:term", title: "Quit (SIGTERM)", icon: sf("nf-md-close_circle"), run: { kill(p.pid, SIGTERM) }),
                Item(id: "proc:kill", title: "Kill (SIGKILL)", subtitle: "unsaved work is lost", icon: sf("nf-md-skull"),
                     run: { kill(p.pid, SIGKILL) }),
                Item(id: "proc:no", title: "Cancel", icon: sf("nf-md-close")),
            ] }
        })
    }.sorted { $0.score > $1.score }
}

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
    let qlURL = configDir.appendingPathComponent("quicklinks.toml")
    quicklinks = (try? String(contentsOf: qlURL, encoding: .utf8)).map { Quicklinks.parse($0, problems: &p) } ?? Quicklinks()
    if !Icons.fontHasNerdGlyphs(th) {
        p.append("themes/\(c.theme).toml: font \"\(th.fontFamily)\" has no Nerd Font glyphs; menu icons show as dots")
    }
    return (c, th, p)
}

func applySettings() {
    let (c, th, p) = loadSettings()
    menus.load()
    snippets.load()
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

func makeLauncher() -> Launcher {
    let l = Launcher(theme: theme, root: root)
    l.onShow = { apps.refresh(); windows.refresh(); menus.load(); snippets.load(); refreshBrowserAndProjects() }
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
rates.onChange = { launcher.refilter() }
recentFiles.onChange = { launcher.refilter() }
screenshots.onChange = { launcher.refilter() }
refreshBrowserAndProjects()
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
    case "pick-color": pickColor()
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
