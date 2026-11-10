import XCTest
@testable import fener

final class ConfigEditorTests: XCTestCase {
    let sample = """
    # fener config
    theme = "tokyo-night"   # the default

    # prefixes typed first
    [prefixes]
    calc = "="
    # files = "?"
    files = "/"

    [aliases]
    ws = "workspace"

    """

    func parsed(_ s: String) throws -> [String: Any] { try Toml.parse(s) }

    func testReplaceKeepsEverythingElse() throws {
        let out = ConfigEditor.set(sample, section: "prefixes", key: "files", value: .string("?"))
        XCTAssertEqual(out, sample.replacingOccurrences(of: "files = \"/\"", with: "files = \"?\""))   // only that line changed
        XCTAssertEqual((try parsed(out)["prefixes"] as? [String: Any])?["files"] as? String, "?")
        XCTAssertTrue(out.contains("# files = \"?\""))   // the commented-out line is not touched
    }

    func testTopLevelKeepsTrailingComment() throws {
        let out = ConfigEditor.set(sample, section: nil, key: "theme", value: .string("catppuccin-mocha"))
        XCTAssertTrue(out.contains("theme = \"catppuccin-mocha\"  # the default"))
        XCTAssertEqual(try parsed(out)["theme"] as? String, "catppuccin-mocha")
    }

    func testAddKeyToTopLevelAndToExistingTable() throws {
        var out = ConfigEditor.set(sample, section: nil, key: "home", value: .string(""))
        XCTAssertEqual(try parsed(out)["home"] as? String, "")
        XCTAssertNil((try parsed(out)["prefixes"] as? [String: Any])?["home"])   // not swallowed by [prefixes]
        out = ConfigEditor.set(out, section: "aliases", key: "vol", value: .string("audio"))
        XCTAssertEqual((try parsed(out)["aliases"] as? [String: Any])?["vol"] as? String, "audio")
        XCTAssertEqual((try parsed(out)["aliases"] as? [String: Any])?["ws"] as? String, "workspace")
    }

    func testAddNewTableAtEnd() throws {
        let out = ConfigEditor.set(sample, section: "panel", key: "position", value: .string("top"))
        XCTAssertTrue(out.hasSuffix("[panel]\nposition = \"top\"\n"))
        XCTAssertEqual((try parsed(out)["panel"] as? [String: Any])?["position"] as? String, "top")
    }

    func testValueKindsAndEscaping() throws {
        var out = ConfigEditor.set("", section: "search", key: "sources", value: .strings(["apps", "menus"]))
        out = ConfigEditor.set(out, section: "panel", key: "close_on_blur", value: .bool(false))
        out = ConfigEditor.set(out, section: "panel", key: "animation_ms", value: .int(90))
        out = ConfigEditor.set(out, section: "learning", key: "usage_half_life_days", value: .double(3.5))
        out = ConfigEditor.set(out, section: "apps", key: "terminal", value: .string("My \"Term\" #1"))
        let t = try parsed(out)
        XCTAssertEqual((t["search"] as? [String: Any])?["sources"] as? [String], ["apps", "menus"])
        XCTAssertEqual((t["panel"] as? [String: Any])?["close_on_blur"] as? Bool, false)
        XCTAssertEqual((t["panel"] as? [String: Any])?["animation_ms"] as? Int, 90)
        XCTAssertEqual((t["learning"] as? [String: Any])?["usage_half_life_days"] as? Double, 3.5)
        XCTAssertEqual((t["apps"] as? [String: Any])?["terminal"] as? String, "My \"Term\" #1")
        // Replacing a value that contains '#' keeps no bogus comment.
        let again = ConfigEditor.set(out, section: "apps", key: "terminal", value: .string("Ghostty"))
        XCTAssertEqual(((try parsed(again))["apps"] as? [String: Any])?["terminal"] as? String, "Ghostty")
    }

    func testDoesNotTouchArrayTablesOrSimilarKeys() throws {
        let menu = "[[entry]]\nname = \"a\"\n[panelx]\npositions = 1\n"
        let out = ConfigEditor.set(menu, section: "panel", key: "position", value: .string("top"))
        XCTAssertTrue(out.contains("positions = 1"))
        XCTAssertEqual((try parsed(out)["panel"] as? [String: Any])?["position"] as? String, "top")
    }
}
