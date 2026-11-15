import SwiftUI
import AVFoundation
import UIKit

struct ScanView: View {
    @ObservedObject var store: ScanStore
    @State private var manual = ""

    private var cameraDenied: Bool {
        let s = AVCaptureDevice.authorizationStatus(for: .video)
        return s == .denied || s == .restricted
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if cameraDenied {
                    ContentUnavailableView("Kamera gesperrt", systemImage: "camera.fill",
                                           description: Text("Bitte in den Einstellungen den Kamera-Zugriff für MCM-Konsignation erlauben."))
                        .frame(height: 240)
                } else {
                    CameraScannerView { store.add($0) }
                        .frame(height: 240)
                        .background(.black)
                        // Bildschirm bleibt während des Scannens an
                        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
                        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
                }

                if let notice = store.notice {
                    Text(notice)
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                        .padding(.top, 6)
                }

                HStack {
                    TextField("Code einfügen (GS1-Text)", text: $manual)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onSubmit(addManual)
                    Button("Hinzufügen", action: addManual)
                        .buttonStyle(.bordered)
                        .disabled(manual.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding()

                List {
                    Section {
                        ForEach(store.records.reversed()) { rec in
                            HStack(alignment: .top) {
                                Image(systemName: rec.known ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                    .foregroundStyle(rec.known ? .green : .orange)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(rec.name).lineLimit(1)
                                    Text(details(rec))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                        .onDelete { offsets in
                            // Anzeige ist umgekehrt, deshalb Index umrechnen
                            let count = store.records.count
                            store.remove(IndexSet(offsets.map { count - 1 - $0 }))
                        }
                    } header: {
                        Text("\(store.records.count) gescannt")
                    }
                }
                .listStyle(.insetGrouped)
            }
            .navigationTitle("Scannen")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Letzten +1") { store.plusOneLast() }
                        .disabled(store.lastRecord == nil)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Leeren", role: .destructive) { store.clear() }
                        .disabled(store.records.isEmpty)
                }
            }
        }
    }

    private func addManual() {
        store.add(manual, manual: true)
        manual = ""
    }

    private func details(_ rec: ScanRecord) -> String {
        var parts: [String] = []
        if let sn = rec.sn { parts.append("SN \(sn)") }
        if let lot = rec.lot { parts.append("Charge \(lot)") }
        if rec.exp != nil { parts.append("MHD \(dstr(rec.exp))") }
        return parts.joined(separator: " · ")
    }
}
