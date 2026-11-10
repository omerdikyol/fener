import Foundation

/// Time zones and date arithmetic, offline (the OS time zone database):
///   time in tokyo        tokyo time           15:00 istanbul to london     3pm in new york
///   days until dec 31    days since 2026-01-01
///   today + 30 days      tomorrow - 2 weeks   2026-12-24 + 1 month
enum TimeCalc {
    /// Common names that are not the last part of a tz identifier.
    static let aliases: [String: String] = [
        "nyc": "America/New_York", "sf": "America/Los_Angeles", "san francisco": "America/Los_Angeles",
        "la": "America/Los_Angeles", "seattle": "America/Los_Angeles", "boston": "America/New_York",
        "washington": "America/New_York", "beijing": "Asia/Shanghai", "delhi": "Asia/Kolkata",
        "mumbai": "Asia/Kolkata", "bangalore": "Asia/Kolkata", "ankara": "Europe/Istanbul", "izmir": "Europe/Istanbul",
        "turkey": "Europe/Istanbul", "türkiye": "Europe/Istanbul", "japan": "Asia/Tokyo", "germany": "Europe/Berlin",
        "uk": "Europe/London", "england": "Europe/London", "france": "Europe/Paris", "netherlands": "Europe/Amsterdam",
    ]

    static func zone(_ place: String, local: TimeZone) -> (TimeZone, String)? {
        let p = place.trimmingCharacters(in: .whitespaces).lowercased()
        guard !p.isEmpty else { return nil }
        if p == "here" || p == "local" { return (local, "here") }
        if let id = aliases[p], let tz = TimeZone(identifier: id) { return (tz, p.capitalized) }
        if p.count <= 5, p.allSatisfy(\.isLetter), let tz = TimeZone(abbreviation: p.uppercased()) { return (tz, p.uppercased()) }
        let key = p.replacingOccurrences(of: " ", with: "_")
        for id in TimeZone.knownTimeZoneIdentifiers where id.split(separator: "/").last?.lowercased() == key {
            if let tz = TimeZone(identifier: id) { return (tz, id.split(separator: "/").last!.replacingOccurrences(of: "_", with: " ")) }
        }
        return nil
    }

