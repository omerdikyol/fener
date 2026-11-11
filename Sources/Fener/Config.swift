import AppKit

/// ~/.config/fener/config.toml. Every key is optional; unknown keys are reported, not ignored.
///
///     theme = "tokyo-night"          # themes/<name>.toml, or the built-in tokyo-night
///     home = "menu"                  # menu shown while the search is empty; "" = app list
///     shortcut = "cmd+shift+space"   # fener's own show/hide shortcut; "" = none
///     learn_queries = true           # rank rows you picked for the same text first; Recently Used
///     terminal_command = "open -na Ghostty --args --command={} --quit-after-last-window-closed=true"
///                                    # how `terminal = true` menu entries run; {} = the command
///
///     [prefixes]                     # typed first in the search field to pick a source
///     calc = "="
///     files = "/"
///     emoji = ":"
///     clipboard = "*"
///     menus = ">"
///     windows = ";"
///     snippets = "!"
///
///     [aliases]                      # a typed word opens a menu, built-in view or app
///     ws = "workspace"
///     vol = "audio"
///
///     [currency]                     # ECB daily rates, fetched only when a conversion is typed
///     enabled = true
///
///     [clipboard]
///     enabled = true
///     max_items = 200
///     max_item_bytes = 5000000
///     keep_days = 30                 # older items are deleted
///     ignore_apps = ["com.1password.1password"]   # bundle ids or names: never recorded
///
///     [panel]
///     position = "center"            # center | upper | top
///     screen = "mouse"               # mouse | focused (the front window's) | main (with the menu bar)
///     close_on_blur = true           # hide when another window takes focus
///     animation = true
///     animation_ms = 120             # open; closing takes two thirds of it
///
///     [search]                       # what the main search lists besides apps' own prefixes
///     sources = ["apps", "menus", "system", "snippets", "settings", "projects", "generators", "bookmarks", "windows"]
///     web_fallback = true            # the "Search <engine> for …" row at the bottom
///
///     [files]
///     roots = ["~"]                  # where file search and Recent Files look
///     limit = 60
///     recent_days = 14
///     screenshot_thumbnails = 40
///
///     [apps]
///     folders = ["/Applications", "/System/Applications", "~/Applications"]
///     browser = "helium"             # bookmarks: helium | chrome | brave | arc | edge | vivaldi | chromium | none
///     editor = "vscode"              # projects and Edit actions: vscode | cursor | vscodium | windsurf | textedit
///     terminal = "Ghostty"           # "Open in Terminal" actions: an app name
///
///     [learning]
///     usage_half_life_days = 7       # how fast picks stop counting
///     search_half_life_days = 14     # how fast learned searches fade
struct Config: Equatable {
    var theme = "tokyo-night"
    var learnQueries = true   // learn which row is picked for which typed text; Recently Used
    var home = "menu"   // menu listed while the search is empty; "" lists apps instead
    var shortcut = ""   // fener's own show/hide shortcut, e.g. "ctrl+opt+cmd+space"; "" = none
    var terminal = "open -na Ghostty --args --command={} --quit-after-last-window-closed=true"
    var prefixes: [String: String] = ["calc": "=", "files": "/", "emoji": ":", "clipboard": "*", "menus": ">", "windows": ";", "snippets": "!"]
    var clipboardEnabled = true
    var clipboardMaxItems = 200
    var clipboardMaxItemBytes = 5_000_000
    var clipboardKeepDays = 30
    var clipboardIgnoreApps: [String] = []
    var currencyEnabled = true
    var aliases: [String: String] = [:]   // typed word -> menu, built-in view or app name

    // [panel]
    var panelPosition = "center"
    var panelScreen = "mouse"
    var closeOnBlur = true
    var animation = true
    var animationMs = 120
    // [search]
    static let allSources = ["apps", "menus", "system", "snippets", "settings", "projects", "generators", "bookmarks", "windows"]
    var sources = Set(Config.allSources)
    var webFallback = true
    // [files]
    var fileRoots = ["~"]
    var fileLimit = 60
    var recentDays = 14
    var screenshotThumbnails = 40
    // [apps]
    var appFolders = ["/Applications", "/System/Applications", "~/Applications"]
    var browser = "helium"
    var editor = "vscode"
    var terminalApp = "Ghostty"
    // [learning]
    var usageHalfLifeDays = 7.0
    var searchHalfLifeDays = 14.0

