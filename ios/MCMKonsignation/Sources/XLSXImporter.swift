import Foundation
import Compression

enum XLSXError: LocalizedError {
    case invalid
    case noHeader

    var errorDescription: String? {
        switch self {
        case .invalid: return "Die Excel-Datei konnte nicht gelesen werden."
        case .noHeader: return "In der Excel-Datei fehlt die Kopfzeile mit „Artikel Nr“ oder „Artikel“."
        }
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

/// Minimales ZIP-Lesen für .xlsx-Dateien (ohne zusätzliche Bibliothek).
struct ZipArchive {
    private let b: [UInt8]
    private var index: [String: (method: Int, csize: Int, usize: Int, loff: Int)] = [:]

    init(data: Data) throws {
        b = [UInt8](data)
        guard b.count > 22 else { throw XLSXError.invalid }
        // Zentrales Verzeichnis über den End-of-Central-Directory-Datensatz finden
        var e = b.count - 22
        while e >= 0 && u32(e) != 0x06054b50 { e -= 1 }
        guard e >= 0 else { throw XLSXError.invalid }
        let count = u16(e + 10)
        var p = u32(e + 16)
        for _ in 0..<count {
            guard p + 46 <= b.count, u32(p) == 0x02014b50 else { break }
            let method = u16(p + 10)
            let csize = u32(p + 20)
            let usize = u32(p + 24)
            let nlen = u16(p + 28)
            let elen = u16(p + 30)
            let clen = u16(p + 32)
            let loff = u32(p + 42)
            let name = String(decoding: b[(p + 46)..<(p + 46 + nlen)], as: UTF8.self)
            index[name] = (method, csize, usize, loff)
            p += 46 + nlen + elen + clen
        }
    }

    private func u16(_ o: Int) -> Int {
        Int(b[o]) | Int(b[o + 1]) << 8
    }

    private func u32(_ o: Int) -> Int {
        Int(b[o]) | Int(b[o + 1]) << 8 | Int(b[o + 2]) << 16 | Int(b[o + 3]) << 24
    }

    func read(_ name: String) throws -> Data {
        guard let ent = index[name] else { throw XLSXError.invalid }
        let lp = ent.loff
        let start = lp + 30 + u16(lp + 26) + u16(lp + 28)
        guard start + ent.csize <= b.count else { throw XLSXError.invalid }
        let raw = Array(b[start..<(start + ent.csize)])
        if ent.method == 0 { return Data(raw) }
        guard ent.method == 8 else { throw XLSXError.invalid }
        var dst = [UInt8](repeating: 0, count: max(ent.usize, 1))
        let n = compression_decode_buffer(&dst, dst.count, raw, raw.count, nil, COMPRESSION_ZLIB)
        guard n > 0 else { throw XLSXError.invalid }
        return Data(dst[0..<n])
    }
}

/// Liest die gemeinsamen Zeichenketten (sharedStrings.xml).
final class SharedStringsParser: NSObject, XMLParserDelegate {
    var strings: [String] = []
    private var current = ""
    private var inT = false

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String]) {
        if elementName == "si" { current = "" }
        if elementName == "t" { inT = true }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inT { current += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "t" { inT = false }
        if elementName == "si" { strings.append(current) }
    }
}

/// Liest die Zellen eines Tabellenblatts als Zuordnung "A4" → Wert.
final class SheetParser: NSObject, XMLParserDelegate {
    let shared: [String]
    var cells: [String: String] = [:]
    private var ref = ""
    private var type = ""
    private var text = ""
    private var inValue = false

