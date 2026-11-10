import XCTest
import CryptoKit
@testable import fener

final class ClipboardStoreTests: XCTestCase {
    var root: URL!
    override func setUp() {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: root) }

    /// Waits for the background key load and the first save.
    func waitFor(_ cond: @autoclosure () -> Bool) {
        let deadline = Date().addingTimeInterval(5)
        while !cond(), Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
    }

    func legacyFolder(with clips: [Clipboard.Clip], png: Data? = nil) throws -> URL {
        let old = root.appendingPathComponent("old")
        try FileManager.default.createDirectory(at: old.appendingPathComponent("images"), withIntermediateDirectories: true)
        try JSONEncoder().encode(clips).write(to: old.appendingPathComponent("history.json"))
        if let png { try png.write(to: old.appendingPathComponent("images/img.png")) }
        return old
    }

    func testMigratesPlaintextIntoEncryptedStore() throws {
        let key = SymmetricKey(size: .bits256)
        let png = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 4, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            .representation(using: .png, properties: [:])!
        let old = try legacyFolder(with: [
            .init(id: "a", kind: .text, text: "secret-ish text", hash: "h1", date: Date()),
            .init(id: "b", kind: .image, text: "", image: "img.png", width: 4, height: 4, hash: "h2", date: Date().addingTimeInterval(-60)),
        ], png: png)
        let dir = root.appendingPathComponent("new")
        let c = Clipboard(dir: dir, legacy: old, loadKey: { key })
        let store = dir.appendingPathComponent("history.enc")
        waitFor(FileManager.default.fileExists(atPath: store.path) && c.clips.count == 2)

        XCTAssertEqual(c.clips.map(\.id), ["a", "b"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: old.path))                 // plaintext removed
        let raw = try Data(contentsOf: store)
        XCTAssertNil(raw.range(of: Data("secret-ish".utf8)))                           // not readable on disk
        XCTAssertNotNil(c.image(c.clips[1]))                                             // image decrypts
        let imgFile = try FileManager.default.contentsOfDirectory(atPath: dir.appendingPathComponent("images").path)
        XCTAssertEqual(imgFile, ["b.png.enc"])
        XCTAssertEqual(try URL(fileURLWithPath: dir.path).resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)

        // A second instance with the same key reads it back; a different key cannot.
        let again = Clipboard(dir: dir, loadKey: { key })
        waitFor(again.clips.count == 2)
        XCTAssertEqual(again.clips.first?.text, "secret-ish text")
        let wrong = Clipboard(dir: dir, loadKey: { SymmetricKey(size: .bits256) })
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        XCTAssertTrue(wrong.clips.isEmpty)
    }

    func testExpiryAndIgnoreList() throws {
        let key = SymmetricKey(size: .bits256)
        let old = try legacyFolder(with: [
            .init(id: "new", kind: .text, text: "x", hash: "1", date: Date()),
            .init(id: "old", kind: .text, text: "y", hash: "2", date: Date().addingTimeInterval(-40 * 86_400)),
        ])
        let c = Clipboard(dir: root.appendingPathComponent("s"), legacy: old, loadKey: { key })
        waitFor(c.clips.count == 1)                       // the 40-day-old item is gone (default 30)
        XCTAssertEqual(c.clips.map(\.id), ["new"])
        c.keepDays = 1
        c.purgeExpired(now: Date().addingTimeInterval(2 * 86_400))
        XCTAssertTrue(c.clips.isEmpty)

        let list: Set = ["com.1password.1password", "bitwarden"]
        XCTAssertTrue(Clipboard.ignored(bundleId: "com.1Password.1password", name: "1Password", in: list))
        XCTAssertTrue(Clipboard.ignored(bundleId: "com.x", name: "Bitwarden", in: list))
        XCTAssertFalse(Clipboard.ignored(bundleId: "com.apple.Safari", name: "Safari", in: list))
        XCTAssertFalse(Clipboard.ignored(bundleId: nil, name: nil, in: list))
    }

    func testNoKeyMeansNothingIsWritten() throws {
        let old = try legacyFolder(with: [.init(id: "a", kind: .text, text: "x", hash: "1", date: Date())])
        let dir = root.appendingPathComponent("nokey")
        _ = Clipboard(dir: dir, legacy: old, loadKey: { nil })
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("history.enc").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: old.path))   // legacy left alone without a key
    }
}
