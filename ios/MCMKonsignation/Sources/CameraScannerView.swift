import SwiftUI
import AVFoundation

/// Kamera-Ansicht, die Barcodes und DataMatrix-Codes erkennt (GS1-Etiketten).
struct CameraScannerView: UIViewControllerRepresentable {
    var onCodes: ([String]) -> Void

    func makeUIViewController(context: Context) -> ScannerViewController {
        let vc = ScannerViewController()
        vc.onCodes = onCodes
        return vc
    }

    func updateUIViewController(_ vc: ScannerViewController, context: Context) {
        vc.onCodes = onCodes
    }
}

/// Setzt kontinuierlichen Autofokus über den gesamten Bereich.
fileprivate func setContinuousFocus(_ device: AVCaptureDevice) {
    do {
        try device.lockForConfiguration()
        if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
        if device.isAutoFocusRangeRestrictionSupported { device.autoFocusRangeRestriction = .none }
        if device.isSmoothAutoFocusSupported { device.isSmoothAutoFocusEnabled = true }
        device.unlockForConfiguration()
    } catch {
        // Fokus bleibt auf der Standardeinstellung, der Scan funktioniert trotzdem.
    }
}

final class ScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onCodes: (([String]) -> Void)?

    private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var lastValue: String?
    private var lastTime = Date.distantPast
    private var device: AVCaptureDevice?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configure()
    }

    private func configure() {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else { return }

        self.device = device
        setContinuousFocus(device)

        session.beginConfiguration()
        if session.canAddInput(input) { session.addInput(input) }

        let output = AVCaptureMetadataOutput()
        if session.canAddOutput(output) {
            session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: .main)
            let wanted: [AVMetadataObject.ObjectType] = [.dataMatrix, .ean13, .ean8, .code128, .qr, .pdf417]
            output.metadataObjectTypes = wanted.filter { output.availableMetadataObjectTypes.contains($0) }
        }
        session.commitConfiguration()

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(layer)
        previewLayer = layer
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        let s = session
        let d = device
        DispatchQueue.global(qos: .userInitiated).async {
            s.startRunning()
            // Fokus nach dem Start noch einmal setzen, falls die Session ihn zurückgesetzt hat
            if let d { setContinuousFocus(d) }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        let s = session
        DispatchQueue.global(qos: .userInitiated).async { s.stopRunning() }
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput objects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        // Alle Codes im Bild, ohne Doppel (z. B. drei gleiche Strichcodes auf einer Packung)
        var values: [String] = []
        for obj in objects {
            if let v = (obj as? AVMetadataMachineReadableCodeObject)?.stringValue, !values.contains(v) {
                values.append(v)
            }
        }
        guard !values.isEmpty else { return }
        // Gleiches Bild innerhalb von 1,5 Sekunden nur einmal weitergeben.
        let key = values.sorted().joined(separator: "|")
        if key == lastValue && Date().timeIntervalSince(lastTime) < 1.5 { return }
        lastValue = key
        lastTime = Date()
        onCodes?(values)
    }
}