    static let choices: [String: [String]] = [
        "panel.position": ["center", "upper", "top"],
        "panel.screen": ["mouse", "focused", "main"],
        "apps.browser": ["helium", "chrome", "brave", "arc", "edge", "vivaldi", "chromium", "none"],
        "apps.editor": ["vscode", "cursor", "vscodium", "windsurf", "textedit"],
    ]

    /// Parses config text; `problems` collects errors and warnings worth showing to the user.
    static func parse(_ text: String, problems: inout [String]) -> Config {
        var c = Config()
        let t: [String: Any]
        do { t = try Toml.parse(text) } catch { problems.append("config.toml: \(error)"); return c }
        func warn(_ m: String) { problems.append("config.toml: \(m)") }

        for (k, v) in t {
            switch k {
            case "theme":
                if let s = v as? String { c.theme = s } else { warn("theme must be a string") }
            case "learn_queries":
                if let b = v as? Bool { c.learnQueries = b } else { warn("learn_queries must be true or false") }
            case "home":
                if let s = v as? String { c.home = s } else { warn("home must be a string") }
            case "shortcut":   // checked and reported when it is registered (Hotkey.set)
                if let s = v as? String { c.shortcut = s } else { warn("shortcut must be a string like \"cmd+shift+space\"") }
            case "terminal_command", "terminal":   // "terminal" is the old name, still accepted
                if let s = v as? String, s.contains("{}") { c.terminal = s } else { warn("\(k) must be a string containing {}") }
            case "prefixes":
                guard let p = v as? [String: Any] else { warn("[prefixes] must be a table"); continue }
                for (name, value) in p {
                    guard c.prefixes[name] != nil else { warn("unknown prefix \(name) (known: \(c.prefixes.keys.sorted().joined(separator: ", ")))"); continue }
                    guard let s = value as? String else { warn("prefixes.\(name) must be a string"); continue }
                    c.prefixes[name] = s  // an empty string turns that prefix off
                }
            case "clipboard":
                guard let p = v as? [String: Any] else { warn("[clipboard] must be a table"); continue }
                for (name, value) in p {
                    switch (name, value) {
                    case ("enabled", let b as Bool): c.clipboardEnabled = b
                    case ("max_items", let i as Int) where i > 0: c.clipboardMaxItems = i
                    case ("max_item_bytes", let i as Int) where i > 0: c.clipboardMaxItemBytes = i
                    case ("keep_days", let i as Int) where i > 0: c.clipboardKeepDays = i
                    case ("ignore_apps", let a as [Any]) where a.allSatisfy({ $0 is String }): c.clipboardIgnoreApps = a as! [String]
                    case ("enabled", _), ("max_items", _), ("max_item_bytes", _), ("keep_days", _), ("ignore_apps", _):
                        warn("clipboard.\(name) has a wrong type or value")
                    default: warn("unknown key clipboard.\(name)")
                    }
                }
            case "aliases":
                guard let p = v as? [String: Any] else { warn("[aliases] must be a table"); continue }
                for (name, value) in p {
                    if let s = value as? String, !s.isEmpty { c.aliases[name.lowercased()] = s }
                    else { warn("aliases.\(name) must be a menu, view or app name") }
                }
            case "panel", "search", "files", "apps", "learning":
                guard let p = v as? [String: Any] else { warn("[\(k)] must be a table"); continue }
                for (name, value) in p { c.set(section: k, name, value, warn) }
            case "currency":
                guard let p = v as? [String: Any] else { warn("[currency] must be a table"); continue }
                for (name, value) in p {
                    if name == "enabled", let b = value as? Bool { c.currencyEnabled = b }
                    else { warn(name == "enabled" ? "currency.enabled must be true or false" : "unknown key currency.\(name)") }
                }
            default: warn("unknown key \(k)")
            }
        }
        let used = c.prefixes.values.filter { !$0.isEmpty }
        if Set(used).count != used.count { warn("two prefixes are the same") }
        return c
    }
}

