import Foundation

/// Exportiert das Abgleichsergebnis als CSV. Trenner ist Semikolon, Datei ist UTF-8 mit BOM,
/// damit Excel Umlaute richtig anzeigt.
enum CSVExport {
    static func url(for r: CompareResult, standort: String) -> URL {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        let parts = standort.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .prefix(4)
        let base = parts.isEmpty ? "Liste" : parts.joined(separator: "_")
        let name = "Abgleich_\(base)_\(df.string(from: Date())).csv"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try? text(for: r).write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    static func text(for r: CompareResult) -> String {
        var lines = ["Status;Artikel;Bezeichnung;Serie/Charge;MHD;Soll;Ist;Hinweis"]
        func line(_ cols: [String]) {
            lines.append(cols.map(quote).joined(separator: ";"))
        }

        for m in r.fehlend {
            line(["FEHLT", m.row.art, m.row.bez, m.row.sn ?? m.row.charge ?? "", m.row.mhd,
                  "\(m.row.qty)", "\(m.row.qty - m.missing)", ""])
        }
        for m in r.art {
            line(["ABWEICHUNG", m.soll.art, m.soll.bez, m.soll.sn ?? m.soll.charge ?? "", m.soll.mhd,
                  "1", "1", "Artikel: Ist \(m.scan.ref ?? "–")"])
        }
        for m in r.charge {
            line(["ABWEICHUNG", m.soll.art, m.soll.bez, m.soll.sn ?? m.soll.charge ?? "", m.soll.mhd,
                  "1", "1", "Charge: Ist \(m.scan.lot ?? "–")"])
        }
        for m in r.mhd {
            line(["ABWEICHUNG", m.soll.art, m.soll.bez, m.soll.sn ?? m.soll.charge ?? "", m.soll.mhd,
                  "1", "1", "MHD: Ist \(dstr(m.scan.exp))"])
        }
        for sc in r.zus {
            line(["ZUSÄTZLICH", sc.ref ?? sc.raw, sc.name, sc.sn ?? sc.lot ?? "", dstr(sc.exp),
                  "0", "1", ""])
        }
        for sc in r.dopp {
            line(["DOPPELT", sc.ref ?? "", sc.name, sc.sn ?? "", dstr(sc.exp),
                  "", "", "SN \(sc.sn ?? "–") bereits gescannt"])
        }
        for item in r.abg {
            line(["ABGELAUFEN", "", item.title, "", "", "", "", item.detail])
        }

        return "\u{FEFF}" + lines.joined(separator: "\n") + "\n"
    }

    private static func quote(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