    init(shared: [String]) {
        self.shared = shared
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String]) {
        switch elementName {
        case "c":
            ref = attributeDict["r"] ?? ""
            type = attributeDict["t"] ?? ""
            text = ""
        case "v", "t":
            inValue = true
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inValue { text += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        switch elementName {
        case "v", "t":
            inValue = false
        case "c":
            guard !ref.isEmpty else { return }
            let value: String
            if type == "s", let idx = Int(text), idx < shared.count {
                value = shared[idx]
            } else {
                value = text
            }
            cells[ref] = value
        default:
            break
        }
    }
}

/// Liest eine Soll-Liste im Excel-Format. Unterstützt die Testliste (Artikel, Bezeichnung, Menge)
/// und die SelectLine-Ergebnismengen (Artikel Nr, Verfallsdatum, Charge, Bezeichnung, Bestand).
enum XLSXImporter {
    static func load(url: URL) throws -> (standort: String, rows: [SollRow]) {
        let data = try Data(contentsOf: url)
        let zip = try ZipArchive(data: data)

        let ssParser = SharedStringsParser()
        if let ssData = try? zip.read("xl/sharedStrings.xml") {
            let p = XMLParser(data: ssData)
            p.delegate = ssParser
            p.parse()
        }

        let sheetParser = SheetParser(shared: ssParser.strings)
        let sheetData = try zip.read("xl/worksheets/sheet1.xml")
        let p2 = XMLParser(data: sheetData)
        p2.delegate = sheetParser
        p2.parse()
        let cells = sheetParser.cells

        // "B24" → Spalte "B", Zeile 24
        func split(_ ref: String) -> (col: String, row: Int) {
            let col = String(ref.prefix { $0.isLetter })
            return (col, Int(ref.dropFirst(col.count)) ?? 0)
        }

        // Kopfzeile: die Zeile mit „Artikel Nr“ oder „Artikel“
        var headerRow = 0
        for (ref, value) in cells {
            let v = value.trimmed
            if v == "Artikel Nr" || v == "Artikel" {
                headerRow = split(ref).row
            }
        }
        guard headerRow > 0 else { throw XLSXError.noHeader }

        var headers: [String: String] = [:]   // Überschrift → Spaltenbuchstabe
        for (ref, value) in cells {
            let (c, r) = split(ref)
            if r == headerRow { headers[value.trimmed] = c }
        }
        guard let artCol = headers["Artikel Nr"] ?? headers["Artikel"],
              let qtyCol = headers["Bestand"] ?? headers["Menge"] else {
            throw XLSXError.noHeader
        }
        let bezCol = headers["Bezeichnung"]
        let mhdCol = headers["Verfallsdatum"]
        let chargeCol = headers["Charge"]

        // Standort: Textblöcke über der Kopfzeile in der Artikelspalte.
        // Der MCM-Absender wird übersprungen, Zahlen (z. B. Exportdatum) ebenfalls.
        let above = cells.compactMap { (ref, value) -> (row: Int, text: String)? in
            let (c, r) = split(ref)
            guard c == artCol, r < headerRow else { return nil }
            let v = value.trimmed
            guard !v.isEmpty, Double(v) == nil else { return nil }
            return (r, v)
        }.sorted { $0.row < $1.row }

        var blocks: [[String]] = []
        var lastRow = -10
        for item in above {
            if item.row == lastRow + 1 {
                blocks[blocks.count - 1].append(item.text)
            } else {
                blocks.append([item.text])
            }
            lastRow = item.row
        }
        let candidates = blocks.filter { !($0.first ?? "").hasPrefix("MCM Schaublin") }
        let chosen = candidates.first { ($0.first ?? "").hasPrefix("Inventarliste") } ?? candidates.last ?? []
        let standort = chosen.joined(separator: " · ")
            .replacingOccurrences(of: #"^Inventarliste,?\s*"#, with: "", options: .regularExpression)

        // Datenzeilen: alle Zeilen unter der Kopfzeile mit Artikel und numerischer Menge
        var dataRows = Set<Int>()
        for ref in cells.keys {
            let (c, r) = split(ref)
            if c == artCol && r > headerRow { dataRows.insert(r) }
        }

        var rows: [SollRow] = []
        for r in dataRows.sorted() {
            let art = (cells["\(artCol)\(r)"] ?? "").trimmed
            guard !art.isEmpty, let qtyText = cells["\(qtyCol)\(r)"], let qty = Double(qtyText) else { continue }
            let bez = bezCol.flatMap { cells["\($0)\(r)"] }?.trimmed ?? ""

            var sn: String? = nil
            var charge: String? = nil
            if let cc = chargeCol, let raw = cells["\(cc)\(r)"]?.trimmed, !raw.isEmpty {
                (sn, charge) = splitCharge(raw)
            }

            var mhd = ""
            if let mc = mhdCol, let s = cells["\(mc)\(r)"], let serial = Double(s) {
                mhd = dstr(excelDate(serial))
            }

            rows.append(SollRow(standort: standort, art: art, bez: bez, sn: sn, charge: charge,
                                qty: Int(qty), mhd: mhd))
        }
        return (standort, rows)
    }

    /// „1635942688 / 25J11“ → SN und Charge. Eine 10-stellige Zahl ist eine Seriennummer, sonst Charge.
    private static func splitCharge(_ raw: String) -> (String?, String?) {
        if raw.contains("/") {
            let parts = raw.split(separator: "/").map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2 {
                return (parts[0].isEmpty ? nil : parts[0], parts[1].isEmpty ? nil : parts[1])
            }
        }
        if raw.count == 10 && raw.allSatisfy({ $0.isNumber }) {
            return (raw, nil)
        }
        return (nil, raw)
    }

    /// Excel speichert Datum als Anzahl Tage seit 30.12.1899.
    private static func excelDate(_ serial: Double) -> Date {
        Date(timeIntervalSince1970: (serial - 25569) * 86400)
    }
}