extension Config {
    /// One key of the [panel], [search], [files], [apps] or [learning] sections.
    mutating func set(section: String, _ name: String, _ value: Any, _ warn: (String) -> Void) {
        let key = "\(section).\(name)"
        func choice() -> String? {
            guard let s = value as? String, Config.choices[key]?.contains(s) ?? false else {
                warn("\(key) must be one of: \(Config.choices[key]?.joined(separator: ", ") ?? "")"); return nil
            }
            return s
        }
        func int(_ range: ClosedRange<Int>) -> Int? {
            guard let i = value as? Int, range.contains(i) else { warn("\(key) must be a whole number \(range.lowerBound)…\(range.upperBound)"); return nil }
            return i
        }
        func number(_ range: ClosedRange<Double>) -> Double? {
            guard let d = (value as? Int).map(Double.init) ?? value as? Double, range.contains(d) else {
                warn("\(key) must be a number \(range.lowerBound)…\(range.upperBound)"); return nil
            }
            return d
        }
        func bool() -> Bool? {
            guard let b = value as? Bool else { warn("\(key) must be true or false"); return nil }
            return b
        }
        func strings() -> [String]? {
            guard let a = value as? [Any], a.allSatisfy({ $0 is String }) else { warn("\(key) must be a list of strings"); return nil }
            return a as? [String]
        }
        switch key {
        case "panel.position": if let v = choice() { panelPosition = v }
        case "panel.screen": if let v = choice() { panelScreen = v }
        case "panel.close_on_blur": if let v = bool() { closeOnBlur = v }
        case "panel.animation": if let v = bool() { animation = v }
        case "panel.animation_ms": if let v = int(0...1000) { animationMs = v }
        case "search.sources":
            guard let v = strings() else { return }
            let unknown = v.filter { !Config.allSources.contains($0) }
            if !unknown.isEmpty { warn("search.sources: unknown \(unknown.joined(separator: ", ")) (known: \(Config.allSources.joined(separator: ", ")))") }
            sources = Set(v.filter { Config.allSources.contains($0) })
        case "search.web_fallback": if let v = bool() { webFallback = v }
        case "files.roots": if let v = strings(), !v.isEmpty { fileRoots = v }
        case "files.limit": if let v = int(10...500) { fileLimit = v }
        case "files.recent_days": if let v = int(1...365) { recentDays = v }
        case "files.screenshot_thumbnails": if let v = int(0...200) { screenshotThumbnails = v }
        case "apps.folders": if let v = strings(), !v.isEmpty { appFolders = v }
        case "apps.browser": if let v = choice() { browser = v }
        case "apps.editor": if let v = choice() { editor = v }
        case "apps.terminal":
            if let s = value as? String, !s.isEmpty { terminalApp = s } else { warn("\(key) must be an app name") }
        case "learning.usage_half_life_days": if let v = number(0.5...365) { usageHalfLifeDays = v }
        case "learning.search_half_life_days": if let v = number(0.5...365) { searchHalfLifeDays = v }
        default: warn("unknown key \(key)")
        }
    }

    /// "~/x" -> absolute path.
    static func expand(_ path: String) -> String { (path as NSString).expandingTildeInPath }
}

