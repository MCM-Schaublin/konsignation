import SwiftUI

struct ResultView: View {
    @ObservedObject var soll: SollStore
    @ObservedObject var scan: ScanStore
    @State private var showSign = false

    var body: some View {
        NavigationStack {
            let r = Compare.run(rows: soll.rows, scans: scan.records)
            Group {
                if soll.rows.isEmpty {
                    ContentUnavailableView("Keine Soll-Liste", systemImage: "list.bullet.rectangle",
                                           description: Text("Lade zuerst eine Soll-Liste im Reiter Soll-Liste."))
                } else if scan.records.isEmpty {
                    ContentUnavailableView("Noch nichts gescannt", systemImage: "barcode.viewfinder",
                                           description: Text("Scanne Artikel im Reiter Scannen."))
                } else {
                    List {
                        Section("Übersicht") {
                            LabeledContent("Soll-Positionen", value: "\(r.sollCount)")
                            LabeledContent("Gescannt", value: "\(scan.records.count)")
                            LabeledContent("Fehlend (Stück)", value: "\(r.fehlend.reduce(0) { $0 + $1.missing })")
                            LabeledContent("Abweichend", value: "\(r.abweichend)")
                            LabeledContent("Zusätzlich", value: "\(r.zus.count)")
                            LabeledContent("Doppelt", value: "\(r.dopp.count)")
                        }

                        if !r.fehlend.isEmpty {
                            Section("Fehlt") {
                                ForEach(r.fehlend) { m in
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(m.row.art).font(.system(.body, design: .monospaced))
                                        Text(m.row.bez).font(.caption).lineLimit(1)
                                        Text("\(m.missing)× fehlt · \(sollDetails(m.row))")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }

                        if !r.zus.isEmpty {
                            Section("Zusätzlich gescannt") {
                                ForEach(r.zus) { rec in
                                    Text(rec.name).lineLimit(1)
                                }
                            }
                        }

                        if !r.art.isEmpty || !r.charge.isEmpty || !r.mhd.isEmpty {
                            Section("Abweichungen") {
                                ForEach(r.art) { m in
                                    Text("Artikel: Soll \(m.soll.art) · Ist \(m.scan.ref ?? "–")").font(.caption)
                                }
                                ForEach(r.charge) { m in
                                    Text("Charge: Soll \(m.soll.charge ?? "–") · Ist \(m.scan.lot ?? "–")").font(.caption)
                                }
                                ForEach(r.mhd) { m in
                                    Text("MHD: Soll \(m.soll.mhd) · Ist \(dstr(m.scan.exp))").font(.caption)
                                }
                            }
                        }

                        if !r.dopp.isEmpty {
                            Section("Doppelt gescannt") {
                                ForEach(r.dopp) { rec in
                                    Text("SN \(rec.sn ?? "–")").font(.caption)
                                }
                            }
                        }

                        if !r.abg.isEmpty {
                            Section("Abgelaufen") {
                                ForEach(r.abg) { item in
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.title).font(.caption.bold())
                                        Text(item.detail).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Ergebnis")
            .toolbar {
                if !soll.rows.isEmpty && !scan.records.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            showSign = true
                        } label: {
                            Label("PDF", systemImage: "signature")
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        ShareLink(item: CSVExport.url(for: r, standort: soll.standort)) {
                            Label("CSV teilen", systemImage: "square.and.arrow.up")
                        }
                    }
                }
            }
            .sheet(isPresented: $showSign) {
                SignatureSheet(standort: soll.standort, result: r, rows: soll.rows)
            }
        }
    }

    private func sollDetails(_ row: SollRow) -> String {
        var parts: [String] = []
        if let sn = row.sn { parts.append("SN \(sn)") }
        if let charge = row.charge { parts.append("Charge \(charge)") }
        if !row.mhd.isEmpty { parts.append("MHD \(row.mhd)") }
        return parts.joined(separator: " · ")
    }
}
