import SwiftUI

/// Eine Position der Soll-Liste (Konsignationsbestand beim Kunden).
struct SollRow: Identifiable {
    let id = UUID()
    var standort: String
    var art: String        // z. B. IVAS-SPCBCC35140070057
    var bez: String        // Bezeichnung
    var sn: String?        // Seriennummer
    var charge: String?    // Charge
    var qty: Int           // Menge (Bestand)
    var mhd: String        // Verfallsdatum, Text wie im PDF

    /// Artikelkennung ohne GET-/IVAS-Präfix
    var ref: String { normRef(art) }
    var mhdDate: Date? { parseDMY(mhd) }
}

/// Hält die geladene Soll-Liste für alle Reiter.
@MainActor
final class SollStore: ObservableObject {
    @Published private(set) var standort = ""
    @Published private(set) var rows: [SollRow] = []

    var total: Int { rows.reduce(0) { $0 + $1.qty } }

    func set(standort: String, rows: [SollRow]) {
        self.standort = standort
        self.rows = rows
    }
}