    static func answer(_ raw: String, now: Date = Date(), local: TimeZone = .current) -> Calc.Answer? {
        let s = raw.trimmingCharacters(in: .whitespaces).lowercased().replacingOccurrences(of: "  ", with: " ")

        // time in <place> / <place> time / now in <place>
        for prefix in ["time in ", "now in "] where s.hasPrefix(prefix) {
            if let (tz, name) = zone(String(s.dropFirst(prefix.count)), local: local) { return timeAnswer(now, tz, name, local) }
        }
        if s.hasSuffix(" time"), let (tz, name) = zone(String(s.dropLast(5)), local: local) { return timeAnswer(now, tz, name, local) }

        // <time> [<from place>] (to|in) <to place>
        if let m = s.firstMatch(of: #/^(\d{1,2})(?::(\d{2}))?\s*(am|pm)?\s*(.*?)\s+(?:to|in)\s+(.+)$/#) {
            var h = Int(m.1)!, mi = m.2.flatMap { Int($0) } ?? 0
            if let ap = m.3 { guard (1...12).contains(h) else { return nil }; h = h % 12 + (ap == "pm" ? 12 : 0) }
            guard m.2 != nil || m.3 != nil, (0...23).contains(h), (0...59).contains(mi) else { return nil }  // "15 to x" is not a time
            let fromText = String(m.4)
            guard let (to, toName) = zone(String(m.5), local: local) else { return nil }
            let from: (TimeZone, String)
            if fromText.isEmpty { from = (local, "here") } else { guard let f = zone(fromText, local: local) else { return nil }; from = f }
            var cal = Calendar(identifier: .gregorian); cal.timeZone = from.0
            guard let at = cal.date(bySettingHour: h, minute: mi, second: 0, of: now) else { return nil }
            let a = timeAnswer(at, to, toName, local)
            return Calc.Answer(value: a.value, detail: String(format: "%02d:%02d %@ → %@", h, mi, from.1, a.detail))
        }

        // days until / since <date>
        for (prefix, sign) in [("days until ", 1), ("days to ", 1), ("days till ", 1), ("days since ", -1)] where s.hasPrefix(prefix) {
            guard let d = date(String(s.dropFirst(prefix.count)), now: now, local: local, future: sign > 0) else { return nil }
            var cal = Calendar(identifier: .gregorian); cal.timeZone = local
            let days = cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: d)).day! * sign
            return Calc.Answer(value: "\(days) day\(abs(days) == 1 ? "" : "s")", detail: "\(prefix.dropLast()) \(format(d, local))")
        }

        // <date> ± N unit
        if let m = s.firstMatch(of: #/^(.+?)\s*([+-])\s*(\d+)\s*(days?|d|weeks?|w|months?|years?|y)$/#),
           let base = date(String(m.1), now: now, local: local, future: false) {
            var cal = Calendar(identifier: .gregorian); cal.timeZone = local
            let n = Int(m.3)! * (m.2 == "-" ? -1 : 1), u = String(m.4)
            let comp: Calendar.Component = u.hasPrefix("w") ? .weekOfYear : u.hasPrefix("mo") ? .month : u.hasPrefix("y") ? .year : .day
            guard let d = cal.date(byAdding: comp, value: n, to: base) else { return nil }
            return Calc.Answer(value: format(d, local), detail: "\(m.1) \(m.2) \(m.3) \(u)")
        }
        return nil
    }

    private static func timeAnswer(_ at: Date, _ tz: TimeZone, _ name: String, _ local: TimeZone) -> Calc.Answer {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = tz
        f.dateFormat = "HH:mm"
        let time = f.string(from: at)
        f.dateFormat = "EEE d MMM"
        let diff = (tz.secondsFromGMT(for: at) - local.secondsFromGMT(for: at)) / 60
        let rel = diff == 0 ? "same as here" : String(format: "%@%d:%02d from here", diff > 0 ? "+" : "-", abs(diff) / 60, abs(diff) % 60)
        return Calc.Answer(value: time, detail: "\(name) · \(f.string(from: at)) · \(rel)")
    }

    static func format(_ d: Date, _ tz: TimeZone) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = tz
        f.dateFormat = "EEE d MMM yyyy"
        return f.string(from: d)
    }

    /// today, tomorrow, yesterday, now, 2026-12-31, dec 31, 31 dec, december 31 2027.
    /// Without a year, the next occurrence when `future`, otherwise this year.
    static func date(_ text: String, now: Date, local: TimeZone, future: Bool) -> Date? {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = local
        let t = text.trimmingCharacters(in: .whitespaces)
        switch t {
        case "today", "now": return now
        case "tomorrow": return cal.date(byAdding: .day, value: 1, to: now)
        case "yesterday": return cal.date(byAdding: .day, value: -1, to: now)
        default: break
        }
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = local
        f.isLenient = false
        for fmt in ["yyyy-MM-dd", "d MMM yyyy", "MMM d yyyy", "d MMMM yyyy", "MMMM d yyyy", "MMM d, yyyy", "MMMM d, yyyy"] {
            f.dateFormat = fmt
            if let d = f.date(from: t) { return d }
        }
        let year = cal.component(.year, from: now)
        for fmt in ["d MMM", "MMM d", "d MMMM", "MMMM d"] {
            f.dateFormat = fmt + " yyyy"
            guard var d = f.date(from: "\(t) \(year)") else { continue }
            if future, cal.startOfDay(for: d) < cal.startOfDay(for: now) { d = cal.date(byAdding: .year, value: 1, to: d)! }
            return d
        }
        return nil
    }
}
