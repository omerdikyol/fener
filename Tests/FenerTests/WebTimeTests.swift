import XCTest
@testable import fener

final class QuicklinkTests: XCTestCase {
    func testBuiltInsAndMatch() {
        let q = Quicklinks()
        XCTAssertEqual(q.defaultEngine?.name, "DuckDuckGo")
        XCTAssertEqual(q.match("g fener launcher")?.0.name, "Google")
        XCTAssertEqual(q.match("g fener launcher")?.1, "fener launcher")
        XCTAssertEqual(q.match("k")?.1, "")                    // bare keyword
        XCTAssertNil(q.match("ghostty"))                      // a word is not a keyword
        XCTAssertEqual(q.links.first { $0.keyword == "k" }?.url(for: "a b")?.absoluteString, "https://kagi.com/search?q=a%20b")
    }

    func testEncodingCannotBreakTheURL() {
        XCTAssertEqual(Quicklink.encode("c++ & you #1?"), "c%2B%2B%20%26%20you%20%231%3F")
        XCTAssertEqual(Quicklink.encode("İstanbul çay"), "%C4%B0stanbul%20%C3%A7ay")
    }

    func testUserFileOverridesAddsAndValidates() {
        var p: [String] = []
        let q = Quicklinks.parse("""
        default = "g"
        [[link]]
        keyword = "g"
        name = "Google TR"
        url = "https://www.google.com.tr/search?q={query}"
        [[link]]
        keyword = "eksi"
        name = "Ekşi"
        url = "https://eksisozluk.com/?q={query}"
        [[link]]
        keyword = "bad one"
        name = "x"
        url = "https://x"
        """, problems: &p)
        XCTAssertEqual(q.defaultEngine?.name, "Google TR")
        XCTAssertEqual(q.match("eksi swift")?.0.name, "Ekşi")
        XCTAssertEqual(q.links.filter { $0.keyword == "g" }.count, 1)
        XCTAssertEqual(p.count, 1)                            // the keyword with a space
    }
}

final class CurrencyTests: XCTestCase {
    let xml = """
    <gesmes:Envelope><Cube><Cube time='2026-11-10'>
    <Cube currency='USD' rate='1.08'/><Cube currency='TRY' rate='37.8'/><Cube currency='GBP' rate='0.84'/>
    </Cube></Cube></gesmes:Envelope>
    """

    func testParse() {
        let r = Currency.parse(Data(xml.utf8))
        XCTAssertEqual(r?.1, "2026-11-10")
        XCTAssertEqual(r?.0["USD"], 1.08)
        XCTAssertEqual(r?.0["EUR"], 1)
        XCTAssertNil(Currency.parse(Data("<html>error</html>".utf8)))
    }

    func testQueryForms() {
        XCTAssertEqual(Currency.query("100 usd to try")?.from, "USD")
        XCTAssertEqual(Currency.query("100usd in eur")?.amount, "100")
        XCTAssertEqual(Currency.query("€50 to try")?.from, "EUR")
        XCTAssertEqual(Currency.query("1,5 gbp = usd")?.amount, "1,5")
        XCTAssertNil(Currency.query("100 km to mi"))
        XCTAssertNil(Currency.query("usd to try"))            // no amount
    }

    func testConvert() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try xml.write(to: dir.appendingPathComponent("ecb-rates.xml"), atomically: true, encoding: .utf8)
        let c = Currency(cacheDir: dir)                       // loads the cached file, no network
        XCTAssertEqual(c.convert(108, from: "USD", to: "EUR")!, 100, accuracy: 1e-9)
        XCTAssertEqual(c.convert(10, from: "USD", to: "TRY")!, 350, accuracy: 1e-9)
        XCTAssertNil(c.convert(1, from: "USD", to: "JPY"))   // missing rate
    }
}

final class TimeCalcTests: XCTestCase {
    let ist = TimeZone(identifier: "Europe/Istanbul")!
    // 2026-11-10 12:00 in Istanbul (UTC+3) = 09:00 UTC
    var now: Date { ISO8601DateFormatter().date(from: "2026-11-10T09:00:00Z")! }
    func v(_ s: String) -> String? { TimeCalc.answer(s, now: now, local: ist)?.value }

    func testTimeInPlace() {
        XCTAssertEqual(v("time in tokyo"), "18:00")
        XCTAssertEqual(v("london time"), "09:00")
        XCTAssertEqual(v("time in utc"), "09:00")
        XCTAssertEqual(v("time in nyc"), "04:00")
        XCTAssertNil(v("time in atlantis"))
    }

