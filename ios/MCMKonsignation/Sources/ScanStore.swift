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
    let at = Date()          // Zeitpunkt des Scans (wird nicht im Initialisierer gesetzt)
}

/// Hält den gerade laufenden Ton. Wird nur auf der toneQueue benutzt.
private final class TonePlayerBox: @unchecked Sendable {
    var player: AVAudioPlayer?
}

/// Töne werden auf einer eigenen Queue geladen und abgespielt, nicht auf dem Hauptthread (Xcode-Hinweis „AVAudioSession Hang Risk“).
private let toneQueue = DispatchQueue(label: "ch.mcmschaublin.mcmkonsignation.audio")
private let toneBox = TonePlayerBox()

/// Sammelt die gescannten Codes in der Reihenfolge des Scans.
@MainActor
final class ScanStore: ObservableObject {
    @Published private(set) var records: [ScanRecord] = []
    @Published var notice: String?

    private var lastRaw = ""
    private var lastAt = Date.distantPast
    private var lastPlainGtin: String?
    private var lastPlainAt = Date.distantPast
    private var pendingSn: (sn: String, at: Date)?

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

        // Seriennummer-Code (unterer Strichcode, nur (17)(21), ohne Artikel): gehört zum Artikelcode davor oder danach
        if !manual, gtin == nil, star == nil, let snOnly = p["21"] {
            if let last = records.last, last.sn == snOnly {
                notice = "Wiederholung, nicht gezählt."
                return
            }
            if let last = records.last, last.gtin != nil, last.sn == nil, Date().timeIntervalSince(last.at) < 5 {
                records[records.count - 1] = ScanRecord(
                    raw: last.raw, gtin: last.gtin, ref: last.ref, name: last.name,
                    sn: snOnly, lot: last.lot ?? p["10"], exp: last.exp ?? parseYYMMDD(p["17"] ?? ""),
                    known: last.known)
                notice = nil
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                playTone("scan_ok")
                return
            }
            pendingSn = (sn: snOnly, at: Date())
            notice = "Seriennummer erkannt. Jetzt den oberen Artikelcode scannen."
            return
        }

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
        if gtin == nil && star == nil && sn == nil && lot == nil { sn = raw }
        // Seriennummer, die vorher allein gelesen wurde (unterer Code zuerst): diesem Artikelcode zuordnen
        if sn == nil, gtin != nil, let pend = pendingSn, Date().timeIntervalSince(pend.at) < 5 {
            sn = pend.sn
            pendingSn = nil
        }   // Klartext: Seriennummer

        let ref: String? = info.map { normRef($0.ref) } ?? star.map { normRef($0[2]) }

        // Zweiter Code desselben Stücks (Perceval: Strichcode und QR mit gleicher SN): nicht als Doppel zählen
        if let sn, records.contains(where: { $0.sn == sn && $0.ref == ref && $0.raw != raw }) {
            notice = "Zweiter Code desselben Stücks, nicht gezählt."
            return
        }

        // Derselbe Artikelcode ohne SN innerhalb von 3 s: derselbe Code, nur anders gelesen
        let plain = gtin != nil && p["21"] == nil
        if !manual, plain, gtin == lastPlainGtin, Date().timeIntervalSince(lastPlainAt) < 3 {
            notice = "Wiederholung, nicht gezählt."
            return
        }
        if plain { lastPlainGtin = gtin; lastPlainAt = Date() }

        // Bicarbon/Slimline: Der obere Strichcode nennt nur den Artikel, der untere die Seriennummer.
        // Direkt aufeinanderfolgende Codes desselben Artikels mit und ohne SN bilden EIN Stück, die SN-Version gilt.
        if let last = records.last, let g = gtin, last.gtin == g, last.ref == ref, (last.sn != nil) != (sn != nil) {
            if sn != nil {
                records.removeLast()          // erst Artikelcode, dann SN-Code: Artikelcode ersetzen
            } else {
                notice = "Artikelcode desselben Stücks, nicht gezählt."
                return                        // erst SN-Code, dann Artikelcode: ignorieren
            }
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
        toneQueue.async {
            guard let url = Bundle.main.url(forResource: name, withExtension: "wav") else { return }
            let p = try? AVAudioPlayer(contentsOf: url)
            toneBox.player = p   // hält den Player, solange der Ton läuft
            p?.play()
        }
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
