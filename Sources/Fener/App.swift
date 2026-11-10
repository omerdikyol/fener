import AppKit

// Shared state, settings and the panel. Globals outside main.swift are initialized lazily
// on first use, so nothing here depends on file order; main.swift sets things up in order.

var theme = Theme()
let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("fener")
let apps = AppProvider(frecency: Frecency(url: cacheDir.appendingPathComponent("frecency.json")))
let configDir = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".config/fener")
let menus = MenuStore(dir: configDir.appendingPathComponent("menus"))
let windows = WindowProvider()

final class Box<T> { var value: T; init(_ v: T) { value = v } }

let supportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("fener")
let clipboard = Clipboard(dir: supportDir.appendingPathComponent("clipboard"), legacy: cacheDir.appendingPathComponent("clipboard"))

/// Clipboard limits and filters from config.toml; recording starts or stops with `enabled`.
func configureClipboard(_ c: Config) {
    clipboard.maxItems = c.clipboardMaxItems
    clipboard.maxItemBytes = c.clipboardMaxItemBytes
    clipboard.keepDays = c.clipboardKeepDays
    clipboard.ignoreApps = Set(c.clipboardIgnoreApps.map { $0.lowercased() })
    if c.clipboardEnabled { clipboard.start() } else { clipboard.stop() }
}
let files = FileSearch()

func sf(_ name: String) -> NSImage? { Icons.named(name, theme: theme) }

let ago = { () -> RelativeDateTimeFormatter in let f = RelativeDateTimeFormatter(); f.unitsStyle = .abbreviated; return f }()

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
    let newProblems = p + menus.errors
    if newProblems != problems { newProblems.forEach { Log.error($0) } }
    problems = newProblems
    configureClipboard(c)
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

func makeLauncher() -> Launcher {
    let l = Launcher(theme: theme, root: root)
    l.onShow = { apps.refresh(); windows.refresh(); menus.load(); snippets.load(); refreshBrowserAndProjects() }
    l.onPick = { if tracked($0.id) { apps.frecency.bump($0.id) } }
    l.prewarm()
    return l
}

var launcher = makeLauncher()

/// Commands from the `fener` CLI (see IPC.swift); returns the reply line.
func handleCommand(_ words: [String]) -> String {
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
    default:
        Log.error("unknown command \(words[0])")
        return "error: unknown command \(words[0])"
    }
    // Reply once the frame is committed, so the client's timing includes the render.
    launcher.panel.displayIfNeeded()
    CATransaction.flush()
    return "ok"
}
