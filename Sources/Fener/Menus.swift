import AppKit

/// One row of a custom menu.
struct MenuEntry: Equatable {
    var name: String
    var subtitle = ""
    var icon = ""
    var command = ""      // run with /bin/sh -c
    var menu = ""         // open this menu instead (a submenu)
    var value = ""        // executable menus: what is handed back (defaults to name)
    var terminal = false  // run the command in a terminal window (config: terminal)
    var confirm = false   // ask "Yes / Cancel" first
}

/// A menu from ~/.config/fener/menus: `<name>.toml` with static entries, or an executable
/// `<name>[.ext]` that prints entries and is run again with the chosen one.
struct Menu {
    var name: String
    var prompt: String
    var icon = ""
    var entries: [MenuEntry]      // static entries (TOML menus)
    var executable: URL?          // dmenu-style menus
    var width: CGFloat? = nil     // panel width while this menu is open

    /// Parses a TOML menu:
    ///     prompt = "Themes…"          # optional
    ///     icon = "paintpalette"       # optional, shown where the menu itself is listed
    ///     width = 320                 # optional panel width for this menu
    ///     [[entry]]
    ///     name = "Tokyo Night"
    ///     subtitle = "dark"          # optional
    ///     icon = "paintpalette"      # optional: SF Symbol, nerd-font glyph, app/image path
    ///     command = "theme tokyo"    # or: menu = "other-menu" (a menu file or a built-in:
    ///                                #     apps, clipboard, emoji, files, system, windows, calc,
    ///                                #     quit, snippets, dictionary)
    ///     terminal = true            # optional: run the command in a terminal window
    ///     confirm = true             # optional: ask before running
    static func parse(name: String, toml: String) throws -> Menu {
        let t = try Toml.parse(toml)
        let rows = t["entry"] as? [[String: Any]] ?? []
        var entries: [MenuEntry] = []
        for (i, r) in rows.enumerated() {
            func str(_ k: String) throws -> String {
                guard let v = r[k] else { return "" }
                guard let s = v as? String else { throw Toml.ParseError(line: 0, message: "entry \(i + 1): \(k) must be a string") }
                return s
            }
            func bool(_ k: String) throws -> Bool {
                guard let v = r[k] else { return false }
                guard let b = v as? Bool else { throw Toml.ParseError(line: 0, message: "entry \(i + 1): \(k) must be true or false") }
                return b
            }
            let e = MenuEntry(name: try str("name"), subtitle: try str("subtitle"), icon: try str("icon"),
                              command: try str("command"), menu: try str("menu"),
                              terminal: try bool("terminal"), confirm: try bool("confirm"))
            if e.name.isEmpty { throw Toml.ParseError(line: 0, message: "entry \(i + 1) has no name") }
            if e.command.isEmpty == e.menu.isEmpty {
                throw Toml.ParseError(line: 0, message: "entry \(i + 1) (\(e.name)) needs exactly one of command or menu")
            }
            entries.append(e)
        }
        var width: CGFloat? = nil
        if let w = t["width"] {
            guard let n = (w as? Int).map({ CGFloat($0) }) ?? (w as? Double).map({ CGFloat($0) }), n >= 200 else {
                throw Toml.ParseError(line: 0, message: "width must be a number ≥ 200")
            }
            width = n
        }
        return Menu(name: name, prompt: t["prompt"] as? String ?? defaultPrompt(name), icon: t["icon"] as? String ?? "",
                    entries: entries, width: width)
    }

    static func defaultPrompt(_ name: String) -> String { title(name) + "…" }
    static func title(_ name: String) -> String { name.prefix(1).uppercased() + name.dropFirst() }

    /// Parses an executable menu's output: a JSON array of objects, or one entry per line,
    /// each line either plain text (the name) or a JSON object
    /// {"name": …, "subtitle": …, "icon": …, "value": …, "command": …, "menu": …}.
    /// An executable menu that prints a line {"refresh": seconds} is run again after that
    /// many seconds for as long as it stays open (for live values). At least 0.5 s.
    static func refreshInterval(_ out: String) -> Double? {
        for line in out.split(separator: "\n") where line.contains("\"refresh\"") {
            if let o = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
               let r = (o["refresh"] as? NSNumber)?.doubleValue, r > 0 { return max(0.5, r) }
        }
        return nil
    }

