import AppKit

/// One row of a custom menu.
struct MenuEntry: Equatable {
    var name: String
    var subtitle = ""
    var icon = ""
    var command = ""      // run with /bin/sh -c
    var menu = ""         // open this menu instead (a submenu)
    var value = ""        // executable menus: what is handed back (defaults to name)
}

/// A menu from ~/.config/fener/menus: `<name>.toml` with static entries, or an executable
/// `<name>[.ext]` that prints entries and is run again with the chosen one.
struct Menu {
    var name: String
    var prompt: String
    var icon = ""
    var entries: [MenuEntry]      // static entries (TOML menus)
    var executable: URL?          // dmenu-style menus

    /// Parses a TOML menu:
    ///     prompt = "Themes…"          # optional
    ///     icon = "paintpalette"       # optional, shown where the menu itself is listed
    ///     [[entry]]
    ///     name = "Tokyo Night"
    ///     subtitle = "dark"          # optional
    ///     icon = "paintpalette"      # optional: SF Symbol, nerd-font glyph, app/image path
    ///     command = "theme tokyo"    # or: menu = "other-menu"
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
            let e = MenuEntry(name: try str("name"), subtitle: try str("subtitle"), icon: try str("icon"),
                              command: try str("command"), menu: try str("menu"))
            if e.name.isEmpty { throw Toml.ParseError(line: 0, message: "entry \(i + 1) has no name") }
            if e.command.isEmpty == e.menu.isEmpty {
                throw Toml.ParseError(line: 0, message: "entry \(i + 1) (\(e.name)) needs exactly one of command or menu")
            }
            entries.append(e)
        }
        return Menu(name: name, prompt: t["prompt"] as? String ?? defaultPrompt(name), icon: t["icon"] as? String ?? "",
                    entries: entries)
    }

    static func defaultPrompt(_ name: String) -> String { title(name) + "…" }
    static func title(_ name: String) -> String { name.prefix(1).uppercased() + name.dropFirst() }

    /// Parses an executable menu's output: a JSON array of objects, or one entry per line,
    /// each line either plain text (the name) or a JSON object
    /// {"name": …, "subtitle": …, "icon": …, "value": …, "command": …, "menu": …}.
    static func parseOutput(_ out: String) -> [MenuEntry] {
        func entry(_ o: [String: Any]) -> MenuEntry? {
            guard let name = o["name"] as? String, !name.isEmpty else { return nil }
            func s(_ k: String) -> String { o[k] as? String ?? "" }
            return MenuEntry(name: name, subtitle: s("subtitle"), icon: s("icon"), command: s("command"),
                             menu: s("menu"), value: s("value"))
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
        errs.forEach { FileHandle.standardError.write("fener: \($0)\n".data(using: .utf8)!) }
    }

    /// Runs an executable menu off the main thread and returns its entries on the main thread.
    func list(_ menu: Menu, done: @escaping ([MenuEntry]) -> Void) {
        guard let exe = menu.executable else { return done(menu.entries) }
        DispatchQueue.global(qos: .userInitiated).async {
            let out = Shell.capture(exe.path, [], timeout: 5)
            DispatchQueue.main.async { done(Menu.parseOutput(out ?? "")) }
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
        do { try p.run() } catch {
            FileHandle.standardError.write("fener: cannot run \(exe): \(error)\n".data(using: .utf8)!)
        }
    }

    static func sh(_ command: String, extraEnv: [String: String] = [:]) { run("/bin/sh", ["-c", command], extraEnv: extraEnv) }

    /// Runs and returns stdout, or nil on failure or timeout. Call off the main thread.
    static func capture(_ exe: String, _ args: [String], timeout: TimeInterval) -> String? {
        let p = Process(), pipe = Pipe()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        p.environment = environment
        p.standardOutput = pipe
        p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let killer = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        killer.cancel()
        return p.terminationStatus == 0 ? String(decoding: data, as: UTF8.self) : nil
    }
}

/// Icons named in menu files: an absolute or ~ path (app bundle or image file), a bundle id
/// (contains a dot), a short non-ASCII string (nerd-font glyph or emoji), or an SF Symbol name.
enum Icons {
    private static var cache: [String: NSImage] = [:]

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
        if spec.count <= 2, spec.unicodeScalars.contains(where: { !$0.isASCII }) { return glyph(spec, theme: theme) }
        if spec.contains("."), !spec.contains(" "), let i = app(bundleId: spec) { return i }
        let cfg = NSImage.SymbolConfiguration(pointSize: theme.iconSize * 0.7, weight: .regular)
            .applying(.init(paletteColors: [theme.text]))
        return NSImage(systemSymbolName: spec, accessibilityDescription: nil)?.withSymbolConfiguration(cfg)
    }

    /// Square, center-cropped thumbnail decoded at icon size (a 5K wallpaper stays cheap).
    private static func thumbnail(_ path: String, side: CGFloat) -> NSImage? {
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

    private static func glyph(_ s: String, theme: Theme) -> NSImage {
        let size = NSSize(width: theme.iconSize, height: theme.iconSize)
        let str = NSAttributedString(string: s, attributes: [.font: theme.font(theme.iconSize * 0.8), .foregroundColor: theme.text])
        return NSImage(size: size, flipped: false) { r in
            let b = str.size()
            str.draw(at: NSPoint(x: (r.width - b.width) / 2, y: (r.height - b.height) / 2))
            return true
        }
    }
}
