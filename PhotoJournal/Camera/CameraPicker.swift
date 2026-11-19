import AVFoundation
import SwiftUI
import UIKit

/// A small in-app camera with native-style controls and orientation-aware capture.
struct CameraPicker: UIViewControllerRepresentable {
    var onPhoto: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> CameraCaptureViewController {
        CameraCaptureViewController(onPhoto: onPhoto, onCancel: { dismiss() })
    }

    func updateUIViewController(_ controller: CameraCaptureViewController, context: Context) { }
}

final class CameraCaptureViewController: UIViewController, AVCapturePhotoCaptureDelegate {
    private let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let sessionQueue = DispatchQueue(label: "photojournal.camera.session")

    private let cancelButton = UIButton(type: .system)
    private let flashButton = UIButton(type: .system)
    private let flipCameraButton = UIButton(type: .system)
    private let shutterButton = UIButton(type: .system)
    private let modeLabel = UILabel()
    private let statusLabel = UILabel()
    private let zoomStack = UIStackView()

    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var activeCamera: AVCaptureDevice?
    private var mainCamera: AVCaptureDevice?
    private var ultraWideCamera: AVCaptureDevice?
    private var frontCamera: AVCaptureDevice?
    private var isUsingFrontCamera = false
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var previewRotationObservation: NSKeyValueObservation?
    private var captureRotationObservation: NSKeyValueObservation?
    private var captureRotationAngle: CGFloat = 0
    private var availableZoomFactors: [CGFloat] = []
    private var backZoomFactors: [CGFloat] = [1]
    private var selectedZoom: CGFloat = 1
    private var pinchStartFactor: CGFloat = 1
    private var pinchDisplayMultiplier: CGFloat = 1
    private var flashEnabled = false
    private var sessionReady = false
    private var currentLayoutIsLandscape: Bool?
    private var portraitConstraints: [NSLayoutConstraint] = []
    private var landscapeConstraints: [NSLayoutConstraint] = []

    private let onPhoto: (UIImage) -> Void
    private let onCancel: () -> Void

    init(onPhoto: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void) {
        self.onPhoto = onPhoto
        self.onCancel = onCancel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .allButUpsideDown }
    override var prefersStatusBarHidden: Bool { true }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        makeControls()
        requestCameraAccessAndConfigure()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
        updateControlLayoutIfNeeded()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    private func makeControls() {
        cancelButton.setTitle("Cancel", for: .normal)
        cancelButton.setTitleColor(.white, for: .normal)
        cancelButton.titleLabel?.font = .preferredFont(forTextStyle: .body)
        cancelButton.backgroundColor = UIColor.black.withAlphaComponent(0.35)
        cancelButton.layer.cornerRadius = 18
        cancelButton.addTarget(self, action: #selector(cancelCapture), for: .touchUpInside)
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(cancelButton)

        flashButton.setImage(UIImage(systemName: "bolt.slash.fill"), for: .normal)
        flashButton.tintColor = .white
        flashButton.backgroundColor = UIColor.black.withAlphaComponent(0.35)
        flashButton.layer.cornerRadius = 22
        flashButton.addTarget(self, action: #selector(toggleFlash), for: .touchUpInside)
        flashButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(flashButton)

        flipCameraButton.setImage(UIImage(systemName: "camera.rotate"), for: .normal)
        flipCameraButton.tintColor = .white
        flipCameraButton.backgroundColor = UIColor.black.withAlphaComponent(0.35)
        flipCameraButton.layer.cornerRadius = 22
        flipCameraButton.accessibilityLabel = "Switch camera"
        flipCameraButton.addTarget(self, action: #selector(flipCamera), for: .touchUpInside)
        flipCameraButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(flipCameraButton)

        zoomStack.axis = .horizontal
        zoomStack.alignment = .center
        zoomStack.distribution = .equalSpacing
        zoomStack.spacing = 8
        zoomStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(zoomStack)

        shutterButton.backgroundColor = .white
        shutterButton.layer.cornerRadius = 38
        shutterButton.layer.borderWidth = 5
        shutterButton.layer.borderColor = UIColor.white.withAlphaComponent(0.45).cgColor
        shutterButton.isEnabled = false
        shutterButton.alpha = 0.55
        shutterButton.accessibilityLabel = "Take photo"
        shutterButton.addTarget(self, action: #selector(takePhoto), for: .touchUpInside)
        shutterButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(shutterButton)

        modeLabel.text = "PHOTO"
        modeLabel.textColor = .white
        modeLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        modeLabel.textAlignment = .center
        modeLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(modeLabel)

        statusLabel.textColor = .white
        statusLabel.font = .preferredFont(forTextStyle: .body)
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLabel)

        let pinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        view.addGestureRecognizer(pinchGesture)

        NSLayoutConstraint.activate([
            cancelButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 18),
            cancelButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            cancelButton.widthAnchor.constraint(equalToConstant: 84),
            cancelButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),

            flashButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -18),
            flashButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            flashButton.widthAnchor.constraint(equalToConstant: 44),
            flashButton.heightAnchor.constraint(equalToConstant: 44),

            flipCameraButton.trailingAnchor.constraint(equalTo: flashButton.leadingAnchor, constant: -10),
            flipCameraButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            flipCameraButton.widthAnchor.constraint(equalToConstant: 44),
            flipCameraButton.heightAnchor.constraint(equalToConstant: 44),

            shutterButton.widthAnchor.constraint(equalToConstant: 76),
            shutterButton.heightAnchor.constraint(equalToConstant: 76),

            modeLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            statusLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24)
        ])