    static func parseOutput(_ out: String) -> [MenuEntry] {
        func entry(_ o: [String: Any]) -> MenuEntry? {
            guard let name = o["name"] as? String, !name.isEmpty else { return nil }
            func s(_ k: String) -> String { o[k] as? String ?? "" }
            return MenuEntry(name: name, subtitle: s("subtitle"), icon: s("icon"), command: s("command"),
                             menu: s("menu"), value: s("value"),
                             terminal: o["terminal"] as? Bool ?? false, confirm: o["confirm"] as? Bool ?? false)
        }
        let trimmed = out.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("["), let a = try? JSONSerialization.jsonObject(with: Data(trimmed.utf8)) as? [[String: Any]] {
            return a.compactMap(entry)
        }
        return trimmed.split(separator: "\n").compactMap { line in
            let l = line.trimmingCharacters(in: .whitespaces)
            if l.isEmpty { return nil }
            if l.hasPrefix("{"), let o = try? JSONSerialization.jsonObject(with: Data(l.utf8)) as? [String: Any] {
                return entry(o)
            }
            return MenuEntry(name: l)
        }
    }
}

final class MenuStore {
    let dir: URL
    private(set) var menus: [String: Menu] = [:]
    private(set) var errors: [String] = []

    init(dir: URL) { self.dir = dir; load() }

    func load() {
        var found: [String: Menu] = [:], errs: [String] = []
        let fm = FileManager.default
        for url in (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [] {
            let file = url.lastPathComponent
            guard !file.hasPrefix("."), !file.hasSuffix("~") else { continue }
            let name = url.deletingPathExtension().lastPathComponent
            if url.pathExtension == "toml" {
                do { found[name] = try Menu.parse(name: name, toml: try String(contentsOf: url, encoding: .utf8)) }
                catch { errs.append("menus/\(file): \(error)") }
            } else if fm.isExecutableFile(atPath: url.path) {
                found[name] = Menu(name: name, prompt: Menu.defaultPrompt(name), entries: [], executable: url)
            }
        }
        menus = found
        errors = errs
    }

    /// Runs an executable menu off the main thread and returns its entries on the main thread.
    /// Also returns the refresh interval the menu asked for, if any.
    func list(_ menu: Menu, done: @escaping ([MenuEntry], Double?) -> Void) {
        guard let exe = menu.executable else { return done(menu.entries, nil) }
        DispatchQueue.global(qos: .userInitiated).async {
            let (out, status) = Shell.run(capturing: exe.path, [], timeout: 5)
            if status != 0 { Log.error("menu \(menu.name) failed with exit code \(status)") }
            // A failing menu says so instead of showing up empty.
            let entries = status == 0 ? Menu.parseOutput(out)
                : [MenuEntry(name: "\(menu.name) failed", subtitle: status < 0 ? "could not run it" : "exit code \(status)",
                             icon: "nf-md-alert", value: "\u{0}")]
            DispatchQueue.main.async { done(entries, status == 0 ? Menu.refreshInterval(out) : nil) }
        }
    }
}

enum Shell {
    /// PATH for commands: launchd gives agents only /usr/bin:/bin:/usr/sbin:/sbin.
    static let path = [NSHomeDirectory() + "/.local/bin", "/opt/homebrew/bin", "/usr/local/bin",
                       "/usr/bin", "/bin", "/usr/sbin", "/sbin"].joined(separator: ":")

    static var environment: [String: String] {
        var e = ProcessInfo.processInfo.environment
        e["PATH"] = path
        return e
    }

