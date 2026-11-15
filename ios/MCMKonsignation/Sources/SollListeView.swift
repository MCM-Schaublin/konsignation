import SwiftUI
import UniformTypeIdentifiers

struct SollListeView: View {
    @ObservedObject var store: SollStore
    @Binding var incoming: URL?
    @State private var showImporter = false
    @State private var busy = false
    @State private var message: String?
    @State private var preview: String = ""

    private let xlsxType = UTType(filenameExtension: "xlsx") ?? .data

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        showImporter = true
                    } label: {
                        Label("Soll-Liste (PDF oder Excel) auswählen", systemImage: "doc.badge.plus")
                    }
                    .disabled(busy)

                    if busy {
                        HStack {
                            ProgressView()
                            Text("Liste wird gelesen …")
                        }
                    }
                    if let message {
                        Text(message).foregroundStyle(.red)
                    }
                    let waiting = Inbox.pending()
                    if !waiting.isEmpty && !busy {
                        Button {
                            Task { await importNextFromInbox() }
                        } label: {
                            Label("Geteilte Datei übernehmen (\(waiting.count))", systemImage: "square.and.arrow.down")
                        }
                        Button(role: .destructive) {
                            Inbox.pending().forEach { try? FileManager.default.removeItem(at: $0) }
                            message = nil
                        } label: {
                            Label("Alle wartenden Dateien verwerfen", systemImage: "trash")
                        }
                    }
                }

                if !store.rows.isEmpty {
                    Section {
                        ForEach(store.rows) { row in
                            SollRowView(row: row)
                        }
                    } header: {
                        Text("\(store.standort) · \(store.rows.count) Positionen · Soll gesamt \(store.total)")
                    }
                }
            }
            .navigationTitle("Soll-Liste")
            .onChange(of: incoming) { _, newValue in
                guard let file = newValue else { return }
                incoming = nil
                Task {
                    await load(file)
                    try? FileManager.default.removeItem(at: file)
                }
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.pdf, xlsxType]) { result in
                switch result {
                case .success(let url):
                    Task { await load(url) }
                case .failure(let err):
                    message = err.localizedDescription
                }
            }
        }
    }

    /// Übernimmt die älteste geteilte Datei aus dem gemeinsamen Ordner und entfernt sie danach.
    private func importNextFromInbox() async {
        guard let file = Inbox.pending().first else { return }
        await load(file)
        try? FileManager.default.removeItem(at: file)
    }

    private func load(_ url: URL) async {
        busy = true
        message = nil
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        var diag = ""
        do {
            let result: (standort: String, rows: [SollRow])
            // Die Art der Datei wird am Inhalt erkannt, nicht an der Endung:
            // Safari-Vollbild-Exporte (Webarchiv) können mit .jpeg ankommen.
            let head = (try? Data(contentsOf: url, options: .alwaysMapped).prefix(8)) ?? Data()
            let isWebArchive = head.starts(with: Array("bplist00".utf8))
            let isPDFData = head.starts(with: Array("%PDF".utf8))
            let hex = head.map { String(format: "%02X", $0) }.joined(separator: " ")
            diag = "Datei \(url.pathExtension.lowercased()), Kopf: \(hex)"

            if url.pathExtension.lowercased() == "xlsx" {
                result = try await Task.detached(priority: .userInitiated) {
                    try XLSXImporter.load(url: url)
                }.value
            } else if url.pathExtension.lowercased() == "txt" {
                // Sichtbarer Text einer Webseite (aus der Teilen-Erweiterung)
                let text = try String(contentsOf: url, encoding: .utf8)
                preview = String(text.prefix(400))
                let parsed = SollParser.parse(text)
                result = (parsed.standort, parsed.rows)
            } else if isWebArchive {
                // Safari-Vollbild-Export: Text direkt aus dem Webarchiv lesen.
                // Enthält das Webarchiv eine Tabelle, wird der Text gelesen, sonst das eingebettete Bild per Texterkennung.
                let text = try await Task.detached(priority: .userInitiated) { () async throws -> String in
                    do {
                        return try WebArchiveText.extract(from: url)
                    } catch {
                        guard let img = WebArchiveText.largestImage(from: url) else { throw error }
                        let tmp = FileManager.default.temporaryDirectory
                            .appendingPathComponent("wa-\(UUID().uuidString).png")
                        try img.write(to: tmp)
                        return try await PDFImporter.text(fromImageAt: tmp)
                    }
                }.value
                preview = String(text.prefix(400))
                let parsed = SollParser.parse(text)
                result = (parsed.standort, parsed.rows)
            } else if !isPDFData && ["jpg", "jpeg", "png"].contains(url.pathExtension.lowercased()) {
                // Foto oder Bild der Liste: Texterkennung im Hintergrund
                let text = try await Task.detached(priority: .userInitiated) {
                    try await PDFImporter.text(fromImageAt: url)
                }.value
                let parsed = SollParser.parse(text)
                result = (parsed.standort, parsed.rows)
            } else {
                // PDF: Lesen und Texterkennung laufen im Hintergrund, damit die Oberfläche nicht hängt.
                let text = try await Task.detached(priority: .userInitiated) {
                    // Safari-Vollbild-Exporte sind Webarchive und werden zuerst in ein PDF gewandelt.
                    let pdf = try await WebArchivePDF.convert(url)
                    return try await PDFImporter.text(from: pdf)
                }.value
                preview = String(text.prefix(400))
                let parsed = SollParser.parse(text)
                result = (parsed.standort, parsed.rows)
            }
            store.set(standort: result.standort, rows: result.rows)
            if result.rows.isEmpty {
                message = "Keine Positionen erkannt. Textauszug: " + (preview.isEmpty ? "(leer)" : preview)
            }
        } catch {
            message = error.localizedDescription + " [" + diag + "]"
        }
        busy = false
    }
}

struct SollRowView: View {
    let row: SollRow

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.art)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)
                if !row.bez.isEmpty {
                    Text(row.bez)
                        .font(.caption)
                        .lineLimit(1)
                }
                Text(details)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(row.qty)×")
                .font(.headline)
                .foregroundStyle(Brand.navy)
        }
    }

    private var details: String {
        var parts: [String] = []
        if let sn = row.sn { parts.append("SN \(sn)") }
        if let charge = row.charge { parts.append("Charge \(charge)") }
        if !row.mhd.isEmpty { parts.append("MHD \(row.mhd)") }
        return parts.joined(separator: " · ")
    }
}
