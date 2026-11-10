import XCTest
@testable import fener

final class ConfigTests: XCTestCase {
    func testDefaultsWhenEmpty() {
        var p: [String] = []
        let c = Config.parse("", problems: &p)
        XCTAssertEqual(c.theme, "tokyo-night")
        XCTAssertEqual(c.prefixes["files"], "/")
        XCTAssertTrue(c.clipboardEnabled)
        XCTAssertEqual(p, [])
    }

    func testValuesAndWarnings() {
        var p: [String] = []
        let c = Config.parse("""
        theme = "gruvbox"
        colour = "x"
        [prefixes]
        files = "?"
        windows = ""
        bogus = "!"
        [clipboard]
        enabled = false
        max_items = 50
        max_item_bytes = "big"
        """, problems: &p)
        XCTAssertEqual(c.theme, "gruvbox")
        XCTAssertEqual(c.prefixes["files"], "?")
        XCTAssertEqual(c.prefixes["windows"], "")       // turned off
        XCTAssertFalse(c.clipboardEnabled)
        XCTAssertEqual(c.clipboardMaxItems, 50)
        XCTAssertEqual(c.clipboardMaxItemBytes, 5_000_000)  // bad value keeps the default
        XCTAssertEqual(p.count, 3)  // colour, bogus prefix, max_item_bytes
        XCTAssertTrue(p.contains { $0.contains("unknown key colour") })
    }

    func testDuplicatePrefixWarns() {
        var p: [String] = []
        _ = Config.parse("[prefixes]\nfiles = \":\"", problems: &p)
        XCTAssertTrue(p.contains { $0.contains("same") })
    }

    func testSyntaxErrorKeepsDefaults() {
        var p: [String] = []
        let c = Config.parse("theme = ", problems: &p)
        XCTAssertEqual(c.theme, "tokyo-night")
        XCTAssertEqual(p.first, "config.toml: line 1: missing value")
    }

    func testTheme() {
        var p: [String] = []
        let t = Theme.parse("""
        [colors]
        accent = "#ff9e64"
        border = "#7aa2f7cc"
        background_opacity = 0.8
        muted = "red"
        [font]
        size = 13
        [layout]
        width = 600
        corner_radius = 12
        visible_rows = 7
        wobble = 1
        """, name: "t", problems: &p)
        XCTAssertEqual(t.accent, NSColor(hexString: "#ff9e64"))
        XCTAssertEqual(t.border.alphaComponent, 0.8, accuracy: 0.01)
        XCTAssertEqual(t.backgroundOpacity, 0.8)
        XCTAssertEqual(t.fontSize, 13)
        XCTAssertEqual(t.width, 600)
        XCTAssertEqual(t.cornerRadius, 12)
        XCTAssertEqual(t.visibleRows, 7)
        XCTAssertEqual(t.muted, Theme().muted)            // invalid color keeps the base
        XCTAssertEqual(p.count, 2)                         // muted, wobble
        XCTAssertNotEqual(t, Theme())
    }

    func testHexColors() {
        XCTAssertNotNil(NSColor(hexString: "#1a1b26"))
        XCTAssertNil(NSColor(hexString: "1a1b26"))
        XCTAssertNil(NSColor(hexString: "#12345"))
        XCTAssertNil(NSColor(hexString: "#gggggg"))
    }

