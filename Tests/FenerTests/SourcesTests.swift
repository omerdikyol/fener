import XCTest
@testable import fener

final class SourcesTests: XCTestCase {
    func testClipboardSkipsConcealedAndTransient() {
        XCTAssertTrue(Clipboard.shouldRecord(types: ["public.utf8-plain-text"]))
        XCTAssertFalse(Clipboard.shouldRecord(types: ["public.utf8-plain-text", "org.nspasteboard.ConcealedType"]))
        XCTAssertFalse(Clipboard.shouldRecord(types: ["org.nspasteboard.TransientType", "public.png"]))
    }

    func testEmojiIndex() {
        XCTAssertEqual(Emoji.search("grinning face").first?.char, "😀")
        XCTAssertEqual(Emoji.search("rightwards arrow").first?.char, "→")
        XCTAssertEqual(Emoji.search("flag turk").first?.char, "🇹🇷")
        XCTAssertEqual(Emoji.search("greek small letter alpha").first?.char, "α")
        XCTAssertGreaterThan(Emoji.all.count, 2500)
        XCTAssertFalse(Emoji.all.contains { $0.code == "U+1F394" })  // no font draws it
    }

    func testFileFilter() {
        let h = NSHomeDirectory()
        XCTAssertTrue(FileSearch.useful(h + "/Documents/report.pdf"))
        XCTAssertFalse(FileSearch.useful(h + "/Library/Caches/x"))
        XCTAssertFalse(FileSearch.useful(h + "/.config/fener/menus/a.toml"))
    }
}

final class TerminalTests: XCTestCase {
    func testInTerminalRunsCommandWithEnvAndCleansUp() throws {
        let out = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: out) }
        // A "terminal" that just runs the script; `read` gets EOF from /dev/null and returns.
        Shell.inTerminal("echo \"$FENER_CHOICE it's\" > '\(out.path)'", template: "/bin/sh -c {}",
                         extraEnv: ["FENER_CHOICE": "quote's"])
        let deadline = Date().addingTimeInterval(5)
        while !FileManager.default.fileExists(atPath: out.path), Date() < deadline { usleep(20_000) }
        usleep(100_000)
        XCTAssertEqual(try String(contentsOf: out, encoding: .utf8), "quote's it's\n")
        let runDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("fener/run")
        XCTAssertEqual((try? FileManager.default.contentsOfDirectory(atPath: runDir.path))?.filter { $0.hasSuffix(".sh") }.count ?? 0, 0)
    }
}

final class ExecutableMenuTests: XCTestCase {
    func testOutputRefreshAndFailureRow() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        func script(_ name: String, _ body: String) throws {
            let u = dir.appendingPathComponent(name)
            try ("#!/bin/sh\n" + body).write(to: u, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: u.path)
        }
        try script("live.sh", "echo '{\"name\": \"a\"}'; echo '{\"refresh\": 0.1}'")
        try script("broken.sh", "echo partial; exit 3")
        let store = MenuStore(dir: dir)

        let live = expectation(description: "live"), broken = expectation(description: "broken")
        store.list(store.menus["live"]!) { entries, refresh in
            XCTAssertEqual(entries.map(\.name), ["a"])   // the refresh line is not an entry
            XCTAssertEqual(refresh, 0.5)                  // clamped to at least 0.5 s
            live.fulfill()
        }
        store.list(store.menus["broken"]!) { entries, refresh in
            XCTAssertEqual(entries.map(\.name), ["broken failed"])
            XCTAssertEqual(entries.first?.subtitle, "exit code 3")
            XCTAssertNil(refresh)
            broken.fulfill()
        }
        wait(for: [live, broken], timeout: 5)
    }
}
