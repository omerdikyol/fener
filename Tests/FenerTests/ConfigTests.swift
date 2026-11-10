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
        let builtins: Set = ["apps", "clipboard", "emoji", "files", "system", "windows", "calc", "quit", "snippets", "dictionary"]
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
}
