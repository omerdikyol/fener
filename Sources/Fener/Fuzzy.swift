import Foundation

/// Fuzzy subsequence matcher. Every query character must appear in order in the candidate.
/// Matches at word starts and runs of consecutive characters score higher; gaps cost a little.
/// Returns nil when the query is not a subsequence.
enum Fuzzy {
    static let maxLength = 128

    /// Lowercases, strips diacritics, and maps Turkish dotless ı to i, one Character at a time
    /// so indexes into the folded and original strings stay aligned.
    static func fold(_ s: String) -> [Character] {
        s.map { c in
            if c == "ı" || c == "I" || c == "İ" { return "i" }
            return String(c).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).first ?? c
        }
    }

    static func score(_ query: String, _ candidate: String) -> Int? {
        let o = Array(candidate.prefix(maxLength))
        return score(fold(query).filter { $0 != " " }, folded: fold(String(o)), original: o)
    }

    /// `q` and `c` already folded; `original` is `c` before folding (same length), used for word starts.
    static func score(_ q: [Character], folded c: [Character], original: [Character]) -> Int? {
        let n = c.count, m = q.count
        guard m > 0 else { return 0 }
        guard m <= n else { return nil }

        func bonus(_ j: Int) -> Int {
            if j == 0 { return 10 }
            let prev = original[j - 1]
            if " -_./()".contains(prev) { return 8 }
            if prev.isLowercase && original[j].isUppercase { return 7 }  // camelCase
            return 0
        }

        let none = Int.min / 2
        // best[j]: best score for the query prefix so far with its last char matched at c[j];
        // chunk[j]: bonus of the first char of the consecutive run ending at j. A run that
        // starts at a word boundary keeps that bonus for every char ("Term" in "Terminal").
        var best = [Int](repeating: none, count: n), chunk = [Int](repeating: 0, count: n)
        for j in 0..<n where c[j] == q[0] {
            best[j] = 16 + bonus(j) - (bonus(j) > 0 ? 0 : min(j, 6))  // late mid-word start costs a little
            chunk[j] = bonus(j)
        }
        for i in 1..<m {
            var next = [Int](repeating: none, count: n), nextChunk = [Int](repeating: 0, count: n)
            var gapped = none  // max over k < j-1 of best[k] - (j-k-1), kept incrementally
            for j in 1..<n {
                if j >= 2, best[j - 2] > none { gapped = max(gapped, best[j - 2]) }
                gapped = gapped > none ? gapped - 1 : none   // one more skipped char
                guard c[j] == q[i] else { continue }
                if gapped > none { next[j] = gapped + 16 + bonus(j); nextChunk[j] = bonus(j) }
                if best[j - 1] > none {
                    let b = max(bonus(j), chunk[j - 1], 4)
                    if best[j - 1] + 16 + b > next[j] { next[j] = best[j - 1] + 16 + b; nextChunk[j] = b }
                }
            }
            best = next; chunk = nextChunk
        }
        guard var top = best.max(), top > none else { return nil }
        // Acronym bonus: every query char can be taken from word initials ("vsc" -> Visual Studio Code).
        var k = 0
        for j in 0..<n where k < m && bonus(j) > 0 && c[j] == q[k] { k += 1 }
        if k == m { top += 20 }
        return top - (n - m) / 4  // prefer shorter candidates slightly
    }
}
