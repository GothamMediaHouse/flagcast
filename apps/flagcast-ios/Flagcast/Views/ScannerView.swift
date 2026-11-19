import SwiftUI
import VisionKit
import AVFoundation

/// Scans the QR code on a cart card. Uses VisionKit's DataScannerViewController where the phone supports it,
/// and AVFoundation's QR reader otherwise. `onCode` returns true when the code was a Flagcast card.
struct ScannerSheet: View {
    var onCode: (String) -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var message = "Point your camera at the QR code on the cart card."
    @State private var denied = false

    private var visionKitWorks: Bool { DataScannerViewController.isSupported && DataScannerViewController.isAvailable }
    private var hasCamera: Bool { AVCaptureDevice.default(for: .video) != nil }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if denied || !hasCamera {
                VStack(spacing: 12) {
                    Image(systemName: "camera.fill").font(.largeTitle).foregroundStyle(.white.opacity(0.7))
                    Text(hasCamera ? "The camera isn’t available. Allow camera access in Settings, or type the codes instead."
                                   : "This device has no camera. Type the codes instead.")
                        .multilineTextAlignment(.center).foregroundStyle(.white).padding(.horizontal, 32)
                    if hasCamera, let u = URL(string: UIApplication.openSettingsURLString) {
                        Link("Open Settings", destination: u).buttonStyle(.fc(.primary, full: false))
                    }
                }
            } else if visionKitWorks {
                DataScanner { handle($0) }.ignoresSafeArea()
            } else {
                QRCamera { handle($0) }.ignoresSafeArea()
            }
            if hasCamera && !denied {
                RoundedRectangle(cornerRadius: 18).stroke(Color.fcFlag, lineWidth: 3)
                    .frame(width: 260, height: 260).allowsHitTesting(false)
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                Text(message).font(.callout).foregroundStyle(.white).multilineTextAlignment(.center)
                Button("Cancel") { dismiss() }.buttonStyle(.fcPlain)
            }
            .padding(.horizontal, 20).padding(.vertical, 16)
            .background(.black)
        }
        .task {
            guard hasCamera else { return }
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .notDetermined: denied = !(await AVCaptureDevice.requestAccess(for: .video))
            case .denied, .restricted: denied = true
            default: break
            }
        }
        .sensoryFeedback(.error, trigger: message)
    }

    private func handle(_ text: String) {
        if !onCode(text) { message = "That QR code isn’t a Flagcast card." }
    }
}

private struct DataScanner: UIViewControllerRepresentable {
    var found: (String) -> Void
    func makeUIViewController(context: Context) -> DataScannerViewController {
        let c = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.qr])], qualityLevel: .fast,
                                          recognizesMultipleItems: false, isHighFrameRateTrackingEnabled: false, isHighlightingEnabled: true)
        c.delegate = context.coordinator
        try? c.startScanning()
        return c
    }
    func updateUIViewController(_ c: DataScannerViewController, context: Context) {}
    static func dismantleUIViewController(_ c: DataScannerViewController, coordinator: Coordinator) { c.stopScanning() }
    func makeCoordinator() -> Coordinator { Coordinator(found: found) }
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let found: (String) -> Void
        private var last = ""
        init(found: @escaping (String) -> Void) { self.found = found }
        func dataScanner(_ s: DataScannerViewController, didAdd items: [RecognizedItem], allItems: [RecognizedItem]) {
            for case let .barcode(b) in items { if let v = b.payloadStringValue, v != last { last = v; found(v) } }
        }
    }
}

/// The fallback QR reader (AVCaptureMetadataOutput).
private struct QRCamera: UIViewControllerRepresentable {
    var found: (String) -> Void
    func makeUIViewController(context: Context) -> QRController { let c = QRController(); c.found = found; return c }
    func updateUIViewController(_ c: QRController, context: Context) {}

    final class QRController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
        var found: (String) -> Void = { _ in }
        private let session = AVCaptureSession()
        private var preview: AVCaptureVideoPreviewLayer?
        private var last = ""
        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .black
            guard let dev = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: dev), session.canAddInput(input) else { return }
            session.addInput(input)
            let out = AVCaptureMetadataOutput()
            guard session.canAddOutput(out) else { return }
            session.addOutput(out)
            out.setMetadataObjectsDelegate(self, queue: .main)
            out.metadataObjectTypes = [.qr]
            let p = AVCaptureVideoPreviewLayer(session: session)
            p.videoGravity = .resizeAspectFill
            view.layer.addSublayer(p)
            preview = p
            DispatchQueue.global(qos: .userInitiated).async { [session] in session.startRunning() }
        }
        override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); preview?.frame = view.bounds }
        override func viewWillDisappear(_ animated: Bool) { super.viewWillDisappear(animated); session.stopRunning() }
        func metadataOutput(_ o: AVCaptureMetadataOutput, didOutput objs: [AVMetadataObject], from c: AVCaptureConnection) {
            for case let m as AVMetadataMachineReadableCodeObject in objs { if let v = m.stringValue, v != last { last = v; found(v) } }
        }
    }
}
