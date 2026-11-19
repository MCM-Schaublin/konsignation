import SwiftUI
import AVFoundation

struct ScanRecord: Identifiable {
    let id = UUID()
    let raw: String
    let gtin: String?
    let ref: String?        // normalisierte Artikelkennung aus dem Katalog
    let name: String
    let sn: String?
    let lot: String?
    let exp: Date?
    let known: Bool
}

/// Sammelt die gescannten Codes in der Reihenfolge des Scans.
@MainActor
final class ScanStore: ObservableObject {
    @Published private(set) var records: [ScanRecord] = []
    @Published var notice: String?

    private var player: AVAudioPlayer?
    private var lastRaw = ""
    private var lastAt = Date.distantPast

    var lastRecord: ScanRecord? { records.last }

    func add(_ rawIn: String, manual: Bool = false) {
        let raw = rawIn.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }

        // Die Kamera liest denselben Code mehrfach. Gleicher Code innerhalb von 3 s zählt nur einmal.
        if !manual {
            let now = Date()
            let same = raw == lastRaw && now.timeIntervalSince(lastAt) < 3
            lastRaw = raw
            lastAt = now
            if same {
                notice = "Wiederholung, nicht gezählt. Zweiter Karton mit gleicher Charge? Dann „Letzten +1“ nutzen."
                playTone("scan_fehler")
                return
            }
        }

        let p = GS1.parse(raw)
        let gtin = p["01"].map { String(repeating: "0", count: max(0, 14 - $0.count)) + $0 }

        // Corcym-Etiketten (Data Matrix) haben kein GS1-Format, sondern „SERIENNUMMER*ARTIKEL“, z. B. „A98503*PVF-L“
        let star: [String]? = gtin == nil ? raw.firstMatch(#"^([0-9A-Za-z]{4,})\*([0-9A-Za-z][0-9A-Za-z\-/]*)$"#) : nil

        // Kamera-Fremdcodes ohne GTIN (z. B. EAN auf der Verpackung) werden nicht gezählt.
        if !manual && gtin == nil && star == nil {
            notice = "Kein GS1-Code, nicht gezählt."
            playTone("scan_fehler")
            return
        }

        let info = gtin.flatMap { Catalog.entries[$0] }
        // Steuerzeichen-Reste (z. B. „>“) gehören nicht zur Seriennummer oder Charge
        let clean: (String) -> String = { $0.filter { $0.isASCII && ($0.isLetter || $0.isNumber) } }
        var sn = (p["21"] ?? star?[1]).map(clean)
        let lot = p["10"].map(clean)
        if gtin == nil && star == nil && sn == nil && lot == nil { sn = raw }   // Klartext: Seriennummer

        let ref: String? = info.map { normRef($0.ref) } ?? star.map { normRef($0[2]) }

        // Zweiter Code desselben Stücks (Perceval: Strichcode und QR mit gleicher SN): nicht als Doppel zählen
        if let sn, records.contains(where: { $0.sn == sn && $0.ref == ref && $0.raw != raw }) {
            notice = "Zweiter Code desselben Stücks, nicht gezählt."
            return
        }

        let known = info != nil || star != nil
        let rec = ScanRecord(
            raw: raw, gtin: gtin,
            ref: ref,
            name: info?.name ?? star.map { $0[2] } ?? (gtin == nil ? "(kein GS1-Format)" : "(GTIN nicht in Katalog)"),
            sn: sn, lot: lot,
            exp: parseYYMMDD(p["17"] ?? ""),
            known: known)
        records.append(rec)

        if !known {
            notice = "Nicht im Katalog · GTIN \(gtin ?? "–")"
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            playTone("scan_fehler")
        } else {
            notice = nil
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            playTone("scan_ok")
        }
    }

    /// Kurzer Ton: „scan_ok“ bei erfolgreichem Scan, „scan_fehler“ bei Fehlschlag.
    private func playTone(_ name: String) {
        guard let url = Bundle.main.url(forResource: name, withExtension: "wav") else { return }
        player = try? AVAudioPlayer(contentsOf: url)
        player?.play()
    }

    func plusOneLast() {
        if let r = lastRecord { add(r.raw, manual: true) }
    }

    func remove(_ offsets: IndexSet) {
        records.remove(atOffsets: offsets)
    }

    func clear() {
        records.removeAll()
        notice = nil
        lastRaw = ""
    }
}
