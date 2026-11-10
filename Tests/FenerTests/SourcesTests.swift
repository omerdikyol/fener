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
