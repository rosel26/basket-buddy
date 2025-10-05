//
//  BarcodeScannerView.swift
//  BasketBuddy
//
//  Created by Elly Zheng on 10/1/25.
//

import SwiftUI
import AVFoundation

struct BarcodeScannerView: UIViewControllerRepresentable {
    @Binding var scannedCode: String?
    @Environment(\.presentationMode) var presentationMode

    func makeUIViewController(context: Context) -> ScannerViewController {
        let scannerVC = ScannerViewController()
        scannerVC.delegate = context.coordinator
        return scannerVC
    }

    func updateUIViewController(_ uiViewController: ScannerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, ScannerViewControllerDelegate {
        var parent: BarcodeScannerView

        init(_ parent: BarcodeScannerView) {
            self.parent = parent
        }

        func didScanBarcode(_ code: String) {
            parent.scannedCode = code
            parent.presentationMode.wrappedValue.dismiss() // automatically close sheet
        }
    }
}

protocol ScannerViewControllerDelegate: AnyObject {
    func didScanBarcode(_ code: String)
}

class ScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    weak var delegate: ScannerViewControllerDelegate?

    private let captureSession = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer!

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupCaptureSession()
    }

    private func setupCaptureSession() {
        guard let videoDevice = AVCaptureDevice.default(for: .video) else { return }

        do {
            let input = try AVCaptureDeviceInput(device: videoDevice)
            if captureSession.canAddInput(input) { captureSession.addInput(input) }

            let metadataOutput = AVCaptureMetadataOutput()
            if captureSession.canAddOutput(metadataOutput) {
                captureSession.addOutput(metadataOutput)
                metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
                metadataOutput.metadataObjectTypes = [.ean8, .ean13, .qr, .code128, .code39]
            }

            previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
            previewLayer.videoGravity = .resizeAspectFill
            previewLayer.frame = view.layer.bounds
            view.layer.addSublayer(previewLayer)

            DispatchQueue.global(qos: .userInitiated).async {
                self.captureSession.startRunning()
            }
        } catch {
            print("Error setting up camera input: \(error)")
        }
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        guard let metadata = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let code = metadata.stringValue else { return }

        // Stop the session after detecting a barcode
        DispatchQueue.global(qos: .userInitiated).async {
            self.captureSession.stopRunning()
        }

        delegate?.didScanBarcode(code)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }
}
