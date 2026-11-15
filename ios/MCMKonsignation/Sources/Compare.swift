import Foundation

struct Mismatch: Identifiable {
    let id = UUID()
    let soll: SollRow
    let scan: ScanRecord
}

struct Missing: Identifiable {
    let id = UUID()
    let row: SollRow
    let missing: Int
}

struct ExpiryItem: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
}

struct CompareResult {
    var sollCount = 0
    var fehlend: [Missing] = []
    var zus: [ScanRecord] = []
    var art: [Mismatch] = []
    var charge: [Mismatch] = []
    var mhd: [Mismatch] = []
    var dopp: [ScanRecord] = []
    var abg: [ExpiryItem] = []
    var abweichend = 0
}

/// Gleicht Scans gegen die Soll-Liste ab (Regeln wie compare() in der Web-Version).
enum Compare {
    static func run(rows: [SollRow], scans: [ScanRecord]) -> CompareResult {
        var r = CompareResult(sollCount: rows.count)
        var rem = rows.map { $0.sn != nil ? 1 : max($0.qty, 1) }
        var deviating = Set<Int>()
        var expiredMatched = Set<Int>()
        var seenSN = Set<String>()
        let today = Calendar.current.startOfDay(for: Date())

        for sc in scans {
            if let sn = sc.sn {
                if seenSN.contains(sn) {
                    r.dopp.append(sc)
                    continue
                }
                seenSN.insert(sn)
            }

            var found: Int? = nil
            if let sn = sc.sn {
                found = rows.indices.first { rem[$0] > 0 && rows[$0].sn == sn }
                if found == nil, let ref = sc.ref {
                    found = rows.indices.first { rem[$0] > 0 && rows[$0].sn == nil && rows[$0].ref == ref }
                }
            } else if let ref = sc.ref {
                // 1. Exakt: gleiche Artikelnummer und gleiche LOT, noch offen
                found = rows.indices.first { rem[$0] > 0 && rows[$0].sn == nil && rows[$0].ref == ref && rows[$0].charge == sc.lot }
                // 2. Charge-Abweichung nur, wenn diese LOT gar nicht auf der Liste steht.
                //    Steht die LOT auf der Liste, ist ein Scan ohne offene Zeile zusätzlich, keine Abweichung.
                if found == nil {
                    let lotOnList = rows.contains { $0.sn == nil && $0.ref == ref && $0.charge == sc.lot }
                    if !lotOnList {
                        found = rows.indices.first { rem[$0] > 0 && rows[$0].sn == nil && rows[$0].ref == ref }
                    }
                }
            }

            guard let m = found else {
                r.zus.append(sc)
                continue
            }
            rem[m] -= 1
            let row = rows[m]

            if let ref = sc.ref, row.ref != ref {
                r.art.append(Mismatch(soll: row, scan: sc)); deviating.insert(m)
            }
            if let lot = sc.lot, let c = row.charge, lot != c {
                r.charge.append(Mismatch(soll: row, scan: sc)); deviating.insert(m)
            }
            if let exp = sc.exp, let d = row.mhdDate, exp != d {
                r.mhd.append(Mismatch(soll: row, scan: sc)); deviating.insert(m)
            }
            if let exp = sc.exp, exp < today {
                r.abg.append(ExpiryItem(title: "Gescannt, abgelaufen", detail: "\(row.art) · MHD \(dstr(exp))"))
                expiredMatched.insert(m)
            }
        }

        for (i, row) in rows.enumerated() {
            if rem[i] > 0 {
                r.fehlend.append(Missing(row: row, missing: rem[i]))
            }
            if let d = row.mhdDate, d < today, !expiredMatched.contains(i) {
                r.abg.append(ExpiryItem(title: "Liste, abgelaufen", detail: "\(row.art) · MHD \(dstr(d))"))
            }
        }
        r.abweichend = deviating.count
        return r
    }
}
