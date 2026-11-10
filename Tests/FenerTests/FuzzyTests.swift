import XCTest
@testable import fener

final class FuzzyTests: XCTestCase {
    func rank(_ q: String, _ names: [String]) -> [String] {
        names.compactMap { n in Fuzzy.score(q, n).map { (n, $0) } }.sorted { $0.1 > $1.1 }.map(\.0)
    }

    func testNonSubsequenceFails() {
        XCTAssertNil(Fuzzy.score("xyz", "Safari"))
        XCTAssertNil(Fuzzy.score("fs", "Safari"))       // order matters
        XCTAssertNil(Fuzzy.score("safarii", "Safari"))  // longer than candidate
    }

    func testEmptyQueryMatchesEverything() { XCTAssertEqual(Fuzzy.score("", "Anything"), 0) }

    func testCaseAndDiacriticsInsensitive() {
        XCTAssertNotNil(Fuzzy.score("SAF", "safari"))
        XCTAssertNotNil(Fuzzy.score("cafe", "Café"))
        XCTAssertNotNil(Fuzzy.score("sistem ayarlari", "Sistem Ayarları"))  // Turkish dotless ı
        XCTAssertNotNil(Fuzzy.score("istanbul", "İstanbul"))
    }

    func testPrefixBeatsScattered() {
        XCTAssertEqual(rank("saf", ["Messages Safe", "Safari", "Spotify Audio Files"]).first, "Safari")
    }

    func testWordStartsBeatMidWord() {
        XCTAssertEqual(rank("ss", ["Messages", "System Settings"]).first, "System Settings")
        XCTAssertEqual(rank("am", ["Camera", "Activity Monitor"]).first, "Activity Monitor")
        XCTAssertEqual(rank("mon", ["Moonlight", "Activity Monitor"]).first, "Activity Monitor")
        XCTAssertEqual(rank("vsc", ["Visual Studio Code", "Voice Scanner"]).first, "Visual Studio Code")
    }

    func testCamelCase() {
        XCTAssertEqual(rank("vb", ["Verbose", "VirtualBox"]).first, "VirtualBox")
    }

    func testConsecutiveBeatsGapped() {
        XCTAssertEqual(rank("term", ["Time Recorder Mail", "Terminal"]).first, "Terminal")
    }

    func testShorterWinsTie() {
        XCTAssertEqual(rank("notes", ["Notes Helper Pro", "Notes"]).first, "Notes")
    }

    func testSpacesInQueryIgnored() {
        XCTAssertNotNil(Fuzzy.score("sys set", "System Settings"))
    }
}

final class FrecencyTests: XCTestCase {
    func testDecayAndPersistence() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        let f = Frecency(url: url)
        f.bump("a", now: 0)
        f.bump("a", now: 0)
        XCTAssertEqual(f.value("a", now: 0), 2, accuracy: 1e-9)
        XCTAssertEqual(f.value("a", now: Frecency.halfLife), 1, accuracy: 1e-9)   // halves after one half-life
        XCTAssertEqual(Frecency(url: url).value("a", now: 0), 2, accuracy: 1e-9)  // reloaded from disk
        XCTAssertEqual(f.value("missing"), 0)
    }
}
