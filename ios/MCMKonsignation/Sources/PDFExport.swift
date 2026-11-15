import UIKit

/// Erstellt die Abgleich-Bestätigung als A4-PDF (Layout wie in der Web-Version).
enum PDFExport {
    struct Signature {
        let image: UIImage?
        let name: String
        let date: String
    }

    static func write(standort: String, result r: CompareResult, rows: [SollRow],
                      kunde: Signature, mcm: Signature) -> URL? {
        let datum = dstr(Date())
        let pageRect = CGRect(x: 0, y: 0, width: 595, height: 842)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)

        let black = UIColor.black
        let red = UIColor(red: 179 / 255, green: 38 / 255, blue: 30 / 255, alpha: 1)
        let orange = UIColor(red: 178 / 255, green: 106 / 255, blue: 0, alpha: 1)
        let grey = UIColor(white: 110 / 255, alpha: 1)
        let L: CGFloat = 15
        let pageBottom: CGFloat = 275
        let cols: [String: CGFloat] = ["art": 15, "cs": 62, "mhd": 100, "soll": 123, "ist": 136, "st": 150]

        // Status pro Soll-Position
        let missingById = Dictionary(uniqueKeysWithValues: r.fehlend.map { ($0.row.id, $0.missing) })
        let devIds = Set((r.art + r.charge + r.mhd).map { $0.soll.id })

        // Grund je Abweichung, z. B. "MHD Ist 31.12.2030", für die Zeile im PDF
        var reasons: [UUID: [String]] = [:]
        for m in r.art { reasons[m.soll.id, default: []].append("Artikel Ist \(m.scan.ref ?? "–")") }
        for m in r.charge { reasons[m.soll.id, default: []].append("Charge Ist \(m.scan.lot ?? "–")") }
        for m in r.mhd { reasons[m.soll.id, default: []].append("MHD Ist \(dstr(m.scan.exp))") }

