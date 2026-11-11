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