    func testConvertTimes() {
        XCTAssertEqual(v("15:00 istanbul to london"), "12:00")
        XCTAssertEqual(v("3pm in tokyo"), "21:00")            // from here
        XCTAssertEqual(v("9am new york to istanbul"), "17:00")
        XCTAssertNil(v("15 to london"))                       // a bare number is not a time
        XCTAssertNil(v("13pm in tokyo"))
    }

    func testDates() {
        XCTAssertEqual(v("days until dec 31"), "51 days")
        XCTAssertEqual(v("days until 2026-11-11"), "1 day")
        XCTAssertEqual(v("days since 2026-01-01"), "313 days")
        XCTAssertEqual(v("today + 30 days"), "Thu 10 Dec 2026")
        XCTAssertEqual(v("tomorrow - 2 weeks"), "Wed 28 Oct 2026")
        XCTAssertEqual(v("2026-01-31 + 1 month"), "Sat 28 Feb 2026")
        XCTAssertEqual(v("days until jan 5"), "56 days")      // next year when already past
    }

    func testNotTimeLike() {
        XCTAssertNil(v("safari"))
        XCTAssertNil(v("time"))
        XCTAssertNil(v("10 km to mi"))
    }
}

final class SnippetDictionaryTests: XCTestCase {
    func testExpand() {
        let now = ISO8601DateFormatter().date(from: "2026-11-11T11:05:00Z")!
        let s = Snippets.expand("{date} {time:HH} {date:EEE d MMM} {clipboard} {uuid} {nope} {datetime:yyyy}",
                                now: now, clipboard: "clip", uuid: { "U-1" })
        let tz = TimeZone.current.secondsFromGMT(for: now)
        var cal = Calendar(identifier: .gregorian); cal.timeZone = .current
        let hour = String(format: "%02d", cal.component(.hour, from: now))
        XCTAssertEqual(s, "2026-11-11 \(hour) Wed 11 Nov clip U-1 {nope} 2026", "tz offset \(tz)")
        XCTAssertEqual(Snippets.expand("{clipboard}", clipboard: nil), "")
    }

    func testLoadFolder() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try "Teşekkürler,\nİyi günler".write(to: dir.appendingPathComponent("Signature.txt"), atomically: true, encoding: .utf8)
        try "x".write(to: dir.appendingPathComponent(".hidden"), atomically: true, encoding: .utf8)
        try "addr".write(to: dir.appendingPathComponent("address"), atomically: true, encoding: .utf8)
        XCTAssertEqual(Snippets(dir: dir).all.map(\.name), ["address", "Signature"])
        XCTAssertEqual(Snippets(dir: dir).all.last?.text, "Teşekkürler,\nİyi günler")
    }

    func testSenses() {
        let en = "launcher launch·er | ˈlôn(t)SHər | noun a structure that holds a rocket: a rocket launcher. • a rocket that is used to convey a satellite. ORIGIN 1880s."
        XCTAssertEqual(Definitions.senses(en), [
            "launcher launch·er | ˈlôn(t)SHər | noun a structure that holds a rocket: a rocket launcher.",
            "a rocket that is used to convey a satellite.", "ORIGIN 1880s."])
        let tr = "kitap a. Ar. 1 esk. basılı yapraklar. 2 basımevinde basılıp kapak geçirilmiş nesne. ör. Bu kitap yeni çıktı. 3 ciltli nesne."
        XCTAssertEqual(Definitions.senses(tr).count, 3)
        XCTAssertTrue(Definitions.senses(tr)[1].hasPrefix("2 basımevinde"))
    }

    func testHeader() {
        let h = Definitions.header("serendipity ser·en·dip·i·ty | ˌserənˈdipədē | noun the occurrence of events by chance")
        XCTAssertEqual(h.header, "serendipity ser·en·dip·i·ty | ˌserənˈdipədē | noun")
        XCTAssertEqual(h.sense, "the occurrence of events by chance")
        XCTAssertEqual(Definitions.header("kitap a. Ar. 1 esk. basılı yapraklar.").sense, "1 esk. basılı yapraklar.")
        XCTAssertEqual(Definitions.header("plain text").sense, "plain text")
        XCTAssertEqual(Definitions.header("l l | p | noun holds a rocket: a rocket launcher | a grenade launcher.").sense,
                       "holds a rocket: a rocket launcher | a grenade launcher.")  // examples also use "|"
        XCTAssertEqual(Definitions.header("w w\u{a0}|\u{a0}w\u{a0}|\u{a0}noun a sense").sense, "a sense")  // no-break spaces
    }

    func testSystemDictionaryWhenAvailable() throws {
        guard let d = Definitions.lookup("launcher") else { throw XCTSkip("no English dictionary enabled") }
        XCTAssertTrue(d.contains("rocket"))
        XCTAssertNil(Definitions.lookup("xyzzyqq"))
    }
}
