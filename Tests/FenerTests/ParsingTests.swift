import XCTest
@testable import fener

final class TomlTests: XCTestCase {
    func testScalarsTablesAndComments() throws {
        let t = try Toml.parse("""
        # comment
        title = "fener" # trailing comment
        width = 480
        ratio = 0.5
        big = 1_000
        on = true
        lit = 'C:\\no\\escapes'
        esc = "tab\\there \\"q\\" \\u00e7"
        list = [1, "two", false]
        "quoted key" = 1

        [theme]
        name = "tokyo-night"

        [theme.colors]
        accent = "#7aa2f7"
        """)
        XCTAssertEqual(t["title"] as? String, "fener")
        XCTAssertEqual(t["width"] as? Int, 480)
        XCTAssertEqual(t["ratio"] as? Double, 0.5)
        XCTAssertEqual(t["big"] as? Int, 1000)
        XCTAssertEqual(t["on"] as? Bool, true)
        XCTAssertEqual(t["lit"] as? String, "C:\\no\\escapes")
        XCTAssertEqual(t["esc"] as? String, "tab\there \"q\" ç")
        XCTAssertEqual((t["list"] as? [Any])?.count, 3)
        XCTAssertEqual(t["quoted key"] as? Int, 1)
        let theme = t["theme"] as? [String: Any]
        XCTAssertEqual(theme?["name"] as? String, "tokyo-night")
        XCTAssertEqual((theme?["colors"] as? [String: Any])?["accent"] as? String, "#7aa2f7")
    }

    func testArrayOfTables() throws {
        let t = try Toml.parse("""
        prompt = "Pick"
        [[entry]]
        name = "a"
        [[entry]]
        name = "b"
        command = "echo b"
        """)
        let e = t["entry"] as? [[String: Any]]
        XCTAssertEqual(e?.count, 2)
        XCTAssertEqual(e?[1]["command"] as? String, "echo b")
        XCTAssertEqual(t["prompt"] as? String, "Pick")
    }

    func testErrorsCarryLineNumbers() {
        func line(_ s: String) -> Int? { do { _ = try Toml.parse(s); return nil } catch let e as Toml.ParseError { return e.line } catch { return -1 } }
        XCTAssertEqual(line("a = 1\nb = \n"), 2)               // missing value
        XCTAssertEqual(line("a = \"open\n"), 1)                 // unterminated string
        XCTAssertEqual(line("a = 1\na = 2"), 2)                 // duplicate key
        XCTAssertEqual(line("[t]\n[t]"), 2)                     // duplicate table
        XCTAssertEqual(line("x = {a = 1}"), 1)                  // inline tables unsupported
        XCTAssertEqual(line("x = \"\"\"multi"), 1)              // multi-line strings unsupported
        XCTAssertEqual(line("x = 1 2"), 1)                      // junk after value
        XCTAssertEqual(line("x = [1, 2"), 1)                    // unclosed array
        XCTAssertEqual(line("x = yes"), 1)                      // bare word
    }
}

final class MenuTests: XCTestCase {
    func testTomlMenu() throws {
        let m = try Menu.parse(name: "power", toml: """
        [[entry]]
        name = "Lock"
        icon = "lock"
        command = "pmset displaysleepnow"
        [[entry]]
        name = "More"
        menu = "system"
        """)
        XCTAssertEqual(m.prompt, "Power…")
        XCTAssertEqual(m.entries.map(\.name), ["Lock", "More"])
        XCTAssertEqual(m.entries[1].menu, "system")
    }

    func testTomlMenuValidation() {
        XCTAssertThrowsError(try Menu.parse(name: "m", toml: "[[entry]]\ncommand = \"x\""))             // no name
        XCTAssertThrowsError(try Menu.parse(name: "m", toml: "[[entry]]\nname = \"a\""))                // no action
        XCTAssertThrowsError(try Menu.parse(name: "m", toml: "[[entry]]\nname = \"a\"\ncommand = \"x\"\nmenu = \"y\""))
        XCTAssertThrowsError(try Menu.parse(name: "m", toml: "[[entry]]\nname = 3\ncommand = \"x\""))   // wrong type
    }

    func testExecutableOutputFormats() {
        XCTAssertEqual(Menu.parseOutput("one\n  two  \n\nthree\n").map(\.name), ["one", "two", "three"])
        let nd = Menu.parseOutput("""
        {"name": "Street", "value": "/w/street.jpg", "subtitle": "jpg"}
        plain line
        {"broken": true}
        """)
        XCTAssertEqual(nd.map(\.name), ["Street", "plain line"])  // JSON without a name is skipped
        XCTAssertEqual(nd.first?.value, "/w/street.jpg")
        let arr = Menu.parseOutput(#"[{"name": "a"}, {"name": "b", "icon": "star"}, {"nope": 1}]"#)
        XCTAssertEqual(arr.map(\.name), ["a", "b"])
        XCTAssertEqual(arr[1].icon, "star")
    }
}

final class WindowDecodeTests: XCTestCase {
    func testOmniWMReply() {
        let json = """
        {"id":"1","kind":"response","ok":true,"status":"success","version":1,"result":{"kind":"windows","payload":{"windows":[
          {"id":"ow_a","title":"Notes","app":{"name":"Ghostty","bundleId":"com.mitchellh.ghostty"},
           "workspace":{"number":2,"displayName":"2"},"isFocused":false,"pid":1,"frame":{"x":0,"y":0,"width":1,"height":1}},
          {"id":"ow_b","title":null,"app":{"name":"Finder"},"workspace":null}
        ]}}}
        """
        let w = WindowProvider.decode(Data(json.utf8))
        XCTAssertEqual(w?.map(\.id), ["ow_a", "ow_b"])
        XCTAssertEqual(w?[0].workspace?.number, 2)
        XCTAssertNil(w?[1].title)
        XCTAssertNil(WindowProvider.decode(Data(#"{"ok":false}"#.utf8)))
    }
}
