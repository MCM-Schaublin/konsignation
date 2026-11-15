import Foundation

/// Artikelkennung ohne Präfix, wie in der Web-Version (normRef).
func normRef(_ r: String) -> String {
    r.replacingOccurrences(of: #"^(GET|IVAS)-"#, with: "", options: [.regularExpression, .caseInsensitive])
        .uppercased()
        .trimmingCharacters(in: .whitespaces)
}

/// Datum im Format TT.MM.JJJJ.
func parseDMY(_ s: String) -> Date? {
    guard let m = s.firstMatch(#"(\d{2})\.(\d{2})\.(\d{4})"#) else { return nil }
    var c = DateComponents()
    c.day = Int(m[1]); c.month = Int(m[2]); c.year = Int(m[3])
    return Calendar.current.date(from: c)
}

/// GS1-Ablaufdatum JJMMTT. Tag 00 bedeutet letzter Tag des Monats.
func parseYYMMDD(_ s: String) -> Date? {
    let chars = Array(s)
    guard chars.count == 6, chars.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
    guard let y = Int(String(chars[0..<2])), let mo = Int(String(chars[2..<4])), let d = Int(String(chars[4..<6])) else { return nil }
    let cal = Calendar.current
    var c = DateComponents()
    c.year = 2000 + y
    c.month = mo
    if d == 0 {
        guard let first = cal.date(from: DateComponents(year: 2000 + y, month: mo, day: 1)),
              let range = cal.range(of: .day, in: .month, for: first) else { return nil }
        c.day = range.count
    } else {
        c.day = d
    }
    return cal.date(from: c)
}

private let dateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "dd.MM.yyyy"
    return f
}()

func dstr(_ d: Date?) -> String {
    guard let d else { return "–" }
    return dateFormatter.string(from: d)
}

/// Zerlegt GS1-Codes in ihre Application Identifier (wie parseGS1Core in der Web-Version).
enum GS1 {
    static let fixed: [String: Int] = ["00": 18, "01": 14, "02": 14, "11": 6, "13": 6, "15": 6, "16": 6, "17": 6, "20": 2]
    static let bound: [String: Int] = ["01": 14, "11": 6, "13": 6, "15": 6, "16": 6, "17": 6]
    static let separators = CharacterSet(charactersIn: "\u{1D}\u{1E}\u{04}")

    static func parse(_ raw: String) -> [String: String] {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.range(of: #"\(\d{2,4}\)"#, options: .regularExpression) != nil {
            return parseParenthesized(s)
        }
        s = s.replacingOccurrences(of: #"^\][A-Za-z]\d"#, with: "", options: .regularExpression)
        let hasSep = s.unicodeScalars.contains { separators.contains($0) }
        let segments = hasSep ? s.components(separatedBy: separators) : [s]

        var out: [String: String] = [:]
        for seg in segments {
            let chars = Array(seg)
            var i = 0
            while i < chars.count {
                let a2 = String(chars[i..<min(i + 2, chars.count)])
                if let len = fixed[a2] {
                    if out[a2] == nil { out[a2] = slice(chars, i + 2, len) }
                    i += 2 + len
                } else if a2 == "10" || a2 == "21" {
                    let rest = Array(chars[min(i + 2, chars.count)...])
                    let end = hasSep ? rest.count : boundary(rest, a2)
                    if out[a2] == nil { out[a2] = String(rest[0..<end]) }
                    i += 2 + end
                } else {
                    break
                }
            }
        }
        return out
    }

    private static func parseParenthesized(_ s: String) -> [String: String] {
        var out: [String: String] = [:]
        guard let re = try? NSRegularExpression(pattern: #"\((\d{2,4})\)([^(]*)"#) else { return out }
        let ns = s as NSString
        for m in re.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            let k = ns.substring(with: m.range(at: 1))
            let v = ns.substring(with: m.range(at: 2))
                .components(separatedBy: separators).joined()
                .trimmingCharacters(in: .whitespaces)
            if out[k] == nil { out[k] = v }
        }
        return out
    }

    /// Feldgrenze ohne Trennzeichen. Eine Charge wie 2610552 darf nicht bei „10“ zerschnitten werden.
    private static func boundary(_ rest: [Character], _ cur: String) -> Int {
        let n = rest.count
        guard n >= 2 else { return n }
        for j in 1..<n {
            guard j + 2 <= n else { break }
            let t2 = String(rest[j..<(j + 2)])
            if cur == "21" && t2 == "10" && n - (j + 2) == 5 { return j }   // Getinge: SN + 10 + 5-stellige Charge
            guard let need = bound[t2] else { continue }
            let start = j + 2
            guard start + need <= n else { continue }
            if rest[start..<(start + need)].allSatisfy({ $0.isASCII && $0.isNumber }) { return j }
        }
        return n
    }

    private static func slice(_ c: [Character], _ start: Int, _ len: Int) -> String {
        let s = min(start, c.count), e = min(start + len, c.count)
        return String(c[s..<e])
    }
}