extension Theme {
    /// Parses a theme file on top of `base`; every key is optional.
    ///
    ///     [colors]                     # "#rrggbb" or "#rrggbbaa"
    ///     background = "#1a1b26"
    ///     background_opacity = 0.95
    ///     border = "#c0caf5"
    ///     text = "#c0caf5"
    ///     muted = "#565f89"
    ///     accent = "#7aa2f7"
    ///     selection = "#24283b"
    ///     [font]
    ///     family = "JetBrainsMono Nerd Font"
    ///     size = 15
    ///     [layout]
    ///     width = 480
    ///     padding = 18
    ///     border_width = 2
    ///     corner_radius = 0
    ///     selection_radius = 4
    ///     row_height = 40
    ///     icon_size = 20
    ///     visible_rows = 9
    static func parse(_ text: String, name: String, base: Theme = Theme(), problems: inout [String]) -> Theme {
        var th = base
        let file = "themes/\(name).toml"
        let t: [String: Any]
        do { t = try Toml.parse(text) } catch { problems.append("\(file): \(error)"); return base }
        func warn(_ m: String) { problems.append("\(file): \(m)") }
        func number(_ v: Any) -> CGFloat? { (v as? Int).map { CGFloat($0) } ?? (v as? Double).map { CGFloat($0) } }

        for (section, body) in t {
            guard let b = body as? [String: Any] else { warn("unknown key \(section)"); continue }
            for (k, v) in b {
                switch (section, k) {
                case ("colors", "background_opacity"):
                    if let n = number(v), (0...1).contains(n) { th.backgroundOpacity = n } else { warn("background_opacity must be 0…1") }
                case ("colors", _):
                    guard let s = v as? String, let c = NSColor(hexString: s) else { warn("colors.\(k) must be \"#rrggbb\""); continue }
                    switch k {
                    case "background": th.background = c
                    case "border": th.border = c
                    case "text": th.text = c
                    case "muted": th.muted = c
                    case "accent": th.accent = c
                    case "selection": th.selection = c
                    default: warn("unknown color \(k)")
                    }
                case ("font", "family"):
                    if let s = v as? String { th.fontFamily = s } else { warn("font.family must be a string") }
                case ("font", "size"):
                    if let n = number(v), n >= 8, n <= 40 { th.fontSize = n } else { warn("font.size must be 8…40") }
                case ("layout", _):
                    guard let n = number(v), n >= 0 else { warn("layout.\(k) must be a number ≥ 0"); continue }
                    switch k {
                    case "width": th.width = max(240, n)
                    case "padding": th.padding = n
                    case "border_width": th.borderWidth = n
                    case "corner_radius": th.cornerRadius = n
                    case "selection_radius": th.selectionRadius = n
                    case "row_height": th.rowHeight = max(20, n)
                    case "icon_size": th.iconSize = max(8, n)
                    case "visible_rows": th.visibleRows = max(1, Int(n))
                    default: warn("unknown key layout.\(k)")
                    }
                default: warn("unknown key \(section).\(k)")
                }
            }
        }
        if NSFontManager.shared.font(withFamily: th.fontFamily, traits: [], weight: 5, size: 12) == nil {
            warn("font \"\(th.fontFamily)\" is not installed; using the system monospaced font")
        }
        return th
    }
}

extension NSColor {
    convenience init?(hexString s: String) {
        var h = s.trimmingCharacters(in: .whitespaces)
        guard h.hasPrefix("#") else { return nil }
        h.removeFirst()
        guard h.count == 6 || h.count == 8, let v = UInt64(h, radix: 16) else { return nil }
        let rgb = h.count == 8 ? v >> 8 : v, a = h.count == 8 ? CGFloat(v & 0xff) / 255 : 1
        self.init(srgbRed: CGFloat((rgb >> 16) & 0xff) / 255, green: CGFloat((rgb >> 8) & 0xff) / 255,
                  blue: CGFloat(rgb & 0xff) / 255, alpha: a)
    }
}

/// Watches a folder tree with FSEvents and calls back on the main queue, coalesced.
final class FolderWatcher {
    private var stream: FSEventStreamRef?
    private let callback: () -> Void

    init(_ url: URL, callback: @escaping () -> Void) {
        self.callback = callback
        var ctx = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                       retain: nil, release: nil, copyDescription: nil)
        let cb: FSEventStreamCallback = { _, info, _, _, _, _ in
            Unmanaged<FolderWatcher>.fromOpaque(info!).takeUnretainedValue().callback()
        }
        // 0.15 s latency coalesces an editor's write-rename-chmod burst into one reload.
        stream = FSEventStreamCreate(nil, cb, &ctx, [url.path] as CFArray,
                                     FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.15,
                                     FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents))
        if let stream {
            FSEventStreamSetDispatchQueue(stream, .main)
            FSEventStreamStart(stream)
        }
    }

    deinit {
        if let stream { FSEventStreamStop(stream); FSEventStreamInvalidate(stream); FSEventStreamRelease(stream) }
    }
}
