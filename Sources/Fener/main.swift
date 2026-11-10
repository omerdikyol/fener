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

let launcher = Launcher(theme: theme, search: apps.search)
launcher.onShow = { apps.refresh() }
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
        if words.count > 1 { return "error: menus are not implemented yet" }
        launcher.show()
    case "hide": launcher.hide()
    case "reload": apps.refresh()
    case "ping": break
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
