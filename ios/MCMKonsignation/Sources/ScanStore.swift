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

        // Kamera-Fremdcodes ohne GTIN (z. B. EAN auf der Verpackung) werden nicht gezählt.
        if !manual && gtin == nil {
            notice = "Kein GS1-Code, nicht gezählt."
            playTone("scan_fehler")
            return
        }

        let info = gtin.flatMap { Catalog.entries[$0] }
        var sn = p["21"]
        let lot = p["10"]
        if gtin == nil && sn == nil && lot == nil { sn = raw }   // Klartext: Seriennummer

        let rec = ScanRecord(
            raw: raw, gtin: gtin,
            ref: info.map { normRef($0.ref) },
            name: info?.name ?? (gtin == nil ? "(kein GS1-Format)" : "(GTIN nicht in Katalog)"),
            sn: sn, lot: lot,
            exp: parseYYMMDD(p["17"] ?? ""),
            known: info != nil)
        records.append(rec)

        if info == nil {
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
