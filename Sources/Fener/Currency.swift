import Foundation

/// Exchange rates from the European Central Bank's daily reference rates (about 30
/// currencies, quoted against EUR). The only network request fener makes: one GET of a
/// public XML file, at most once a day, and only when a currency conversion is typed.
/// No account, key or user data is involved. Turn it off with `[currency] enabled = false`.
final class Currency {
    static let source = URL(string: "https://www.ecb.europa.eu/stats/eurofxref/eurofxref-daily.xml")!
    static let codes: Set = ["EUR", "USD", "JPY", "BGN", "CZK", "DKK", "GBP", "HUF", "PLN", "RON", "SEK", "CHF", "ISK",
                             "NOK", "TRY", "AUD", "BRL", "CAD", "CNY", "HKD", "IDR", "ILS", "INR", "KRW", "MXN", "MYR",
                             "NZD", "PHP", "SGD", "THB", "ZAR"]
    static let symbols: [String: String] = ["$": "USD", "€": "EUR", "£": "GBP", "₺": "TRY", "¥": "JPY"]

    private(set) var rates: [String: Double] = [:]   // per 1 EUR; EUR itself is 1
    private(set) var date = ""                        // the ECB's reference date
    var enabled = true
    var onChange: () -> Void = {}
    private let cache: URL
    private var fetching = false

    init(cacheDir: URL) {
        cache = cacheDir.appendingPathComponent("ecb-rates.xml")
        if let d = try? Data(contentsOf: cache), let (r, day) = Self.parse(d) { rates = r; date = day }
    }

    /// Parses the ECB file: <Cube time='2026-11-10'> with <Cube currency='USD' rate='1.0812'/> rows.
    static func parse(_ data: Data) -> ([String: Double], String)? {
        let s = String(decoding: data, as: UTF8.self)
        guard let day = s.firstMatch(of: #/time=['"](\d{4}-\d{2}-\d{2})['"]/#)?.1 else { return nil }
        var r: [String: Double] = ["EUR": 1]
        for m in s.matches(of: #/currency=['"]([A-Z]{3})['"]\s+rate=['"]([0-9.]+)['"]/#) {
            if let v = Double(m.2), v > 0 { r[String(m.1)] = v }
        }
        return r.count > 1 ? (r, String(day)) : nil
    }

    /// Converts using EUR as the pivot; nil when a rate is missing.
    func convert(_ amount: Double, from: String, to: String) -> Double? {
        guard let f = rates[from], let t = rates[to] else { return nil }
        return amount / f * t
    }

    /// Refreshes when the cached file is over a day old (or missing), off the main thread.
    func refreshIfStale() {
        guard enabled, !fetching else { return }
        let age = (try? cache.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
            .map { Date().timeIntervalSince($0) } ?? .infinity
        guard age > 86_400 || rates.isEmpty else { return }
        fetching = true
        let cfg = URLSessionConfiguration.ephemeral   // no cookies, no cache, no credentials
        cfg.timeoutIntervalForRequest = 10
        URLSession(configuration: cfg).dataTask(with: Self.source) { [weak self] data, response, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.fetching = false
                guard (response as? HTTPURLResponse)?.statusCode == 200, let data, let (r, day) = Self.parse(data) else { return }
                try? data.write(to: self.cache, options: .atomic)
                self.rates = r
                self.date = day
                self.onChange()
            }
        }.resume()
    }

    /// "100 usd to try", "100usd in eur", "€50 to try", "1,5 gbp = usd".
    static func query(_ s: String) -> (amount: String, from: String, to: String)? {
        let parts = s.replacingOccurrences(of: "->", with: " to ").split(separator: " ").map(String.init)
        guard parts.count >= 3, ["to", "in", "as", "="].contains(parts[parts.count - 2]) else { return nil }
        let to = code(parts[parts.count - 1])
        var left = parts[..<(parts.count - 2)].joined()
        guard let to else { return nil }
        for (sym, c) in symbols where left.hasPrefix(sym) { left = String(left.dropFirst(sym.count)) + c.lowercased() }
        guard let i = left.firstIndex(where: { $0.isLetter }) else { return nil }
        let amount = String(left[..<i]), unit = String(left[i...])
        guard !amount.isEmpty, let from = code(unit) else { return nil }
        return (amount, from, to)
    }

    private static func code(_ s: String) -> String? {
        if let c = symbols[s] { return c }
        let u = s.uppercased()
        return codes.contains(u) ? u : nil
    }
}