    static func which(_ tool: String) -> String? {
        path.split(separator: ":").map { "\($0)/\(tool)" }.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Fire and forget, detached from fener's lifetime.
    static func run(_ exe: String, _ args: [String], extraEnv: [String: String] = [:]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        p.environment = environment.merging(extraEnv) { $1 }
        p.standardInput = FileHandle.nullDevice
        p.standardOutput = FileHandle.nullDevice
        p.standardError = Log.handle()   // a failing menu command explains itself in the log
        let shown = ([exe] + args).joined(separator: " ").prefix(200)
        p.terminationHandler = { if $0.terminationStatus != 0 { Log.error("exit \($0.terminationStatus): \(shown)") } }
        do { try p.run() } catch { Log.error("cannot run \(exe): \(error.localizedDescription)") }
    }

    static func sh(_ command: String, extraEnv: [String: String] = [:]) { run("/bin/sh", ["-c", command], extraEnv: extraEnv) }

    /// Runs `command` in a new terminal window that waits for Return before closing.
    /// `template` is split on spaces and `{}` becomes "/bin/sh <script>"; the script sets
    /// PATH and the env first, because apps started with `open` get a bare environment.
    static func inTerminal(_ command: String, template: String, extraEnv: [String: String] = [:]) {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("fener/run")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let script = dir.appendingPathComponent(UUID().uuidString + ".sh")
        func q(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        var body = "#!/bin/sh\nrm -f \"$0\"\nexport PATH=\(q(path))\n"
        for (k, v) in extraEnv.sorted(by: { $0.key < $1.key }) { body += "export \(k)=\(q(v))\n" }
        body += command + "\nstatus=$?\nprintf '\\n[exit %s] Press Return to close.' \"$status\"\nread _\n"
        guard (try? body.write(to: script, atomically: true, encoding: .utf8)) != nil else { return }
        let parts = template.split(separator: " ").map { $0.replacingOccurrences(of: "{}", with: "/bin/sh " + script.path) }
        guard let exe = parts.first else { return }
        if exe.hasPrefix("/") { run(exe, Array(parts.dropFirst())) }
        else if let found = which(exe) { run(found, Array(parts.dropFirst())) }
    }

    /// Runs and returns stdout, or nil on failure or timeout. Call off the main thread.
    static func capture(_ exe: String, _ args: [String], timeout: TimeInterval) -> String? {
        let (out, status) = run(capturing: exe, args, timeout: timeout)
        return status == 0 ? out : nil
    }

    /// Runs and returns stdout and the exit status (-1 when it could not start). Off the main thread.
    static func run(capturing exe: String, _ args: [String], timeout: TimeInterval) -> (String, Int32) {
        let p = Process(), pipe = Pipe()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        p.environment = environment
        p.standardOutput = pipe
        p.standardInput = FileHandle.nullDevice
        p.standardError = Log.handle()
        do { try p.run() } catch { Log.error("cannot run \(exe): \(error.localizedDescription)"); return ("", -1) }
        let killer = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        killer.cancel()
        return (String(decoding: data, as: UTF8.self), p.terminationStatus)
    }
}

/// Icons named in menu files:
///   nf-fa-cog       a Nerd Font glyph by name (www.nerdfonts.com/cheat-sheet), drawn in the theme font
///   /path, ~/path   an app bundle's icon or an image file (square thumbnail)
///   com.apple.Notes an app's icon by bundle id
///   a short non-ASCII string: a glyph or emoji pasted as is
///   anything else   an SF Symbol name
/// Single-color icons (glyphs, SF Symbols) are template images, so a row can tint them.
enum Icons {
    private static var cache: [String: NSImage] = [:]
    static func clearCache() { cache.removeAll() }

    static func named(_ spec: String, theme: Theme) -> NSImage? {
        guard !spec.isEmpty else { return nil }
        if let i = cache[spec] { return i }
        let img = resolve(spec, theme: theme)
        cache[spec] = img
        return img
    }

    static func app(bundleId: String) -> NSImage? {
        if let i = cache[bundleId] { return i }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else { return nil }
        let i = NSWorkspace.shared.icon(forFile: url.path)
        cache[bundleId] = i
        return i
    }

    private static func resolve(_ spec: String, theme: Theme) -> NSImage? {
        if spec.hasPrefix("/") || spec.hasPrefix("~") {
            let path = (spec as NSString).expandingTildeInPath
            if path.hasSuffix(".app") { return NSWorkspace.shared.icon(forFile: path) }
            return thumbnail(path, side: theme.iconSize * 2)
        }
        if spec.hasPrefix("nf-") {
            guard let g = NerdGlyphs.glyph(spec) else { return glyph("•", theme: theme) }  // unknown name
            return glyph(g, theme: theme)
        }
        if spec.count <= 2, spec.unicodeScalars.contains(where: { !$0.isASCII }) { return glyph(spec, theme: theme) }
        if spec.contains("."), !spec.contains(" "), let i = app(bundleId: spec) { return i }
        let cfg = NSImage.SymbolConfiguration(pointSize: theme.iconSize * 0.7, weight: .regular)
        let img = NSImage(systemSymbolName: spec, accessibilityDescription: nil)?.withSymbolConfiguration(cfg)
        img?.isTemplate = true
        return img
    }

    /// True when the theme font draws Nerd Font glyphs (checked with the gear, U+F013).
    static func fontHasNerdGlyphs(_ theme: Theme) -> Bool {
        var ch: [UniChar] = [0xF013], g: [CGGlyph] = [0]
        return CTFontGetGlyphsForCharacters(theme.font(theme.iconSize) as CTFont, &ch, &g, 1) && g[0] != 0
    }

    /// Private Use Area code points are Nerd Font icons (single color); most emoji are not.
    private static func isMonochrome(_ s: String) -> Bool {
        s.unicodeScalars.allSatisfy { u in
            (0xE000...0xF8FF).contains(u.value) || (0xF0000...0x10FFFD).contains(u.value) || !u.properties.isEmoji
        }
    }

    /// Square, center-cropped thumbnail decoded at icon size (a 5K wallpaper stays cheap).
    static func thumbnail(_ path: String, side: CGFloat) -> NSImage? {
        guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: side * 4] as CFDictionary) else { return nil }
        let w = CGFloat(cg.width), h = CGFloat(cg.height), m = min(w, h)
        guard let square = cg.cropping(to: CGRect(x: (w - m) / 2, y: (h - m) / 2, width: m, height: m)) else { return nil }
        let img = NSImage(cgImage: square, size: NSSize(width: side / 2, height: side / 2))
        return NSImage(size: img.size, flipped: false) { r in
            NSBezierPath(roundedRect: r, xRadius: 3, yRadius: 3).addClip()
            img.draw(in: r)
            return true
        }
    }

