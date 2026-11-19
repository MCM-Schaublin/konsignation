import SwiftUI
import AVFoundation

/// Kamera-Ansicht, die Barcodes und DataMatrix-Codes erkennt (GS1-Etiketten).
struct CameraScannerView: UIViewControllerRepresentable {
    var onCode: (String) -> Void

    func makeUIViewController(context: Context) -> ScannerViewController {
        let vc = ScannerViewController()
        vc.onCode = onCode
        return vc
    }

    func updateUIViewController(_ vc: ScannerViewController, context: Context) {
        vc.onCode = onCode
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
    var onCode: ((String) -> Void)?

    private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var lastValue: String?
    private var lastTime = Date.distantPast
    private var device: AVCaptureDevice?
    private let focusLabel = UILabel()
    private var focusTimer: Timer?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configure()
        // Tippen auf das Bild setzt den Fokus auf die getippte Stelle
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleFocusTap(_:)))
        view.addGestureRecognizer(tap)

        // Anzeige für Fokus-Modus und Linsenposition (zum Testen)
        focusLabel.font = .monospacedSystemFont(ofSize: 12, weight: .semibold)
        focusLabel.textColor = .white
        focusLabel.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        focusLabel.textAlignment = .center
        view.addSubview(focusLabel)
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
        let width: CGFloat = 280
        focusLabel.frame = CGRect(x: (view.bounds.width - width) / 2,
                                  y: view.safeAreaInsets.top + 8,
                                  width: width, height: 24)
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
        focusTimer?.invalidate()
        focusTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.updateFocusLabel()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        focusTimer?.invalidate()
        focusTimer = nil
        let s = session
        DispatchQueue.global(qos: .userInitiated).async { s.stopRunning() }
    }

    private func updateFocusLabel() {
        guard let d = device else {
            focusLabel.text = "Kamera nicht verfügbar"
            return
        }
        let mode: String
        switch d.focusMode {
        case .locked: mode = "gesperrt"
        case .autoFocus: mode = "einmalig"
        case .continuousAutoFocus: mode = "kontinuierlich"
        @unknown default: mode = "unbekannt"
        }
        focusLabel.text = "Fokus: \(mode) · Linse \(String(format: "%.2f", d.lensPosition))"
    }

    @objc private func handleFocusTap(_ gesture: UITapGestureRecognizer) {
        guard let device, let previewLayer else { return }
        let point = previewLayer.captureDevicePointConverted(fromLayerPoint: gesture.location(in: view))
        do {
            try device.lockForConfiguration()
            if device.isFocusPointOfInterestSupported { device.focusPointOfInterest = point }
            if device.isFocusModeSupported(.autoFocus) { device.focusMode = .autoFocus }
            device.unlockForConfiguration()
        } catch { return }
        // Nach dem Antippen wieder auf kontinuierlichen Autofokus schalten
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, let device = self.device else { return }
            setContinuousFocus(device)
        }
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput objects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        guard let obj = objects.first as? AVMetadataMachineReadableCodeObject,
              let value = obj.stringValue else { return }
        // Gleicher Code wird innerhalb von 1,5 Sekunden nur einmal gezählt.
        if value == lastValue && Date().timeIntervalSince(lastTime) < 1.5 { return }
        lastValue = value
        lastTime = Date()
        onCode?(value)
    }
}
