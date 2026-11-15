import Foundation

/// Gemeinsamer Ordner mit der Teilen-Erweiterung (App Group).
enum Inbox {
    static let groupID = "group.ch.mcmschaublin.konsignation"

    /// Gibt die nächste geteilte Datei zurück, falls eine wartet.
    static func takeNext() -> URL? {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID) else {
            return nil
        }
        let dir = container.appendingPathComponent("Inbox", isDirectory: true)
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil,
                                                                  options: [.skipsHiddenFiles])) ?? []
        return files.first
    }

    /// Diagnose: zeigt, ob der gemeinsame Ordner erreichbar ist und was darin liegt.
    static func status() -> String {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID) else {
            return "Diagnose: kein Zugriff auf die App Group."
        }
        let dir = container.appendingPathComponent("Inbox", isDirectory: true)
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return "Diagnose: Inbox enthält \(files.count) Datei(en)" + (files.isEmpty ? "" : ": " + files.joined(separator: ", "))
    }

    /// Alle wartenden geteilten Dateien, die älteste zuerst.
    static func pending() -> [URL] {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID) else {
            return []
        }
        let dir = container.appendingPathComponent("Inbox", isDirectory: true)
        let files = (try? FileManager.default.contentsOfDirectory(at: dir,
                                                                  includingPropertiesForKeys: [.creationDateKey],
                                                                  options: [.skipsHiddenFiles])) ?? []
        return files.sorted {
            let a = (try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            let b = (try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return a < b
        }
    }
}
