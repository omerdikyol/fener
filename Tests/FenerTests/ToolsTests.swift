import XCTest
@testable import fener

final class ToolsTests: XCTestCase {
    func testSettingsPaneIdsExistOnThisMac() throws {
        let dir = "/System/Library/ExtensionKit/Extensions"
        var ids: Set<String> = []
        for a in try FileManager.default.contentsOfDirectory(atPath: dir) where a.hasSuffix(".appex") {
            if let d = NSDictionary(contentsOfFile: "\(dir)/\(a)/Contents/Info.plist"), let id = d["CFBundleIdentifier"] as? String { ids.insert(id) }
        }
        for p in SettingsPanes.all { XCTAssertTrue(ids.contains(p.id), "\(p.name): \(p.id)") }
    }

    func testBookmarksParse() {
        let json = """
        {"roots": {"bookmark_bar": {"type": "folder", "name": "Bar", "children": [
            {"type": "url", "name": "Swift", "url": "https://swift.org"},
            {"type": "folder", "name": "Work", "children": [{"type": "url", "name": "Issues", "url": "https://github.com/issues"}]}]},
          "other": {"type": "folder", "name": "Other", "children": []}}}
        """
        let b = Bookmarks.parse(Data(json.utf8)).sorted { $0.name < $1.name }
        XCTAssertEqual(b.map(\.name), ["Issues", "Swift"])
        XCTAssertEqual(b.first?.folder, "Work")
    }

    func testVSCodeRecentsParse() throws {
        let tmp = FileManager.default.temporaryDirectory.path
        let json = """
        {"entries": [{"folderUri": "file://\(tmp)"}, {"folderUri": "vscode-remote://ssh-remote+box/home"},
                     {"fileUri": "file:///does/not/exist.txt"}, {"workspace": {"configPath": "file://\(tmp)"}}]}
        """
        let r = VSCodeRecents.parse(Data(json.utf8))
        XCTAssertEqual(r.count, 3)   // missing local entry dropped, remote kept
        XCTAssertEqual(r.filter { !$0.isFileURL }.first?.host, "ssh-remote+box")
    }

    func testProcessesParse() {
        let p = Processes.parse("  123  1.5  20480 /usr/bin/thing\n 9 30.0 1024 Safari\nbad line\n")
        XCTAssertEqual(p.map(\.name), ["Safari", "thing"])   // most CPU first
        XCTAssertEqual(p.last?.memMB, 20)
    }

    func testGenerators() {
        let pw = Generators.password(length: 32, symbols: false)
        XCTAssertEqual(pw.count, 32)
        XCTAssertTrue(pw.allSatisfy { $0.isLetter || $0.isNumber })
        XCTAssertFalse(pw.contains { "lIO01".contains($0) })   // no look-alikes
        XCTAssertNotEqual(Generators.password(length: 20, symbols: true), Generators.password(length: 20, symbols: true))
        XCTAssertEqual(Generators.pin(6).count, 6)
        XCTAssertEqual(Generators.password(length: 1, symbols: true).count, 4)   // clamped
    }

    func testAliasesConfig() {
        var p: [String] = []
        let c = Config.parse("[aliases]\nWS = \"workspace\"\nvol = \"audio\"\nbad = 3", problems: &p)
        XCTAssertEqual(c.aliases, ["ws": "workspace", "vol": "audio"])
        XCTAssertEqual(p.count, 1)
    }

    func testAudioDevicesListed() throws {
        let d = Audio.devices()
        guard !d.isEmpty else { throw XCTSkip("no audio devices") }
        XCTAssertTrue(d.contains { $0.output })
        XCTAssertTrue(d.contains { $0.id == Audio.defaultDevice(input: false) })
    }
}

final class SearchQualityTests: XCTestCase {
    func testQualityBar() {
        XCTAssertEqual(minimumScore("a"), 18)
        XCTAssertEqual(minimumScore("sys set"), 108)          // spaces do not count
        XCTAssertEqual(minimumScore("a very long query here"), 144)
        // A word-start match clears the bar; letters scattered through a long title do not.
        XCTAssertGreaterThanOrEqual(Fuzzy.score("key", "Keyboard")!, minimumScore("key"))
        XCTAssertLessThan(Fuzzy.score("nt", "Printers & Scanners") ?? 0, minimumScore("nt"))
    }

    func testTrackedIds() {
        XCTAssertTrue(tracked("menu:workspace:Workspace 3"))
        XCTAssertTrue(tracked("pane:com.apple.Keyboard-Settings.extension"))
        XCTAssertFalse(tracked("/Applications/Safari.app"))   // apps count launches themselves
        XCTAssertFalse(tracked("calc"))
        XCTAssertFalse(tracked("gen:Password"))
        XCTAssertFalse(tracked(""))
    }
}

final class ActionTests: XCTestCase {
    func testFileActions() {
        XCTAssertEqual(Act.file("/tmp/x.txt").map(\.title), ["Show in Finder", "Quick Look", "Copy Path", "Copy File"])
        XCTAssertEqual(Act.url("https://a.b").map(\.title), ["Copy URL"])
        XCTAssertTrue(Act.file("/tmp").allSatisfy { $0.id.hasPrefix("action:") && !tracked($0.id) })
    }

    func testAppActionsIncludeQuitOnlyWhenRunning() {
        let finder = NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == "com.apple.finder" }?.bundleURL?.path
        if let finder { XCTAssertTrue(Act.app(finder).map(\.title).contains("Quit")) }
        XCTAssertEqual(Act.app("/Applications/Not Running Here.app").map(\.title), ["Show in Finder", "Copy Path"])
    }

    func testMenuEntryActions() throws {
        var m = try Menu.parse(name: "t", toml: "[[entry]]\nname = \"Run\"\ncommand = \"echo hi\"")
        XCTAssertNil(entryItem(m.entries[0], of: m, score: 0).actions)          // no file: nothing to edit
        m.file = URL(fileURLWithPath: "/tmp/t.toml")
        XCTAssertEqual(entryItem(m.entries[0], of: m, score: 0).actions?().map(\.title), ["Edit Menu File", "Copy Command"])
    }
}
