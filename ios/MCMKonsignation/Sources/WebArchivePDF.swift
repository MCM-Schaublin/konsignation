import Foundation
import UIKit
import WebKit

/// Wandelt eine Safari-Webarchiv-Datei (Vollbild-Export aus Safari) in ein echtes PDF um.
/// Die Erkennung erfolgt am Dateiinhalt, nicht an der Endung.
@MainActor
enum WebArchivePDF {

    /// Gibt eine PDF-Datei zurück. Ist die Datei schon ein PDF oder unbekannt, wird sie unverändert zurückgegeben.
    static func convert(_ url: URL) async throws -> URL {
        let data = try Data(contentsOf: url)
        if data.starts(with: Array("bplist00".utf8)) {
            let renderer = Renderer()
            return try await renderer.render(data: data)
        }
        return url
    }

    /// Hält die Web-Ansicht während des Renderns am Leben.
    private final class Renderer: NSObject, WKNavigationDelegate {
        private let webView: WKWebView
        private var continuation: CheckedContinuation<URL, Error>?

        override init() {
            let config = WKWebViewConfiguration()
            webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1024, height: 1400), configuration: config)
            super.init()
            webView.navigationDelegate = self
        }

        func render(data: Data) async throws -> URL {
            try await withCheckedThrowingContinuation { cont in
                self.continuation = cont
                // Die Web-Ansicht muss im Fenster hängen, sonst wird der Inhalt nicht gelayoutet.
                if let window = Self.keyWindow() {
                    webView.alpha = 0.01
                    window.addSubview(webView)
                }
                webView.load(data,
                             mimeType: "application/x-webarchive",
                             characterEncodingName: "utf-8",
                             baseURL: URL(fileURLWithPath: NSTemporaryDirectory()))
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Kurze Pause, damit der Inhalt fertig gezeichnet ist.
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 800_000_000)
                self?.webView.createPDF(configuration: WKPDFConfiguration()) { [weak self] result in
                    Task { @MainActor in
                        switch result {
                    case .success(let pdfData):
                        let out = FileManager.default.temporaryDirectory
                            .appendingPathComponent("web-\(UUID().uuidString).pdf")
                        do {
                            try pdfData.write(to: out)
                            self?.finish(.success(out))
                        } catch {
                            self?.finish(.failure(error))
                        }
                    case .failure(let error):
                        self?.finish(.failure(error))
                        }
                    }
                }
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            finish(.failure(error))
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            finish(.failure(error))
        }

        private static func keyWindow() -> UIWindow? {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .first { $0.isKeyWindow }
        }

        private func finish(_ result: Result<URL, Error>) {
            webView.removeFromSuperview()
            guard let cont = continuation else { return }
            continuation = nil
            cont.resume(with: result)
        }
    }
}
