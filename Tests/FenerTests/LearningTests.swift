import XCTest
@testable import fener

final class LearningTests: XCTestCase {
    func store() -> Learning {
        Learning(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json"))
    }

    func testExactAndPrefixBoost() {
        let l = store()
        l.picked(id: "/Applications/Ghostty.app", title: "Ghostty", query: "g", now: 0)
        l.picked(id: "/Applications/Ghostty.app", title: "Ghostty", query: "G ", now: 0)   // normalized to "g"
        l.picked(id: "menu:workspace:Workspace 3", title: "Workspace 3", query: "ws3", now: 0)
        let g = l.boosts(for: "g", now: 0)
        XCTAssertEqual(g["/Applications/Ghostty.app"], Int(60 * log2(3.0)))   // two picks, exact
        XCTAssertNil(g["menu:workspace:Workspace 3"])
        XCTAssertEqual(l.boosts(for: "ws", now: 0)["menu:workspace:Workspace 3"], Int(60 * log2(1.5)))  // "ws3" helps "ws" at half weight
        XCTAssertEqual(l.boosts(for: "gho", now: 0)["/Applications/Ghostty.app"], Int(60 * log2(2.0)))  // "g" helps "gho" at half weight
        XCTAssertTrue(l.boosts(for: "x", now: 0).isEmpty)
        XCTAssertTrue(l.boosts(for: "", now: 0).isEmpty)
    }

    func testDecayAndPersistence() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        let l = Learning(url: url)
        l.picked(id: "a", title: "A", query: "q", now: 0)
        XCTAssertEqual(l.boosts(for: "q", now: 0)["a"], 60)
        XCTAssertEqual(l.boosts(for: "q", now: Learning.halfLife)["a"], Int(60 * log2(1.5)))
        let deadline = Date().addingTimeInterval(3)
        while !FileManager.default.fileExists(atPath: url.path), Date() < deadline { usleep(20_000) }
        usleep(100_000)
        XCTAssertEqual(Learning(url: url).recent.map(\.id), ["a"])
        try? FileManager.default.removeItem(at: url)
    }

    func testRecentListAndLimits() {
        let l = store()
        for i in 0..<12 { l.picked(id: "id\(i)", title: "T\(i)", query: nil, now: Double(i)) }
        XCTAssertEqual(l.recent.count, 10)
        XCTAssertEqual(l.recent.first?.id, "id11")
        l.picked(id: "id5", title: "T5", query: nil, now: 20)           // picked again: moves to the top, no duplicate
        XCTAssertEqual(l.recent.first?.id, "id5")
        XCTAssertEqual(l.recent.filter { $0.id == "id5" }.count, 1)
        l.picked(id: "menu:x", title: "X", query: "x", recent: false, now: 21)   // opened menu: learned, not listed
        XCTAssertNotEqual(l.recent.first?.id, "menu:x")
        XCTAssertNotNil(l.boosts(for: "x", now: 21)["menu:x"])

        let big = store()
        for i in 0..<(Learning.maxPairs + 20) { big.picked(id: "r\(i)", title: "", query: "q\(i)", recent: false, now: Double(i)) }
        XCTAssertNil(big.boosts(for: "q0", now: 600)["r0"])               // the oldest, weakest pairs were dropped
        XCTAssertNotNil(big.boosts(for: "q519", now: 600)["r519"])
    }

    func testOffSwitchAndForget() {
        let l = store()
        l.enabled = false
        l.picked(id: "a", title: "A", query: "a", now: 0)
        XCTAssertTrue(l.recent.isEmpty)
        l.enabled = true
        l.picked(id: "a", title: "A", query: "a", now: 0)
        l.forget()
        XCTAssertTrue(l.recent.isEmpty)
        XCTAssertTrue(l.boosts(for: "a", now: 0).isEmpty)
    }

    func testWhatIsRemembered() {
        XCTAssertTrue(remembered("/Applications/Ghostty.app"))
        XCTAssertTrue(remembered("bookmark:https://swift.org"))
        for id in ["calc", "gen:Password", "action:Copy Path", "confirm:yes", "link:g", "problem:x", ""] {
            XCTAssertFalse(remembered(id), id)
        }
        var p: [String] = []
        XCTAssertFalse(Config.parse("learn_queries = false", problems: &p).learnQueries)
        XCTAssertEqual(p, [])
    }
}
