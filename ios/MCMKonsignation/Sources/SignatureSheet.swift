import SwiftUI

/// Unterschriftenblatt für Kunde und MCM. Danach wird das PDF erstellt und geteilt.
struct SignatureSheet: View {
    let standort: String
    let result: CompareResult
    let rows: [SollRow]

    @Environment(\.dismiss) private var dismiss
    @State private var kundeStrokes: [[CGPoint]] = []
    @State private var mcmStrokes: [[CGPoint]] = []
    @State private var nameKunde = ""
    @State private var nameMcm = ""
    @State private var dateKunde = dstr(Date())
    @State private var dateMcm = dstr(Date())
    @State private var pdfURL: URL?

    var body: some View {
        NavigationStack {
            Form {
                Section("Kunde") {
                    signatureFields(strokes: $kundeStrokes, name: $nameKunde, date: $dateKunde)
                }
                Section("MCM Schaublin AG") {
                    signatureFields(strokes: $mcmStrokes, name: $nameMcm, date: $dateMcm)
                }
                Section {
                    if let url = pdfURL {
                        ShareLink(item: url) {
                            Label("PDF teilen", systemImage: "square.and.arrow.up")
                        }
                    } else {
                        Button("PDF erstellen") { makePDF() }
                    }
                }
            }
            .navigationTitle("Unterschriften")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { OrientationLock.set(.allButUpsideDown) }     // quer, damit das Feld grösser ist
            .onDisappear { OrientationLock.set(.portrait) }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schließen") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func signatureFields(strokes: Binding<[[CGPoint]]>, name: Binding<String>, date: Binding<String>) -> some View {
        SignatureCanvas(strokes: strokes)
            .aspectRatio(3.5, contentMode: .fit)
        HStack {
            Spacer()
            Button("Löschen", role: .destructive) { strokes.wrappedValue = [] }
        }
        TextField("Name", text: name)
        TextField("Datum", text: date)
    }

    private func makePDF() {
        pdfURL = PDFExport.write(
            standort: standort,
            result: result,
            rows: rows,
            kunde: PDFExport.Signature(image: SignatureRender.image(kundeStrokes),
                                       name: nameKunde.trimmingCharacters(in: .whitespaces),
                                       date: dateKunde.trimmingCharacters(in: .whitespaces)),
            mcm: PDFExport.Signature(image: SignatureRender.image(mcmStrokes),
                                     name: nameMcm.trimmingCharacters(in: .whitespaces),
                                     date: dateMcm.trimmingCharacters(in: .whitespaces))
        )
    }
}
