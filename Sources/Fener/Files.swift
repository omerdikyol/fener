import AppKit

/// Spotlight file search through `mdfind -onlyin ~ -name`, debounced and off the main thread.
/// `search` returns the latest results at once and asks for fresh ones; `onChange` fires
/// when they arrive.
final class FileSearch {
    var onChange: () -> Void = {}
    private var results: [String] = []
    private var requested = ""
    private var pending: DispatchWorkItem?
    private var running: Process?
    private var icons: [String: NSImage] = [:]
    static let limit = 60, debounce = 0.15

    func search(_ query: String) -> [Item] {
        let q = query.trimmingCharacters(in: .whitespaces)
        if q.count < 2 { requested = q; results = []; return [] }
        if q != requested { requested = q; schedule(q) }
        let home = NSHomeDirectory()
        return results.map { path -> (String, Int) in
            let name = (path as NSString).lastPathComponent
            let depth = path.split(separator: "/").count
            return (path, (Fuzzy.score(q, name) ?? 0) - depth)  // shallower paths first
        }.sorted { $0.1 > $1.1 }.map { path, score in
            let dir = (path as NSString).deletingLastPathComponent
            return Item(id: "file:" + path, title: (path as NSString).lastPathComponent,
                        subtitle: dir.hasPrefix(home) ? "~" + dir.dropFirst(home.count) : dir,
                        icon: icon(path), run: { NSWorkspace.shared.open(URL(fileURLWithPath: path)) }, score: score)
        }
    }

    private func icon(_ path: String) -> NSImage {
        if let i = icons[path] { return i }
        let i = NSWorkspace.shared.icon(forFile: path)
        icons[path] = i
        return i
    }

    private func schedule(_ q: String) {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.run(q) }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.debounce, execute: work)
    }

    private func run(_ q: String) {
        running?.terminate()
        let p = Process(), pipe = Pipe()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
        p.arguments = ["-onlyin", NSHomeDirectory(), "-name", q]
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return }
        running = p
        DispatchQueue.global(qos: .userInitiated).async {
            // Read until enough useful lines, then stop mdfind instead of waiting for all matches.
            var buffer = Data(), lines: [String] = []
            let h = pipe.fileHandleForReading
            while lines.count < Self.limit {
                let chunk = h.availableData
                if chunk.isEmpty { break }
                buffer.append(chunk)
                while let nl = buffer.firstIndex(of: 10) {
                    let line = String(decoding: buffer[buffer.startIndex..<nl], as: UTF8.self)
                    buffer.removeSubrange(buffer.startIndex...nl)
                    if Self.useful(line) { lines.append(line) }
                }
            }
            if p.isRunning { p.terminate() }
            DispatchQueue.main.async {
                guard q == self.requested else { return }  // a newer query is on its way
                self.results = lines
                self.onChange()
            }
        }
    }

    /// Skips ~/Library and hidden folders, which are mostly noise for a launcher.
    static func useful(_ path: String) -> Bool {
        let home = NSHomeDirectory()
        if path.hasPrefix(home + "/Library/") { return false }
        return !path.dropFirst(home.count).contains("/.")
    }
}

/// A Spotlight query listed newest first by a date attribute: recent files
/// (kMDItemLastUsedDate) and screenshots (kMDItemIsScreenCapture). Loads in the background,
/// thumbnails included, and calls `onChange` on the main thread.
final class SpotlightList {
    struct Entry { let path: String; let date: Date }
    let query: String, dateAttribute: CFString, limit: Int, thumbnails: Int
    private(set) var entries: [Entry] = []
    private(set) var thumbs: [String: NSImage] = [:]
    var onChange: () -> Void = {}
    private var loading = false, loadedAt = Date.distantPast

    init(query: String, dateAttribute: CFString, limit: Int = 60, thumbnails: Int = 0) {
        self.query = query; self.dateAttribute = dateAttribute; self.limit = limit; self.thumbnails = thumbnails
    }

    /// Reloads when older than a few seconds.
    func refresh(iconSide: CGFloat) {
        guard !loading, Date().timeIntervalSince(loadedAt) > 5 else { return }
        loading = true
        let (q, attr, limit, nThumbs) = (query, dateAttribute, limit, thumbnails)
        DispatchQueue.global(qos: .userInitiated).async {
            let out = Shell.capture("/usr/bin/mdfind", ["-onlyin", NSHomeDirectory(), q], timeout: 5) ?? ""
            let list = out.split(separator: "\n").map(String.init)
                .filter { FileSearch.useful($0) && !$0.hasSuffix(".app") && !$0.contains(".app/") }
                .compactMap { p -> Entry? in
                    guard let item = MDItemCreate(nil, p as CFString),
                          let d = MDItemCopyAttribute(item, attr) as? Date else { return nil }
                    return Entry(path: p, date: d)
                }
                .sorted { $0.date > $1.date }.prefix(limit)
            var t: [String: NSImage] = [:]
            for e in list.prefix(nThumbs) { t[e.path] = Icons.thumbnail(e.path, side: iconSide * 2) }
            DispatchQueue.main.async {
                self.entries = Array(list)
                self.thumbs = t
                self.loading = false
                self.loadedAt = Date()
                self.onChange()
            }
        }
    }
}