        let data = renderer.pdfData { ctx in
            // Umrechnung mm → Punkte (A4 = 210 × 297 mm)
            func mm(_ v: CGFloat) -> CGFloat { v * 72 / 25.4 }

            // y ist die Grundlinie der Schrift (wie in der Web-Version)
            func text(_ s: String, _ x: CGFloat, _ y: CGFloat, size: CGFloat = 8,
                      bold: Bool = false, color: UIColor = UIColor.black) {
                let font = bold ? UIFont.boldSystemFont(ofSize: size) : UIFont.systemFont(ofSize: size)
                (s as NSString).draw(at: CGPoint(x: mm(x), y: mm(y) - font.ascender),
                                     withAttributes: [.font: font, .foregroundColor: color])
            }

            func line(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat) {
                let c = ctx.cgContext
                c.setStrokeColor(black.cgColor)
                c.setLineWidth(0.3)
                c.move(to: CGPoint(x: mm(x1), y: mm(y1)))
                c.addLine(to: CGPoint(x: mm(x2), y: mm(y2)))
                c.strokePath()
            }

            var y: CGFloat = 16

            // MCM-Schaublin-Logo oben rechts auf jeder Seite
            let logo: UIImage? = Bundle.main.url(forResource: "mcm_logo", withExtension: "png")
                .flatMap { UIImage(contentsOfFile: $0.path) }

            func header() {
                text("Konsignationsabgleich · \(standort) · \(datum)", L, 8, size: 8, color: grey)
                if let logo {
                    let w = mm(56), h = mm(56) * logo.size.height / logo.size.width
                    logo.draw(in: CGRect(x: mm(210 - 15 - 56), y: mm(3), width: w, height: h))
                }
                y = 27   // Platz für das Logo oben rechts
            }

            func newPage() {
                ctx.beginPage()
                header()
            }

            func tableHead() {
                text("Artikel", cols["art"]!, y, bold: true)
                text("Serie / Charge", cols["cs"]!, y, bold: true)
                text("MHD", cols["mhd"]!, y, bold: true)
                text("Soll", cols["soll"]!, y, bold: true)
                text("Ist", cols["ist"]!, y, bold: true)
                text("Status", cols["st"]!, y, bold: true)
                y += 1.5
                line(L, y, 195, y)
                y += 3.5
            }

            newPage()

            // Kopf
            text("Konsignationsabgleich – Bestätigung", L, y, size: 15, bold: true)
            y += 8
            text("Standort: \(standort)", L, y, size: 10)
            y += 5
            text("Datum: \(datum)", L, y, size: 10)
            y += 5
            let missingCount = missingById.count
            text("Soll-Positionen: \(rows.count) · fehlend: \(missingCount) · abweichend: \(devIds.count) · zusätzlich gescannt: \(r.zus.count)",
                 L, y, size: 10)
            y += 9

            tableHead()

            for row in rows {
                let missing = missingById[row.id] ?? 0
                let isDev = devIds.contains(row.id)
                let status = missing > 0 ? "FEHLT" : (isDev ? "ABWEICHUNG" : "vorhanden")
                let color = missing > 0 ? red : (isDev ? orange : black)
                var cs = row.charge ?? "–"
                if let sn = row.sn {
                    cs = sn + (row.charge.map { " / " + $0 } ?? "")
                }

                if y + 9 > pageBottom {
                    newPage()
                    tableHead()
                }

                text(row.art, cols["art"]!, y, bold: true, color: color)
                text(cs, cols["cs"]!, y, color: color)
                text(row.mhd.isEmpty ? "–" : row.mhd, cols["mhd"]!, y, color: color)
                text("\(row.qty)", cols["soll"]!, y, color: color)
                text("\(row.qty - missing)", cols["ist"]!, y, color: color)
                text(status, cols["st"]!, y, bold: true, color: color)
                y += 4
                let why = isDev ? (reasons[row.id] ?? []) : []
                let bezText = String(row.bez.prefix(why.isEmpty ? 80 : 60))
                    + (why.isEmpty ? "" : "  →  " + why.joined(separator: ", "))
                text(bezText, cols["art"]!, y, size: 7, color: color)
                y += 4.5
            }

            if !r.zus.isEmpty {
                if y + 12 > pageBottom {
                    newPage()
                    tableHead()
                }
                y += 4
                text("Zusätzlich gescannt (nicht auf der Liste)", L, y, bold: true, color: orange)
                y += 5
                for sc in r.zus {
                    if y + 5 > pageBottom {
                        newPage()
                    }
                    let exp = sc.exp.map { dstr($0) } ?? "–"
                    text("\(sc.ref ?? "unbekannt")   SN \(sc.sn ?? "–")   Charge \(sc.lot ?? "–")   MHD \(exp)",
                         L, y)
                    y += 4.5
                }
            }

            // Unterschriften
            if y + 70 > pageBottom {
                newPage()
            }
            y += 10
            text("Der Bestand wurde gemeinsam geprüft. Abweichungen sind oben vermerkt.", L, y, size: 9)
            y += 14

            func signature(_ x0: CGFloat, _ title: String, _ sig: Signature) {
                text(title, x0, y, size: 9, bold: true)
                if let img = sig.image {
                    img.draw(in: CGRect(x: mm(x0), y: mm(y + 3), width: mm(70), height: mm(20)))
                }
                line(x0, y + 25, x0 + 80, y + 25)
                text("Unterschrift", x0, y + 29, size: 7, color: grey)
                if !sig.name.isEmpty {
                    text(sig.name, x0 + 1, y + 35, size: 9)
                }
                line(x0, y + 37, x0 + 80, y + 37)
                text("Name", x0, y + 41, size: 7, color: grey)
                if !sig.date.isEmpty {
                    text(sig.date, x0 + 1, y + 47, size: 9)
                }
                line(x0, y + 49, x0 + 40, y + 49)
                text("Datum", x0, y + 53, size: 7, color: grey)
            }

            signature(L, "Kunde", kunde)
            signature(110, "MCM Schaublin AG", mcm)
        }

        let safe = standort.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .prefix(4)
            .joined(separator: "_")
        let fileName = "Konsignationsabgleich_\(safe.isEmpty ? "Liste" : safe)_\(datum.replacingOccurrences(of: ".", with: "-")).pdf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        do {
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }
}
