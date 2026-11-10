import AppKit

struct AppEntry {
    let path: String
    let name: String           // localized display name, e.g. "System Settings"
    let fileName: String       // bundle file name without .app, matched as an alias
}

enum AppScanner {
    /// Folders scanned for apps (config [apps] folders).
    static var folders = ["/Applications", "/System/Applications", NSHomeDirectory() + "/Applications"]
    /// Apps that live outside the scanned folders but people expect to find.
    static let extras = ["/System/Library/CoreServices/Finder.app"]

    /// Walks each root two levels deep (covers /Applications/Utilities and vendor folders)
    /// without descending into bundles.
    static func scan() -> [AppEntry] {
        let fm = FileManager.default
        var seen = Set<String>(), out: [AppEntry] = []
        func add(_ path: String) {
            let real = (path as NSString).resolvingSymlinksInPath
            guard seen.insert(real).inserted else { return }
            let file = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
            var name = fm.displayName(atPath: path)
            if name.hasSuffix(".app") { name = String(name.dropLast(4)) }
            out.append(AppEntry(path: path, name: name, fileName: file))
        }
        func walk(_ dir: String, depth: Int) {
            guard let names = try? fm.contentsOfDirectory(atPath: dir) else { return }
            for n in names where !n.hasPrefix(".") {
                let p = dir + "/" + n
                if n.hasSuffix(".app") { add(p) }
                else if depth > 0, (try? fm.attributesOfItem(atPath: p)[.type] as? FileAttributeType) == .typeDirectory {
                    walk(p, depth: depth - 1)
                }
            }
        }
        folders.forEach { walk($0, depth: 1) }
        extras.filter(fm.fileExists).forEach(add)
        return out
    }
}

/// Launch counts that decay with a 7-day half-life, kept in ~/Library/Caches/fener.
final class Frecency {
    private struct Entry: Codable { var score: Double; var time: Double }
    private var entries: [String: Entry] = [:]
    private let url: URL
    static let halfLife: Double = 7 * 86400
    var halfLife = Frecency.halfLife   // config [learning] usage_half_life_days

    init(url: URL) {
        self.url = url
        if let d = try? Data(contentsOf: url), let e = try? JSONDecoder().decode([String: Entry].self, from: d) {
            entries = e
        }
    }

    func value(_ key: String, now: Double = Date().timeIntervalSince1970) -> Double {
        guard let e = entries[key] else { return 0 }
        return e.score * pow(0.5, (now - e.time) / halfLife)
    }

    func bump(_ key: String, now: Double = Date().timeIntervalSince1970) {
        entries[key] = Entry(score: value(key, now: now) + 1, time: now)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(entries).write(to: url, options: .atomic)
    }
}

final class AppProvider {
    private(set) var apps: [AppEntry] = []
    private typealias Target = (folded: [Character], original: [Character])
    private var targets: [(name: Target, file: Target)] = []
    private var icons: [String: NSImage] = [:]
    let frecency: Frecency
    private let scanQueue = DispatchQueue(label: "fener.scan", qos: .userInitiated)

    init(frecency: Frecency) {
        self.frecency = frecency
        set(AppScanner.scan())
    }

    private func set(_ list: [AppEntry]) {
        apps = list
        func target(_ s: String) -> Target {
            let o = Array(s.prefix(Fuzzy.maxLength))
            return (Fuzzy.fold(String(o)), o)
        }
        targets = list.map { (target($0.name), target($0.fileName)) }
    }

    /// Rescans off the main thread; new results apply to the next search.
    func refresh() {
        scanQueue.async {
            let list = AppScanner.scan()
            DispatchQueue.main.async { self.set(list) }
        }
    }

    func search(_ query: String) -> [Item] {
        let q = Fuzzy.fold(query).filter { $0 != " " }
        var ranked: [(Int, Double, Int)] = []  // (score, frecency, index)
        for (i, t) in targets.enumerated() {
            let fr = frecency.value(apps[i].path)
            if q.isEmpty { ranked.append((0, fr, i)); continue }
            let s = max(Fuzzy.score(q, folded: t.name.folded, original: t.name.original) ?? Int.min,
                        Fuzzy.score(q, folded: t.file.folded, original: t.file.original) ?? Int.min)
            if s == Int.min { continue }
            ranked.append((s + Int(12 * log2(1 + fr)), fr, i))
        }
        ranked.sort { a, b in
            if a.0 != b.0 { return a.0 > b.0 }
            if a.1 != b.1 { return a.1 > b.1 }
            return apps[a.2].name.localizedCaseInsensitiveCompare(apps[b.2].name) == .orderedAscending
        }
        return ranked.map { r in var i = item(apps[r.2]); i.score = r.0; return i }
    }

    private func item(_ app: AppEntry) -> Item {
        Item(id: app.path, title: app.name, icon: icon(app.path), run: { [weak self] in self?.launch(app) },
             actions: { Act.app(app.path) })
    }

    private func icon(_ path: String) -> NSImage {
        if let i = icons[path] { return i }
        let i = NSWorkspace.shared.icon(forFile: path)
        icons[path] = i
        return i
    }

    func launch(_ app: AppEntry) {
        frecency.bump(app.path)
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = true
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: app.path), configuration: cfg) { _, err in
            if let err { Log.error("launch failed: \(app.path): \(err.localizedDescription)") }
        }
    }
}