        buildZoomButtons([1])
        updateControlLayoutIfNeeded()
    }

    private func updateControlLayoutIfNeeded() {
        let isLandscape = view.bounds.width > view.bounds.height
        guard currentLayoutIsLandscape != isLandscape else { return }
        currentLayoutIsLandscape = isLandscape

        NSLayoutConstraint.deactivate(portraitConstraints + landscapeConstraints)
        zoomStack.axis = isLandscape ? .vertical : .horizontal

        if isLandscape {
            landscapeConstraints = [
                shutterButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
                shutterButton.centerYAnchor.constraint(equalTo: view.centerYAnchor),
                zoomStack.trailingAnchor.constraint(equalTo: shutterButton.leadingAnchor, constant: -20),
                zoomStack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
                modeLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                modeLabel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12)
            ]
            portraitConstraints = [
                shutterButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                shutterButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -78),
                zoomStack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                zoomStack.bottomAnchor.constraint(equalTo: shutterButton.topAnchor, constant: -22)
            ]
        } else {
            portraitConstraints = [
                shutterButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                shutterButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -78),
                zoomStack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                zoomStack.bottomAnchor.constraint(equalTo: shutterButton.topAnchor, constant: -22),
                modeLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                modeLabel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12)
            ]
            landscapeConstraints = [
                shutterButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
                shutterButton.centerYAnchor.constraint(equalTo: view.centerYAnchor),
                zoomStack.trailingAnchor.constraint(equalTo: shutterButton.leadingAnchor, constant: -20),
                zoomStack.centerYAnchor.constraint(equalTo: view.centerYAnchor)
            ]
        }

        NSLayoutConstraint.activate(isLandscape ? landscapeConstraints : portraitConstraints)
    }

    private func requestCameraAccessAndConfigure() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] allowed in
                guard let self else { return }
                if allowed {
                    self.configureSession()
                } else {
                    self.showMessage("Camera access is off. You can allow it in iPhone Settings.")
                }
            }
        default:
            showMessage("Camera access is off. You can allow it in iPhone Settings.")
        }
    }

    private func configureSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            let discovery = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera,
                              .builtInUltraWideCamera, .builtInWideAngleCamera],
                mediaType: .video,
                position: .back
            )
            let camera = discovery.devices.first(where: { $0.deviceType == .builtInTripleCamera })
                ?? discovery.devices.first(where: { $0.deviceType == .builtInDualWideCamera })
                ?? discovery.devices.first(where: { $0.deviceType == .builtInDualCamera })
                ?? discovery.devices.first(where: { $0.deviceType == .builtInWideAngleCamera })
            let frontDiscovery = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.builtInTrueDepthCamera, .builtInWideAngleCamera],
                mediaType: .video,
                position: .front
            )
            guard let camera,
                  let input = try? AVCaptureDeviceInput(device: camera) else {
                self.showMessage("The camera is unavailable on this device.")
                return
            }

            self.session.beginConfiguration()
            self.session.sessionPreset = .photo
            guard self.session.canAddInput(input), self.session.canAddOutput(self.photoOutput) else {
                self.session.commitConfiguration()
                self.showMessage("The camera could not be started.")
                return
            }
            self.session.addInput(input)
            self.session.addOutput(self.photoOutput)
            self.session.commitConfiguration()

            self.activeCamera = camera
            self.mainCamera = camera
            self.frontCamera = frontDiscovery.devices.first(where: { $0.deviceType == .builtInTrueDepthCamera })
                ?? frontDiscovery.devices.first(where: { $0.deviceType == .builtInWideAngleCamera })
            self.ultraWideCamera = camera.constituentDevices.first(where: { $0.deviceType == .builtInUltraWideCamera })
                ?? discovery.devices.first(where: { $0.deviceType == .builtInUltraWideCamera })
                ?? AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .back)

            // UI zoom labels can use a different scale than videoZoomFactor.
            // Convert the labels using Apple's display multiplier so 1× maps
            // to the camera's actual main-lens framing.
            let multiplier = max(camera.displayVideoZoomFactorMultiplier, 0.001)
            let supportsDisplayZoom: (CGFloat) -> Bool = { displayZoom in
                let deviceZoom = displayZoom / multiplier
                return deviceZoom >= camera.minAvailableVideoZoomFactor
                    && deviceZoom <= camera.maxAvailableVideoZoomFactor
            }
            var factors: [CGFloat] = []
            if supportsDisplayZoom(0.5) || self.ultraWideCamera != nil { factors.append(0.5) }
            factors.append(contentsOf: [1, 2].filter(supportsDisplayZoom))
            if factors.isEmpty { factors = [1] }
            self.backZoomFactors = factors.isEmpty ? [1] : factors

            let oneXDeviceZoom = 1 / multiplier
            if oneXDeviceZoom >= camera.minAvailableVideoZoomFactor,
               oneXDeviceZoom <= camera.maxAvailableVideoZoomFactor {
                do {
                    try camera.lockForConfiguration()
                    camera.videoZoomFactor = oneXDeviceZoom
                    camera.unlockForConfiguration()
                } catch { }
            }

            DispatchQueue.main.async {
                let preview = AVCaptureVideoPreviewLayer(session: self.session)
                // Show the full live camera frame. Aspect-fill crops the sides
                // on a tall phone display, making 1× look more zoomed than the photo.
                preview.videoGravity = .resizeAspect
                self.view.layer.insertSublayer(preview, at: 0)
                self.previewLayer = preview
                self.configureRotation(for: camera, previewLayer: preview)
                self.buildZoomButtons(self.backZoomFactors)
                self.flashButton.isEnabled = camera.hasFlash
                self.flashButton.alpha = camera.hasFlash ? 1 : 0.45
                self.flipCameraButton.isEnabled = self.frontCamera != nil
                self.flipCameraButton.alpha = self.frontCamera == nil ? 0.45 : 1
                self.sessionReady = true
                self.shutterButton.isEnabled = true
                self.shutterButton.alpha = 1
                self.view.setNeedsLayout()
            }
            self.session.startRunning()
        }
    }

    private func buildZoomButtons(_ factors: [CGFloat]) {
        zoomStack.arrangedSubviews.forEach { view in
            zoomStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        availableZoomFactors = factors
        selectedZoom = 1

        for factor in factors {
            let button = UIButton(type: .system)
            button.setTitle(zoomLabel(factor), for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
            button.layer.cornerRadius = 21
            button.backgroundColor = UIColor.black.withAlphaComponent(0.38)
            button.widthAnchor.constraint(equalToConstant: 54).isActive = true
            button.heightAnchor.constraint(equalToConstant: 42).isActive = true
            button.tag = Int(factor * 10)
            button.addTarget(self, action: #selector(selectZoom(_:)), for: .touchUpInside)
            zoomStack.addArrangedSubview(button)
        }
        updateZoomButtonAppearance()
    }

    private func zoomLabel(_ factor: CGFloat) -> String {
        factor == floor(factor) ? "\(Int(factor))×" : String(format: "%.1f×", Double(factor))
    }

    private func updateZoomButtonAppearance() {
        for view in zoomStack.arrangedSubviews {
            guard let button = view as? UIButton else { continue }
            let factor = CGFloat(button.tag) / 10
            let nearestFactor = availableZoomFactors.min(by: { abs($0 - selectedZoom) < abs($1 - selectedZoom) })
            let selected = nearestFactor.map { abs($0 - factor) < 0.001 } ?? false
            button.setTitleColor(selected ? .systemYellow : .white, for: .normal)
            button.backgroundColor = selected
                ? UIColor.black.withAlphaComponent(0.62)
                : UIColor.black.withAlphaComponent(0.38)
        }
    }

    private func configureRotation(for camera: AVCaptureDevice, previewLayer: AVCaptureVideoPreviewLayer) {
        previewRotationObservation = nil
        captureRotationObservation = nil
        let coordinator = AVCaptureDevice.RotationCoordinator(device: camera, previewLayer: previewLayer)
        rotationCoordinator = coordinator

        previewRotationObservation = coordinator.observe(\.videoRotationAngleForHorizonLevelPreview,
                                                         options: [.initial, .new]) { [weak self] coordinator, _ in
            DispatchQueue.main.async {
                guard let connection = self?.previewLayer?.connection else { return }
                let angle = coordinator.videoRotationAngleForHorizonLevelPreview
                if connection.isVideoRotationAngleSupported(angle) {
                    connection.videoRotationAngle = angle
                }
            }
        }

        captureRotationObservation = coordinator.observe(\.videoRotationAngleForHorizonLevelCapture,
                                                         options: [.initial, .new]) { [weak self] coordinator, _ in
            DispatchQueue.main.async {
                self?.captureRotationAngle = coordinator.videoRotationAngleForHorizonLevelCapture
            }
        }
    }

    private func showMessage(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            self?.statusLabel.text = message
        }
    }

    @objc private func selectZoom(_ sender: UIButton) {
        guard !isUsingFrontCamera else { return }
        let factor = CGFloat(sender.tag) / 10
        sessionQueue.async { [weak self] in
            guard let self else { return }
            let camera: AVCaptureDevice
            let deviceZoom: CGFloat
            guard let main = self.mainCamera else { return }
            let multiplier = max(main.displayVideoZoomFactorMultiplier, 0.001)
            let virtualDeviceZoom = factor / multiplier
            let virtualZoomSupported = virtualDeviceZoom >= main.minAvailableVideoZoomFactor
                && virtualDeviceZoom <= main.maxAvailableVideoZoomFactor

            if virtualZoomSupported {
                if self.activeCamera?.uniqueID != main.uniqueID,
                   !self.switchCameraInput(to: main) {
                    self.showMessage("The main camera could not be selected.")
                    return
                }
                camera = main
                deviceZoom = virtualDeviceZoom
            } else if factor == 0.5, let ultraWide = self.ultraWideCamera {
                if self.activeCamera?.uniqueID != ultraWide.uniqueID,
                   !self.switchCameraInput(to: ultraWide) {
                    self.showMessage("The ultra-wide camera could not be selected.")
                    return
                }
                camera = ultraWide
                deviceZoom = 1
            } else {
                self.showMessage("That zoom level isn't available on this camera.")
                return
            }
            do {
                try camera.lockForConfiguration()
                camera.videoZoomFactor = deviceZoom
                camera.unlockForConfiguration()
                DispatchQueue.main.async {
                    self.selectedZoom = factor
                    self.updateZoomButtonAppearance()
                }
            } catch {
                self.showMessage("Zoom couldn't be changed.")
            }
        }
    }

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        guard let camera = activeCamera else { return }
        if gesture.state == .began {
            pinchStartFactor = camera.videoZoomFactor
            pinchDisplayMultiplier = camera.uniqueID == ultraWideCamera?.uniqueID
                ? 0.5
                : max(camera.displayVideoZoomFactorMultiplier, 0.001)
        } else if gesture.state == .changed {
            let factor = min(max(pinchStartFactor * gesture.scale, camera.minAvailableVideoZoomFactor),
                             camera.maxAvailableVideoZoomFactor)
            selectedZoom = factor * pinchDisplayMultiplier
            updateZoomButtonAppearance()
            sessionQueue.async {
                do {
                    try camera.lockForConfiguration()
                    camera.videoZoomFactor = factor
                    camera.unlockForConfiguration()
                } catch { }
            }
        }
    }

    private func switchCameraInput(to camera: AVCaptureDevice) -> Bool {
        guard let newInput = try? AVCaptureDeviceInput(device: camera) else { return false }
        session.beginConfiguration()
        let oldInput = session.inputs
            .compactMap { $0 as? AVCaptureDeviceInput }
            .first
        if let oldInput { session.removeInput(oldInput) }

        guard session.canAddInput(newInput) else {
            if let oldInput, session.canAddInput(oldInput) { session.addInput(oldInput) }
            session.commitConfiguration()
            return false
        }
        session.addInput(newInput)
        session.commitConfiguration()
        activeCamera = camera

        DispatchQueue.main.async { [weak self] in
            guard let self, let previewLayer = self.previewLayer else { return }
            self.configureRotation(for: camera, previewLayer: previewLayer)
            self.flashButton.isEnabled = camera.hasFlash
            self.flashButton.alpha = camera.hasFlash ? 1 : 0.45
            self.flashButton.isHidden = camera.position == .front
            self.flashEnabled = false
            self.flashButton.setImage(UIImage(systemName: "bolt.slash.fill"), for: .normal)
        }
        return true
    }

    @objc private func flipCamera() {
        guard let frontCamera, let mainCamera else { return }
        let destination = isUsingFrontCamera ? mainCamera : frontCamera
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard self.switchCameraInput(to: destination) else {
                self.showMessage("The camera couldn't be switched.")
                return
            }
            DispatchQueue.main.async {
                self.isUsingFrontCamera = destination.position == .front
                self.selectedZoom = 1
                self.zoomStack.isHidden = self.isUsingFrontCamera
                self.flashButton.isHidden = self.isUsingFrontCamera
                self.flashEnabled = false
                self.buildZoomButtons(self.backZoomFactors)
                self.view.setNeedsLayout()
            }
        }
    }

    @objc private func toggleFlash() {
        flashEnabled.toggle()
        flashButton.setImage(UIImage(systemName: flashEnabled ? "bolt.fill" : "bolt.slash.fill"), for: .normal)
    }

    @objc private func cancelCapture() {
        onCancel()
    }

    @objc private func takePhoto() {
        guard sessionReady else { return }
        if let connection = photoOutput.connection(with: .video),
           connection.isVideoRotationAngleSupported(captureRotationAngle) {
            connection.videoRotationAngle = captureRotationAngle
        }
        let settings = AVCapturePhotoSettings()
        if photoOutput.supportedFlashModes.contains(flashEnabled ? .on : .off) {
            settings.flashMode = flashEnabled ? .on : .off
        }
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        guard error == nil,
              let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else {
            showMessage("The photo couldn't be captured. Please try again.")
            return
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.onPhoto(image)
            self.onCancel()
        }
    }
}
