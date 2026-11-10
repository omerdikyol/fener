import AppKit

/// Web searches and quicklinks: `<keyword> <query>` opens a URL template in the default
/// browser, e.g. `g fener` or `gh swift toml`. fener itself sends nothing; the browser does.
///
/// ~/.config/fener/quicklinks.toml adds links or replaces built-in ones by keyword:
///
///     default = "d"                    # engine for the "Search … for" row at the bottom
///
///     [[link]]
///     keyword = "gh"
///     name = "GitHub"
///     url = "https://github.com/search?q={query}"   # {query} is URL-encoded
///     icon = "nf-fa-github"            # optional
struct Quicklink: Equatable {
    var keyword: String
    var name: String
    var url: String
    var icon = "nf-md-web"

    static let builtIn: [Quicklink] = [
        Quicklink(keyword: "d", name: "DuckDuckGo", url: "https://duckduckgo.com/?q={query}", icon: "nf-md-duck"),
        Quicklink(keyword: "g", name: "Google", url: "https://www.google.com/search?q={query}", icon: "nf-fa-google"),
        Quicklink(keyword: "k", name: "Kagi", url: "https://kagi.com/search?q={query}", icon: "nf-md-magnify"),
        Quicklink(keyword: "gh", name: "GitHub", url: "https://github.com/search?q={query}", icon: "nf-fa-github"),
        Quicklink(keyword: "yt", name: "YouTube", url: "https://www.youtube.com/results?search_query={query}", icon: "nf-fa-youtube"),
        Quicklink(keyword: "wiki", name: "Wikipedia", url: "https://en.wikipedia.org/wiki/Special:Search?search={query}", icon: "nf-fa-wikipedia_w"),
        Quicklink(keyword: "maps", name: "Maps", url: "https://maps.apple.com/?q={query}", icon: "nf-md-map"),
    ]

    /// Strict percent-encoding: only unreserved characters stay, so &, +, # and spaces in a
    /// query can never change the URL's meaning.
    static func encode(_ q: String) -> String {
        q.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")) ?? ""
    }

    func url(for query: String) -> URL? { URL(string: url.replacingOccurrences(of: "{query}", with: Self.encode(query))) }
}

struct Quicklinks {
    var links = Quicklink.builtIn
    var defaultKeyword = "d"

    var defaultEngine: Quicklink? { links.first { $0.keyword == defaultKeyword } ?? links.first }

    static func parse(_ text: String, problems: inout [String]) -> Quicklinks {
        var q = Quicklinks()
        let t: [String: Any]
        do { t = try Toml.parse(text) } catch { problems.append("quicklinks.toml: \(error)"); return q }
        for k in t.keys where k != "default" && k != "link" { problems.append("quicklinks.toml: unknown key \(k)") }
        for (i, row) in (t["link"] as? [[String: Any]] ?? []).enumerated() {
            guard let kw = row["keyword"] as? String, !kw.isEmpty, !kw.contains(" "),
                  let name = row["name"] as? String, let url = row["url"] as? String else {
                problems.append("quicklinks.toml: link \(i + 1) needs keyword (no spaces), name and url"); continue
            }
            guard url.hasPrefix("https://") || url.hasPrefix("http://") || url.contains("://") else {
                problems.append("quicklinks.toml: link \(kw) url must be a full URL"); continue
            }
            let link = Quicklink(keyword: kw, name: name, url: url, icon: row["icon"] as? String ?? "nf-md-web")
            if let j = q.links.firstIndex(where: { $0.keyword == kw }) { q.links[j] = link } else { q.links.append(link) }
        }
        if let d = t["default"] as? String {
            if q.links.contains(where: { $0.keyword == d }) { q.defaultKeyword = d }
            else { problems.append("quicklinks.toml: default \(d) is not a link keyword") }
        }
        return q
    }

    /// "gh swift toml" -> (GitHub, "swift toml"); a bare keyword matches with an empty query.
    func match(_ raw: String) -> (Quicklink, String)? {
        let parts = raw.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard let first = parts.first, let link = links.first(where: { $0.keyword == String(first) }) else { return nil }
        return (link, parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespaces) : "")
    }
}
