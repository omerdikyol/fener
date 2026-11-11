import AppKit

// `fener` runs the resident agent app; `fener toggle|show|hide|reload|ping` talks to it
// over a Unix socket. App flags: `--show` opens the panel at launch, `--demo` adds a plain
// gradient backdrop for screenshots, `--query <text>` prefills the search, `--bench`
// prints scan and search timings and exits.

let args = CommandLine.arguments
if args.count > 1, args[1] == "log" { exit(Log.show(follow: args.contains("-f"))) }
if args.count > 1, args[1] == "config" {   // fener config [defaults]
    if args.count > 2, args[2] == "defaults" { print(DefaultConfig.text, terminator: ""); exit(0) }
    let dir = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".config/fener")
    print("settings:    \(dir.path)/config.toml   (edit; applies on save)")
    print("all options: \(dir.path)/config.reference.toml   (reference, rewritten on start)")
    print("also:        menus/, themes/, snippets/, quicklinks.toml in the same folder")
    exit(0)
}
if args.count > 1, IPC.commands.contains(args[1]) {
    exit(IPC.send(Array(args.dropFirst())))  // client: never touches NSApplication
}

if !args.contains("--bench"), IPC.isRunning() {
    // Opening fener.app (or running `fener`) again shows the panel.
    _ = IPC.send(["show"])
    exit(0)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)  // same effect as LSUIElement: no Dock icon, no menu bar
setvbuf(stdout, nil, _IOLBF, 0)

let t0 = CACurrentMediaTime()
let scanCount = apps.apps.count
let scanMs = (CACurrentMediaTime() - t0) * 1000

if args.contains("--bench") {
    print(String(format: "scanned %d apps in %.1f ms", scanCount, scanMs))
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

DispatchQueue.global(qos: .utility).async { _ = Emoji.all.count }  // build the emoji index early

do {
    let (c, th, p) = loadSettings()
    config = c; theme = th; problems = p + menus.errors
    configureClipboard(c)
    learning.enabled = c.learnQueries
}
_ = launcher  // build and pre-warm the panel now (globals are lazy), after settings are loaded
configureBehavior(config)
Hotkey.set(config.shortcut) { launcher.toggle() }
if let e = Hotkey.error { problems.append(e) }
windows.onChange = { launcher.refilter() }
files.onChange = { launcher.refilter() }
rates.onChange = { launcher.refilter() }
recentFiles.onChange = { launcher.refilter() }
screenshots.onChange = { launcher.refilter() }
refreshBrowserAndProjects()
windows.refresh()

try? FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
let firstRun = writeConfigFiles()
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

let server = IPC.Server(path: IPC.socketPath, handle: handleCommand)
if server == nil { exit(0) }  // lost a start-up race with another instance
Log.info("started (pid \(getpid()), \(apps.apps.count) apps, \(menus.menus.count) menus)")
problems.forEach { Log.error($0) }

DispatchQueue.main.async {
    // First run: start at login, and show the panel so a downloaded app visibly does something
    // (with any shortcut clash listed at the top).
    if firstRun, !args.contains("--demo") { registerLoginItem(); launcher.show() }
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

/// Opening fener.app while it runs (Finder, Spotlight, `open`) shows the panel.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        launcher.show()
        return false
    }
}
// An app with no menu bar still routes Cmd+V, C, X, A and Z to the search field through its
// main menu, which is never shown.
do {
    let edit = NSMenu(title: "Edit")
    for (title, action, key, mods) in [("Undo", "undo:", "z", NSEvent.ModifierFlags.command), ("Redo", "redo:", "z", [.command, .shift]),
                                       ("Cut", "cut:", "x", .command), ("Copy", "copy:", "c", .command),
                                       ("Paste", "paste:", "v", .command), ("Select All", "selectAll:", "a", .command)] {
        let item = NSMenuItem(title: title, action: Selector(action), keyEquivalent: key)
        item.keyEquivalentModifierMask = mods
        edit.addItem(item)
    }
    let main = NSMenu(), editItem = NSMenuItem()
    editItem.submenu = edit
    main.addItem(editItem)
    app.mainMenu = main
}
let appDelegate = AppDelegate()
app.delegate = appDelegate
app.run()
