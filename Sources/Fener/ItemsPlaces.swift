import AppKit

let bookmarks = Box<[Bookmarks.Bookmark]>([])
let projects = Box<[URL]>([])
/// Re-reads Helium bookmarks and VS Code recents off the main thread (both small files).
func refreshBrowserAndProjects() {
    DispatchQueue.global(qos: .utility).async {
        let b = Bookmarks.helium(), p = VSCodeRecents.load()
        DispatchQueue.main.async { bookmarks.value = b; projects.value = p }
    }
}

func bookmarkItems(_ q: String) -> [Item] {
    bookmarks.value.compactMap { b in
        let host = URL(string: b.url)?.host ?? b.url
        guard let s = q.isEmpty ? 0 : [Fuzzy.score(q, b.name), Fuzzy.score(q, host)].compactMap({ $0 }).max() else { return nil }
        return Item(id: "bookmark:" + b.url, title: b.name, subtitle: b.folder.isEmpty ? host : "\(b.folder) · \(host)",
                    icon: sf("nf-md-bookmark"), run: { if let u = URL(string: b.url) { NSWorkspace.shared.open(u) } }, score: s)
    }.sorted { $0.score > $1.score }
}

let vscode = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.microsoft.VSCode")
func projectItems(_ q: String) -> [Item] {
    let home = NSHomeDirectory()
    return projects.value.enumerated().compactMap { i, u in
        let name = u.deletingPathExtension().lastPathComponent
        guard let s = q.isEmpty ? -i : Fuzzy.score(q, name) else { return nil }
        let dir = u.deletingLastPathComponent().path
        let remote = u.isFileURL ? nil : (u.host ?? "remote").replacingOccurrences(of: "ssh-remote+", with: "ssh ")
        let place = remote.map { "\($0) · \(dir)" } ?? (dir.hasPrefix(home) ? "~" + dir.dropFirst(home.count) : dir)
        return Item(id: "project:" + u.absoluteString, title: name, subtitle: place,
                    icon: sf("nf-md-microsoft_visual_studio_code"), run: {
                        if let vscode, !u.isFileURL {  // remote folders open through VS Code's own CLI
                            let cli = vscode.appendingPathComponent("Contents/Resources/app/bin/code").path
                            Shell.run(cli, [u.hasDirectoryPath || u.pathExtension.isEmpty ? "--folder-uri" : "--file-uri", u.absoluteString])
                        } else if let vscode { NSWorkspace.shared.open([u], withApplicationAt: vscode, configuration: NSWorkspace.OpenConfiguration()) }
                        else { NSWorkspace.shared.open(u) }
                    }, score: s)
    }.sorted { $0.score > $1.score }
}

let recentFiles = SpotlightList(query: "kMDItemLastUsedDate >= $time.today(-14)", dateAttribute: kMDItemLastUsedDate)
let screenshots = SpotlightList(query: "kMDItemIsScreenCapture == 1", dateAttribute: kMDItemContentCreationDate, thumbnails: 40)

func spotlightItems(_ list: SpotlightList, _ q: String, glyph: String) -> [Item] {
    list.refresh(iconSide: theme.iconSize)
    let home = NSHomeDirectory()
    return list.entries.compactMap { e in
        let name = (e.path as NSString).lastPathComponent
        guard let s = q.isEmpty ? 0 : Fuzzy.score(q, name) else { return nil }
        let dir = (e.path as NSString).deletingLastPathComponent
        let when = ago.localizedString(for: e.date, relativeTo: Date())
        return Item(id: "spot:" + e.path, title: name,
                    subtitle: "\(when) · " + (dir.hasPrefix(home) ? "~" + dir.dropFirst(home.count) : dir),
                    icon: list.thumbs[e.path] ?? (list.thumbnails > 0 ? sf(glyph) : NSWorkspace.shared.icon(forFile: e.path)),
                    run: { NSWorkspace.shared.open(URL(fileURLWithPath: e.path)) }, score: s)
    }.sorted { q.isEmpty ? false : $0.score > $1.score }
}
