import AppKit

/// Open windows from OmniWM (`omniwmctl query windows`), most recently used first.
final class WindowProvider {
    struct Win: Decodable {
        struct App: Decodable { let name: String?; let bundleId: String? }
        struct Workspace: Decodable { let number: Int? }
        let id: String
        let title: String?
        let app: App?
        let workspace: Workspace?
        let isFocused: Bool?
    }
    private struct Reply: Decodable {
        struct Result: Decodable { struct Payload: Decodable { let windows: [Win] }; let payload: Payload }
        let ok: Bool
        let result: Result?
    }

    private(set) var windows: [Win] = []
    private let tool = Shell.which("omniwmctl")
    private var loading = false
    var onChange: () -> Void = {}

    var available: Bool { tool != nil }

    static func decode(_ data: Data) -> [Win]? {
        guard let r = try? JSONDecoder().decode(Reply.self, from: data), r.ok else { return nil }
        return r.result?.payload.windows
    }

    /// Fetches off the main thread; calls onChange on the main thread when the list arrives.
    func refresh() {
        guard let tool, !loading else { return }
        loading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let out = Shell.capture(tool, ["query", "windows", "--sort", "mru", "--format", "json"], timeout: 2)
            let list = out.flatMap { Self.decode(Data($0.utf8)) }
            DispatchQueue.main.async {
                self.loading = false
                guard let list else { return }
                let changed = list.map(\.id) != self.windows.map(\.id) || list.map(\.title) != self.windows.map(\.title)
                self.windows = list
                if changed { self.onChange() }
            }
        }
    }

    /// Fuzzy search on "title app"; the focused window (the one behind the panel) goes last.
    func search(_ query: String, all: Bool) -> [Item] {
        let q = Fuzzy.fold(query).filter { $0 != " " }
        var out: [Item] = []
        for (rank, w) in windows.enumerated() {
            let app = w.app?.name ?? "", title = (w.title?.isEmpty == false ? w.title! : app)
            var score = 0
            if !q.isEmpty {
                let a = Fuzzy.score(String(q), title), b = Fuzzy.score(String(q), app)
                guard let s = [a, b].compactMap({ $0 }).max() else { continue }
                score = s
            } else if !all { continue }
            var sub = app
            if let n = w.workspace?.number { sub += " · workspace \(n)" }
            let item = Item(id: "window:" + w.id, title: title, subtitle: sub,
                            icon: w.app?.bundleId.flatMap(Icons.app(bundleId:)),
                            run: { [tool, id = w.id] in if let tool { Shell.run(tool, ["window", "focus", id]) } },
                            score: score - (w.isFocused == true ? 1000 : min(rank, 8)),
                            actions: { [tool, id = w.id] in
                                guard let tool else { return [] }
                                return [
                                    Act.make("Close Window", "nf-md-window_close") { Shell.run(tool, ["window", "close", id]) },
                                    Act.make("Bring Here", "nf-md-arrow_collapse_left") { Shell.run(tool, ["window", "summon-right", id]) },
                                    Item(id: "action:move", title: "Move to Workspace", accessory: "›", icon: sf("nf-md-swap_horizontal"),
                                         submenu: { Mode(prompt: "Move to workspace…") { _ in (1...9).map { n in
                                             Act.make("Workspace \(n)", "nf-md-numeric_\(n)_box") { Shell.run(tool, ["window", "move-to-workspace", id, "\(n)"]) }
                                         } } }),
                                    Act.copy("Copy Title", title),
                                ]
                            })
            out.append(item)
        }
        return out
    }
}
