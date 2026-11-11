import XCTest
@testable import fener

final class HotkeyTests: XCTestCase {
    func testParseAndWrite() throws {
        let c = try XCTUnwrap(Hotkey.parse("Hyper + Space"))
        XCTAssertEqual(c.mods, [.control, .option, .command])
        XCTAssertEqual(Hotkey.string(c), "ctrl+opt+cmd+space")
        for s in ["shift+cmd+k", "ctrl+f5", "f13", "ctrl+opt+cmd+comma", "cmd+key93"] {
            XCTAssertEqual(Hotkey.string(try XCTUnwrap(Hotkey.parse(s), s)), s)
        }
        XCTAssertNil(Hotkey.parse("cmd+nokey"))
        XCTAssertNil(Hotkey.parse("cmd+a+b"))
        XCTAssertNil(Hotkey.parse("cmd+shift"))
    }

    func testOnlyCommandControlOrFunctionKeys() throws {
        XCTAssertNil(Hotkey.problem(try XCTUnwrap(Hotkey.parse("cmd+space"))))
        XCTAssertNil(Hotkey.problem(try XCTUnwrap(Hotkey.parse("ctrl+opt+k"))))
        XCTAssertNil(Hotkey.problem(try XCTUnwrap(Hotkey.parse("f6"))))
        for s in ["space", "opt+space", "opt+shift+k", "shift+a"] {
            XCTAssertNotNil(Hotkey.problem(try XCTUnwrap(Hotkey.parse(s))), s)
        }
    }
}

final class HotkeySystemTests: XCTestCase {
    func testSpotlightClash() throws {
        let cmdSpace = try XCTUnwrap(Hotkey.parse("cmd+space"))
        XCTAssertEqual(Hotkey.systemOwner(cmdSpace, hotkeys: [:]), "Spotlight")   // factory setting
        let off: [String: Any] = ["64": ["enabled": false, "value": ["parameters": [65535, 49, 1048576]]]]
        XCTAssertNil(Hotkey.systemOwner(cmdSpace, hotkeys: off))
        XCTAssertNil(Hotkey.systemOwner(try XCTUnwrap(Hotkey.parse("shift+cmd+space")), hotkeys: [:]))
    }
}

final class BookmarkBrowserTests: XCTestCase {
    func testAutoPicksTheDefaultBrowserThenAnInstalledOne() {
        XCTAssertEqual(Bookmarks.resolve("brave", defaultBundleId: "com.google.Chrome", installed: { _ in true }), "brave")
        XCTAssertEqual(Bookmarks.resolve("auto", defaultBundleId: "company.thebrowser.Browser", installed: { _ in false }), "arc")
        XCTAssertEqual(Bookmarks.resolve("auto", defaultBundleId: "com.apple.Safari", installed: { $0 == "vivaldi" }), "vivaldi")
        XCTAssertEqual(Bookmarks.resolve("auto", defaultBundleId: nil, installed: { _ in false }), "none")
    }
}
