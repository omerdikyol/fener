import AppKit

func calcItem(_ a: Calc.Answer, icon: String = "nf-md-calculator") -> Item {
    Item(id: "calc", title: a.value, subtitle: a.detail + "  ·  ⏎ copies", icon: sf(icon),
         run: { Clipboard.copyText(a.value) }, score: 10_000)
}

let rates = Currency(cacheDir: cacheDir)

/// "100 usd to try" with ECB rates; fetches them (at most daily) only when asked.
func currencyItem(_ s: String) -> Item? {
    guard config.currencyEnabled, let q = Currency.query(s.lowercased()), let amount = Calc.evaluate(q.amount) else { return nil }
    rates.refreshIfStale()
    guard let v = rates.convert(amount, from: q.from, to: q.to) else {
        return Item(id: "calc", title: rates.rates.isEmpty ? "Fetching exchange rates…" : "No rate for \(q.from) or \(q.to)",
                    subtitle: "ECB reference rates", icon: sf("nf-md-cash_multiple"), score: 10_000)
    }
    let value = abs(v) >= 1 ? String(format: "%.2f", v) : String(format: "%.4g", v)
    return calcItem(Calc.Answer(value: value, detail: "\(Calc.format(amount)) \(q.from) → \(q.to) · ECB \(rates.date)"),
                    icon: "nf-md-cash_multiple")
}

/// Calculator, currency, then time and dates: the first that understands the input.
func answerItem(_ s: String, forced: Bool) -> Item? {
    if let a = Calc.answer(s, forced: forced) { return calcItem(a) }
    if let c = currencyItem(s) { return c }
    if let a = TimeCalc.answer(s) { return calcItem(a, icon: "nf-md-calendar_clock") }
    return nil
}

var quicklinks = Quicklinks()

func linkItem(_ link: Quicklink, _ q: String, score: Int) -> Item {
    Item(id: "link:" + link.keyword, title: q.isEmpty ? link.name : "Search \(link.name) for “\(q)”",
         subtitle: q.isEmpty ? "\(link.keyword) <query>" : link.keyword, icon: sf(link.icon),
         run: { if let u = link.url(for: q) { NSWorkspace.shared.open(u) } }, score: score,
         actions: { link.url(for: q).map { Act.url($0.absoluteString) } ?? [] })
}
