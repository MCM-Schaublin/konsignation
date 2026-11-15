import Foundation
import PDFKit
import UIKit
import Vision

enum ImportError: LocalizedError {
    case cannotOpen

    var errorDescription: String? {
        "Die PDF-Datei konnte nicht geöffnet werden."
    }
}

enum PDFImporter {

    /// Liest den Text aus dem PDF. Hat es keinen Textanteil (Scan oder Druckerdatei), wird die Texterkennung genutzt.
    static func text(from url: URL) async throws -> String {
        guard let doc = PDFDocument(url: url) else { throw ImportError.cannotOpen }

        var text = ""
        for i in 0..<doc.pageCount {
            if let s = doc.page(at: i)?.string { text += s + "\n" }
        }
        if text.trimmingCharacters(in: .whitespacesAndNewlines).count > 30 {
            return text
        }
        return try await ocr(doc)
    }

    /// Texterkennung für ein Bild (JPG/PNG), z. B. aus einem Foto der Liste.
    static func text(fromImageAt url: URL) async throws -> String {
        guard let cg = UIImage(contentsOfFile: url.path)?.cgImage else { throw ImportError.cannotOpen }
        return try await recognize(cg).joined(separator: "\n")
    }

    private static func ocr(_ doc: PDFDocument) async throws -> String {
        var out = ""
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else { continue }
            let box = page.bounds(for: .mediaBox)
            let scale: CGFloat = 3   // ca. 216 dpi für gute Erkennung
            let size = CGSize(width: box.width * scale, height: box.height * scale)
            guard let cg = page.thumbnail(of: size, for: .mediaBox).cgImage else { continue }
            let lines = try await recognize(cg)
            out += lines.joined(separator: "\n") + "\n"
        }
        return out
    }

    /// Erkannte Wörter werden nach Zeilen gruppiert, von oben nach unten und links nach rechts.
    static func recognize(_ cg: CGImage) async throws -> [String] {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                let items: [(y: CGFloat, x: CGFloat, text: String)] = observations.compactMap { o in
                    guard let c = o.topCandidates(1).first else { return nil }
                    return (1 - o.boundingBox.midY, o.boundingBox.minX, c.string)
                }.sorted { $0.y < $1.y }

                var groups: [[(y: CGFloat, x: CGFloat, text: String)]] = []
                var lineY: CGFloat = -1
                for item in items {
                    if groups.isEmpty || abs(item.y - lineY) > 0.012 {
                        groups.append([item])
                        lineY = item.y
                    } else {
                        groups[groups.count - 1].append(item)
                    }
                }
                let lines = groups.map { group in
                    group.sorted { $0.x < $1.x }.map { $0.text }.joined(separator: " ")
                }
                continuation.resume(returning: lines)
            }
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["de-DE", "en-US"]
            request.usesLanguageCorrection = false

            do {
                try VNImageRequestHandler(cgImage: cg, options: [:]).perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
