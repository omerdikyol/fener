import AppKit

/// ~/.config/fener/config.toml. Every key is optional; unknown keys are reported, not ignored.
///
///     theme = "tokyo-night"          # themes/<name>.toml, or the built-in tokyo-night
///     terminal = "open -na Ghostty --args --command={} --quit-after-last-window-closed=true"
///                                    # how `terminal = true` menu entries run; {} = the command
///
///     [prefixes]                     # typed first in the search field to pick a source
///     calc = "="
///     files = "/"
///     emoji = ":"
///     clipboard = "*"
///     menus = ">"
///     windows = ";"
///
///     [clipboard]
///     enabled = true
///     max_items = 200
///     max_item_bytes = 5000000
struct Config {
    var theme = "tokyo-night"
    var terminal = "open -na Ghostty --args --command={} --quit-after-last-window-closed=true"
    var prefixes: [String: String] = ["calc": "=", "files": "/", "emoji": ":", "clipboard": "*", "menus": ">", "windows": ";"]
    var clipboardEnabled = true
    var clipboardMaxItems = 200
    var clipboardMaxItemBytes = 5_000_000

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
            case "terminal":
                if let s = v as? String, s.contains("{}") { c.terminal = s } else { warn("terminal must be a string containing {}") }
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
                    case ("enabled", _), ("max_items", _), ("max_item_bytes", _): warn("clipboard.\(name) has a wrong type or value")
                    default: warn("unknown key clipboard.\(name)")
                    }
                }
            default: warn("unknown key \(k)")
            }
        }
        let used = c.prefixes.values.filter { !$0.isEmpty }
        if Set(used).count != used.count { warn("two prefixes are the same") }
        return c
    }
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
