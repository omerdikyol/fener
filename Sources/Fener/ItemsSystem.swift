import AppKit

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
        view("Projects", "nf-md-microsoft_visual_studio_code", "projects"),
        view("fener Settings", "nf-md-cog_outline", "preferences"),
        view("Recently Used", "nf-md-history", "used"),
        Item(id: "system:forget", title: "Forget Search History", subtitle: "learned searches and Recently Used",
             accessory: "›", icon: sf("nf-md-delete_clock"),
             submenu: { confirm(SystemAction(name: "Forget Search History", subtitle: "", icon: "nf-md-delete_clock", confirm: true) {
                 learning.forget()
             }) }),
    ].compactMap { i -> Item? in
        if q.isEmpty, !inSystemView.contains(i.id) { return nil }
        guard let s = q.isEmpty ? 0 : Fuzzy.score(q, i.title) else { return nil }
        var i = i; i.score = s; return i
    }
    return actions + extra
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

let procCache = Box<(Date, [Processes.Proc])>((.distantPast, []))
/// Name search, or ":3000" for whatever listens on that TCP port.
func processItems(_ q: String) -> [Item] {
    if Date().timeIntervalSince(procCache.value.0) > 2 { procCache.value = (Date(), Processes.list()) }
    let port = q.hasPrefix(":") ? Int(q.dropFirst()) : nil
    let pids = port.map(Processes.listening(port:))
    return procCache.value.1.compactMap { p in
        if let pids { guard pids.contains(p.pid) else { return nil } }
        guard p.pid != getpid(), let s = (q.isEmpty || pids != nil) ? 0 : Fuzzy.score(q, p.name) else { return nil }
        var item = Item(id: "proc:\(p.pid)", title: p.name, subtitle: String(format: "pid %d · %.1f%% CPU · %d MB", p.pid, p.cpu, p.memMB),
                    accessory: "›", icon: sf("nf-md-chip"), score: s, submenu: {
            Mode(prompt: "Stop \(p.name)?") { _ in [
                Item(id: "proc:term", title: "Quit (SIGTERM)", icon: sf("nf-md-close_circle"), run: { kill(p.pid, SIGTERM) }),
                Item(id: "proc:kill", title: "Kill (SIGKILL)", subtitle: "unsaved work is lost", icon: sf("nf-md-skull"),
                     run: { kill(p.pid, SIGKILL) }),
                Item(id: "proc:no", title: "Cancel", icon: sf("nf-md-close")),
            ] }
        })
        item.actions = { [Act.make("Kill Now (SIGKILL)", "nf-md-skull") { kill(p.pid, SIGKILL) }, Act.copy("Copy PID", "\(p.pid)")] }
        return item
    }.sorted { $0.score > $1.score }
}
