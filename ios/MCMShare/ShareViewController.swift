import UIKit
import UniformTypeIdentifiers

/// Teilen-Erweiterung: nimmt eine Webseite (Text), ein PDF oder ein Bild aus Safari entgegen
/// und legt es im gemeinsamen Ordner ab. Die App übernimmt die Datei über „Geteilte Datei übernehmen“.
final class ShareViewController: UIViewController {
    private let label = UILabel()
    private let groupID = "group.ch.mcmschaublin.konsignation"

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        label.text = "Wird gespeichert …"
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            label.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24)
        ])
        save()
    }

    private func save() {
        guard let item = extensionContext?.inputItems.first as? NSExtensionItem,
              let providers = item.attachments, !providers.isEmpty else {
            fail("Keine Datei gefunden.")
            return
        }

        // 1) Webseite: das JavaScript aus Action.js liefert den sichtbaren Text
        if let web = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.propertyList.identifier) }) {
            web.loadItem(forTypeIdentifier: UTType.propertyList.identifier, options: nil) { [weak self] value, _ in
                guard let self else { return }
                let dict = value as? [String: Any]
                let results = dict?[NSExtensionJavaScriptPreprocessingResultsKey] as? [String: Any]
                guard let text = results?["text"] as? String, !text.isEmpty else {
                    self.fail("Auf dieser Seite wurde kein Text gefunden.")
                    return
                }
                do {
                    let dest = try self.inboxURL(extension: "txt")
                    try text.write(to: dest, atomically: true, encoding: .utf8)
                    DispatchQueue.main.async { self.done() }
                } catch {
                    self.fail("Speichern fehlgeschlagen.")
                }
            }
            return
        }

        // 2) PDF oder Bild
        guard let provider = providers.first else {
            fail("Keine Datei gefunden.")
            return
        }
        let type: UTType
        if provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) {
            type = .pdf
        } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            type = .image
        } else {
            fail("Nur Webseite, PDF oder Bild wird unterstützt.")
            return
        }

        provider.loadFileRepresentation(forTypeIdentifier: type.identifier) { [weak self] url, error in
            guard let self else { return }
            guard let url, error == nil else {
                self.fail("Datei konnte nicht gelesen werden.")
                return
            }
            let fallbackExt = type == .pdf ? "pdf" : "jpg"
            let ext = url.pathExtension.isEmpty ? fallbackExt : url.pathExtension
            do {
                let dest = try self.inboxURL(extension: ext)
                // Die URL aus loadFileRepresentation ist nur kurz gültig, deshalb kopieren
                try FileManager.default.copyItem(at: url, to: dest)
                DispatchQueue.main.async { self.done() }
            } catch {
                self.fail("Speichern fehlgeschlagen.")
            }
        }
    }

    private func inboxURL(extension ext: String) throws -> URL {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID) else {
            throw CocoaError(.fileNoSuchFile)
        }
        let dir = container.appendingPathComponent("Inbox", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(UUID().uuidString + "." + ext)
    }

    private func done() {
        label.text = "Gespeichert. Öffne jetzt MCM-Konsignation, um die Liste zu laden."
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        }
    }

    private func fail(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            self?.label.text = message
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                self?.extensionContext?.cancelRequest(withError: CocoaError(.userCancelled))
            }
        }
    }
}