    func testShippedFilesMatchDefaults() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        var p: [String] = []
        let theme = Theme.parse(try String(contentsOf: root.appendingPathComponent("extras/themes/tokyo-night.toml"), encoding: .utf8),
                                name: "tokyo-night", problems: &p)
        XCTAssertEqual(theme, Theme())
        let c = Config.parse(try String(contentsOf: root.appendingPathComponent("extras/config.toml"), encoding: .utf8), problems: &p)
        XCTAssertEqual(c.prefixes, Config().prefixes)
        let d = Config()
        XCTAssertEqual([c.panelPosition, c.panelScreen, c.browser, c.editor, c.terminalApp], [d.panelPosition, d.panelScreen, d.browser, d.editor, d.terminalApp])
        XCTAssertEqual(c.sources, d.sources)
        XCTAssertEqual([c.fileLimit, c.recentDays, c.screenshotThumbnails, c.animationMs], [d.fileLimit, d.recentDays, d.screenshotThumbnails, d.animationMs])
        XCTAssertEqual(p, [])
    }

    func testShippedMenusAndThemesParse() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let fm = FileManager.default
        let menuDir = root.appendingPathComponent("extras/menus")
        var names: Set<String> = []
        for f in try fm.contentsOfDirectory(atPath: menuDir.path) {
            names.insert((f as NSString).deletingPathExtension)
            guard f.hasSuffix(".toml") else { continue }
            XCTAssertNoThrow(try Menu.parse(name: f, toml: String(contentsOf: menuDir.appendingPathComponent(f), encoding: .utf8)), f)
        }
        // Every submenu a shipped menu points at exists, as a file or a built-in.
        let builtins: Set = ["apps", "clipboard", "emoji", "files", "system", "windows", "calc", "quit", "snippets", "dictionary", "settings", "audio", "bookmarks", "projects", "recent", "screenshots", "generate", "processes", "used", "preferences"]
        for f in try fm.contentsOfDirectory(atPath: menuDir.path) where f.hasSuffix(".toml") {
            let m = try Menu.parse(name: f, toml: String(contentsOf: menuDir.appendingPathComponent(f), encoding: .utf8))
            for e in m.entries where !e.menu.isEmpty {
                XCTAssertTrue(names.contains(e.menu) || builtins.contains(e.menu), "\(f): \(e.menu)")
            }
        }
        for f in try fm.contentsOfDirectory(atPath: root.appendingPathComponent("extras/themes").path) {
            var p: [String] = []
            _ = Theme.parse(try String(contentsOf: root.appendingPathComponent("extras/themes/" + f), encoding: .utf8), name: f, problems: &p)
            XCTAssertEqual(p, [], f)
        }
    }

    func testMenuFlagsAndWidth() throws {
        let m = try Menu.parse(name: "m", toml: "width = 320\n[[entry]]\nname = \"a\"\ncommand = \"x\"\nterminal = true\nconfirm = true")
        XCTAssertEqual(m.width, 320)
        XCTAssertTrue(m.entries[0].terminal && m.entries[0].confirm)
        XCTAssertThrowsError(try Menu.parse(name: "m", toml: "width = 50"))
        XCTAssertThrowsError(try Menu.parse(name: "m", toml: "[[entry]]\nname = \"a\"\ncommand = \"x\"\nterminal = \"yes\""))
    }

    func testNewSectionsValidate() {
        var p: [String] = []
        let c = Config.parse("""
        [panel]
        position = "top"
        screen = "sideways"
        animation_ms = 5000
        [search]
        sources = ["apps", "bookmarks", "nope"]
        [apps]
        editor = "cursor"
        terminal = ""
        [learning]
        usage_half_life_days = 3.5
        """, problems: &p)
        XCTAssertEqual(c.panelPosition, "top")
        XCTAssertEqual(c.panelScreen, "mouse")         // invalid keeps the default
        XCTAssertEqual(c.animationMs, 120)
        XCTAssertEqual(c.sources, ["apps", "bookmarks"])
        XCTAssertEqual(c.editor, "cursor")
        XCTAssertEqual(c.terminalApp, "Ghostty")
        XCTAssertEqual(c.usageHalfLifeDays, 3.5)
        XCTAssertEqual(p.count, 4)                     // screen, animation_ms, unknown source, empty terminal
    }

    /// The defaults written as config.reference.toml (and on first run as config.toml) must be
    /// the shipped example, parse without problems, and mean exactly the built-in defaults.
    func testDefaultConfigTextMatchesEverything() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("extras/config.toml"), encoding: .utf8), DefaultConfig.text)
        var p: [String] = []
        let c = Config.parse(DefaultConfig.text, problems: &p)
        XCTAssertEqual(p, [])
        XCTAssertEqual(c, Config())
        for section in ["prefixes", "aliases", "currency", "clipboard", "panel", "search", "files", "apps", "learning"] {
            XCTAssertTrue(DefaultConfig.text.contains("[\(section)]"), section)
        }
        XCTAssertEqual(Config.parse("terminal = \"x {}\"", problems: &p).terminal, "x {}")
    }
}
