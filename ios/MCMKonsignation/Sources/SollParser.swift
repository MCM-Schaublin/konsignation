import Foundation

extension String {
    /// Erste Übereinstimmung mit Gruppen (Index 0 = ganzer Treffer). Groß-/Kleinschreibung egal.
    func firstMatch(_ pattern: String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let ns = self as NSString
        guard let m = re.firstMatch(in: self, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return (0..<m.numberOfRanges).map { i in
            let r = m.range(at: i)
            return r.location == NSNotFound ? "" : ns.substring(with: r)
        }
    }
}

/// Übernimmt die Regeln der Web-Version (parseSollText / parseTableLine).
enum SollParser {

    static func parse(_ text: String) -> (standort: String, rows: [SollRow]) {
        var rows: [SollRow] = []
        var cur: Int? = nil
        var standort = ""
        var curIsLN = false   // aktueller Block stammt aus dem Artikelbestand (LN-Format)

        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        for l in lines {
            // Tabellenformat: Artikel, Datum, Bezeichnung und Menge in einer Zeile
            if let tb = parseTableLine(l, standort: standort) {
                rows.append(tb)
                cur = rows.count - 1
                curIsLN = false
                continue
            }
            if standort.isEmpty, let m = l.firstMatch(#"Standort:\s*(.+)$"#) {
                standort = m[1].trimmingCharacters(in: .whitespaces)
                continue
            }
            // Blockformat: Artikelzeile, dann Serie/Charge, MHD, Bestand
            // LN-Zeilen stammen aus dem Artikelbestand: die interne LN-Kennung entfällt, Menge ist immer 1
            if let m = l.firstMatch(#"^(GET|IVAS|LN)-(\S+)\s*-\s*(.*)$"#) {
                rows.append(SollRow(standort: standort, art: artKey(m[1], m[2]), bez: m[3],
                                    sn: nil, charge: nil, qty: 1, mhd: ""))
                cur = rows.count - 1
                curIsLN = m[1].uppercased() == "LN"
                continue
            }
            guard let i = cur else { continue }
            if let m = l.firstMatch(#"^Bestand:\s*(\d+)"#) {
                if !curIsLN { rows[i].qty = Int(m[1]) ?? rows[i].qty }
            } else if let m = l.firstMatch(#"^Serie/Charge:\s*(.*)$"#) {
                applySerie(m[1], to: &rows[i])
            } else if let m = l.firstMatch(#"^MHD:\s*(.*)$"#) {
                rows[i].mhd = m[1].trimmingCharacters(in: .whitespaces)
            }
        }

        for i in rows.indices where rows[i].standort.isEmpty {
            rows[i].standort = standort
        }
        return (standort, rows)
    }

    private static func artKey(_ prefix: String, _ code: String) -> String {
        let p = prefix.uppercased()
        if p == "LN" { return code }   // interne Lieferanten-Kennung, für die Kontrolle nicht nötig
        // Bei GET-Artikeln wird ein O im Code als Null gelesen
        let c = p == "GET" ? code.replacingOccurrences(of: "O", with: "0") : code
        return p + "-" + c
    }

    private static func applySerie(_ raw: String, to r: inout SollRow) {
        let v = raw.replacingOccurrences(of: "/", with: "").replacingOccurrences(of: " ", with: "")
        if let m = v.firstMatch(#"^(\d{10})29010([0-9A-Za-z]{5})$"#) {
            r.sn = m[1]; r.charge = m[2]          // SN + 29010 + Charge
        } else if let m = v.firstMatch(#"^(\d{10})([0-9A-Za-z]{5})$"#) {
            r.sn = m[1]; r.charge = m[2]          // SN + Charge
        } else if let m = v.firstMatch(#"^(\d{10})$"#) {
            r.sn = m[1]                           // nur SN
        } else if let m = v.firstMatch(#"^(\d{7})$"#) {
            r.charge = m[1]                       // 7-stellige Charge
        } else {
            r.sn = v                              // unklar, wird unverändert übernommen
        }
    }

    private static func parseTableLine(_ l: String, standort: String) -> SollRow? {
        guard let m = l.firstMatch(#"^(GET|IVAS)-(\S+)\s+(\d{2}\.\d{2}\.\d{4})\s+(.+)$"#) else { return nil }
        var rest = m[4]
        var sn: String? = nil
        var charge: String? = nil
        var qty = 1

        if let c = rest.firstMatch(#"^(\d{10})\s*/\s*([0-9A-Za-z]{5})\s+(.*)$"#) {
            sn = c[1]; charge = c[2]; rest = c[3]
        } else if let c = rest.firstMatch(#"^(\d{10})29010([0-9A-Za-z]{5})\s+(.*)$"#) {
            sn = c[1]; charge = c[2]; rest = c[3]
        } else if let c = rest.firstMatch(#"^(\d{10})\s+(.*)$"#) {
            sn = c[1]; rest = c[2]
        } else if let c = rest.firstMatch(#"^(\d{7})\s+(.*)$"#) {
            charge = c[1]; rest = c[2]
        }

        if let q = rest.firstMatch(#"\s(\d+)\s*Stk\.?\s*$"#) {
            qty = Int(q[1]) ?? 1
            rest = rest.replacingOccurrences(of: #"\s\d+\s*Stk\.?\s*$"#, with: "", options: .regularExpression)
        }

        return SollRow(standort: standort, art: artKey(m[1], m[2]), bez: rest.trimmingCharacters(in: .whitespaces),
                       sn: sn, charge: charge, qty: qty, mhd: m[3])
    }
}
