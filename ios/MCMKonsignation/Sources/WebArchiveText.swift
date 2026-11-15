import Foundation

struct WebArchiveError: LocalizedError {
    let text: String
    var errorDescription: String? { text }
}

/// Liest Inhalte aus einem Safari-Webarchiv: Text (HTML-Tabelle) oder eingebettetes Bild (Screenshot).
enum WebArchiveText {

    /// Alle Datenblöcke des Webarchivs (klassisch oder NSKeyedArchiver-Format).
    static func blobs(from url: URL) throws -> [Data] {
        let data = try Data(contentsOf: url)
        let any = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        var blobs: [Data] = []
        if let dict = any as? [String: Any] {
            if let main = dict["WebMainResource"] as? [String: Any], let d = main["WebResourceData"] as? Data {
                blobs.append(d)
            }
            if let objects = dict["$objects"] as? [Any] {
                blobs += objects.compactMap { $0 as? Data }
            }
        }
        return blobs
    }

    /// Größtes eingebettetes Bild (PNG oder JPEG), falls vorhanden.
    static func largestImage(from url: URL) -> Data? {
        guard let blobs = try? blobs(from: url) else { return nil }
        return blobs.filter(isImage).max(by: { $0.count < $1.count })
    }

    static func extract(from url: URL) throws -> String {
        let blobs = try blobs(from: url)
        var pages: [String] = []
        for blob in blobs {
            guard let text = decode(blob) else { continue }
            let t = text.lowercased()
            if t.contains("<html") || t.contains("<table") || t.contains("<tr") {
                pages.append(text)
            }
        }
        guard let html = pages.max(by: { $0.count < $1.count }) else {
            throw WebArchiveError(text: "Webarchiv: keine Tabelle gefunden (\(blobs.count) Datenblöcke)")
        }

        var out = html
        out = out.replacingOccurrences(of: "<script[\\s\\S]*?</script>", with: "", options: .regularExpression)
        out = out.replacingOccurrences(of: "<style[\\s\\S]*?</style>", with: "", options: .regularExpression)
        out = out.replacingOccurrences(of: "(?i)</(tr|p|div|li|h[1-6])>|<br\\s*/?>", with: "\n", options: .regularExpression)
        out = out.replacingOccurrences(of: "(?i)</(td|th)>", with: " ", options: .regularExpression)
        out = out.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        out = decodeEntities(out)

        return out.components(separatedBy: "\n")
            .map { $0.split(whereSeparator: { $0 == " " || $0 == "\t" }).joined(separator: " ") }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private static func isImage(_ d: Data) -> Bool {
        d.starts(with: [0x89, 0x50, 0x4E, 0x47]) || d.starts(with: [0xFF, 0xD8, 0xFF])
    }

    private static func decode(_ data: Data) -> String? {
        String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .windowsCP1252)
            ?? String(data: data, encoding: .isoLatin1)
    }

    private static func decodeEntities(_ s: String) -> String {
        s.replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
    }
}