    /// Draws a glyph centered by its ink (not its text box) and scaled so its larger side
    /// fills 80% of the icon square; glyphs from different icon sets then line up.
    private static func glyph(_ s: String, theme: Theme) -> NSImage {
        let side = theme.iconSize, box = side * 0.8
        let mono = isMonochrome(s)
        let isNerd = s.unicodeScalars.contains { (0xE000...0xF8FF).contains($0.value) || $0.value >= 0xF0000 }
        let text = isNerd && !fontHasNerdGlyphs(theme) ? "•" : s   // no Nerd Font: a dot, not a "?" box
        func line(_ size: CGFloat) -> CTLine {
            CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [
                .font: theme.font(size), .foregroundColor: mono ? NSColor.black : theme.text]))
        }
        let probe = CTLineGetBoundsWithOptions(line(side), .useGlyphPathBounds)
        let scale = probe.width > 0 && probe.height > 0 ? box / max(probe.width, probe.height) : 0.8
        let ln = line(side * scale)
        let ink = CTLineGetBoundsWithOptions(ln, .useGlyphPathBounds)
        let img = NSImage(size: NSSize(width: side, height: side), flipped: false) { r in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.textPosition = CGPoint(x: (r.width - ink.width) / 2 - ink.minX, y: (r.height - ink.height) / 2 - ink.minY)
            CTLineDraw(ln, ctx)
            return true
        }
        img.isTemplate = mono
        return img
    }
}
