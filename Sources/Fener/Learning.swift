import Foundation

/// What fener learns from picks, kept on this Mac only:
/// - typed text -> picked row ("g" then Ghostty), so the same text ranks that row first;
///   a pick learned for "gh" also helps "g", and the other way round. Decays with a 14-day half-life, at most 500 pairs.
/// - the last 10 picked rows, for the Recently Used view.
/// Only picks are recorded, never keystrokes or abandoned searches. `learn_queries = false`
/// in config.toml stops it; Forget Search History clears both.
final class Learning {
    struct Pair: Codable { var query: String; var id: String; var score: Double; var time: Double }
    struct Recent: Codable, Equatable { var id: String; var title: String; var time: Double }
    private struct Store: Codable { var pairs: [Pair] = []; var recent: [Recent] = [] }

    static let halfLife: Double = 14 * 86_400, maxPairs = 500, maxRecent = 10, maxQueryLength = 32
    var enabled = true
    private var store = Store()
    private let url: URL
    private let io = DispatchQueue(label: "fener.learning", qos: .utility)

    var recent: [Recent] { store.recent }

    init(url: URL) {
        self.url = url
        if let d = try? Data(contentsOf: url), let s = try? JSONDecoder().decode(Store.self, from: d) { store = s }
    }

    static func normalize(_ q: String) -> String {
        String(Fuzzy.fold(q.trimmingCharacters(in: .whitespaces)).prefix(maxQueryLength))
    }

    private func decayed(_ p: Pair, _ now: Double) -> Double { p.score * pow(0.5, (now - p.time) / Self.halfLife) }

    /// Records a pick: always into Recently Used, and with its typed text when there was some.
    func picked(id: String, title: String, query: String?, recent: Bool = true, now: Double = Date().timeIntervalSince1970) {
        guard enabled else { return }
        if recent {
            store.recent.removeAll { $0.id == id }
            store.recent.insert(Recent(id: id, title: title, time: now), at: 0)
            if store.recent.count > Self.maxRecent { store.recent.removeLast(store.recent.count - Self.maxRecent) }
        }
        if let query, case let q = Self.normalize(query), !q.isEmpty {
            if let i = store.pairs.firstIndex(where: { $0.query == q && $0.id == id }) {
                store.pairs[i].score = decayed(store.pairs[i], now) + 1
                store.pairs[i].time = now
            } else {
                store.pairs.append(Pair(query: q, id: id, score: 1, time: now))
            }
            if store.pairs.count > Self.maxPairs {   // drop the weakest
                store.pairs.sort { decayed($0, now) > decayed($1, now) }
                store.pairs.removeLast(store.pairs.count - Self.maxPairs)
            }
        }
        save()
    }

    /// Boost per row id for this query: full weight for picks made with exactly this text,
    /// half for picks made with a longer or shorter text that starts the same way ("gh" helps
    /// "g", and "g" helps "gho"). Only rows that match the query anyway are shown.
    func boosts(for query: String, now: Double = Date().timeIntervalSince1970) -> [String: Int] {
        guard enabled else { return [:] }
        let q = Self.normalize(query)
        guard !q.isEmpty else { return [:] }
        var weight: [String: Double] = [:]
        for p in store.pairs where p.query.starts(with: q) || q.starts(with: p.query) {
            weight[p.id, default: 0] += decayed(p, now) * (p.query == q ? 1 : 0.5)
        }
        return weight.mapValues { Int(60 * log2(1 + $0)) }
    }

    func forget() {
        store = Store()
        save()
    }

    private func save() {
        let snapshot = store, url = url
        io.async {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            guard let d = try? JSONEncoder().encode(snapshot) else { return }
            try? d.write(to: url, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            var v = URLResourceValues(); v.isExcludedFromBackup = true
            var u = url; try? u.setResourceValues(v)
        }
    }
}
