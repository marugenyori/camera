import AVFoundation
import CoreImage
import ImageIO
import Photos
import UIKit

/// カメラの制御。映像の各フレームは `latestFrame` に置き、
/// 画面側（CameraPreview）がそれを取り出してフィルタをかけて表示する。
final class CameraModel: NSObject, ObservableObject {

    enum Status {
        case idle
        case running
        case denied
        case unavailable
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var position: AVCaptureDevice.Position = .back
    @Published private(set) var lastPhoto: UIImage?
    @Published private(set) var isSaving = false
    @Published private(set) var shotCount = 0
    @Published var message: String?

    @Published var mode: LookMode {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: "mode") }
    }
    @Published var dateStamp: Bool {
        didSet { UserDefaults.standard.set(dateStamp, forKey: "dateStamp") }
    }

    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "camera.session")
    private let videoQueue = DispatchQueue(label: "camera.video")
    private let processingQueue = DispatchQueue(label: "camera.processing", qos: .userInitiated)
    private let videoOutput = AVCaptureVideoDataOutput()
    private let photoOutput = AVCapturePhotoOutput()
    private var videoInput: AVCaptureDeviceInput?
    private var isConfigured = false

    /// 端末の傾きから、保存する写真の向きを決める（メインスレッドで使う）
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?

    /// 撮影中の写真の受け取り役（撮影が終わるまで保持する。sessionQueue で触る）
    private var inFlight: [Int64: PhotoCaptureProcessor] = [:]

    private let frameLock = NSLock()
    private var _latestFrame: CIImage?

    /// 最新の映像フレーム（縦向き・インカメラは左右反転済み）
    var latestFrame: CIImage? {
        frameLock.lock()
        defer { frameLock.unlock() }
        return _latestFrame
    }

    private let ciContext = CIContext(options: [.cacheIntermediates: false])

    override init() {
        let defaults = UserDefaults.standard
        mode = LookMode(rawValue: defaults.string(forKey: "mode") ?? "") ?? .film
        dateStamp = defaults.bool(forKey: "dateStamp")
        super.init()
    }

    // MARK: - 起動と停止

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            startSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        self.startSession()
                    } else {
                        self.status = .denied
                    }
                }
            }
        default:
            status = .denied
        }
    }

    func stop() {
        sessionQueue.async {
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    private func startSession() {
        let position = self.position
        sessionQueue.async {
            if !self.isConfigured {
                self.isConfigured = self.configure(position: position)
            }
            guard self.isConfigured else {
                DispatchQueue.main.async { self.status = .unavailable }
                return
            }
            if !self.session.isRunning { self.session.startRunning() }
            DispatchQueue.main.async { self.status = .running }
        }
    }

    /// sessionQueue で呼ぶ
    private func configure(position: AVCaptureDevice.Position) -> Bool {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.sessionPreset = .photo

        guard let device = Self.camera(at: position),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return false }
        session.addInput(input)
        videoInput = input

        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
        guard session.canAddOutput(videoOutput), session.canAddOutput(photoOutput) else { return false }
        session.addOutput(videoOutput)
        session.addOutput(photoOutput)

        setUpConnections(for: device)
        return true
    }

    /// sessionQueue で呼ぶ
    private func setUpConnections(for device: AVCaptureDevice) {
        // 写真はそのカメラの最大解像度・画質優先で撮る（初期値だと小さめになる）
        if let largest = device.activeFormat.supportedMaxPhotoDimensions
            .max(by: { $0.width * $0.height < $1.width * $1.height }) {
            photoOutput.maxPhotoDimensions = largest
        }
        photoOutput.maxPhotoQualityPrioritization = .quality

        if let connection = videoOutput.connection(with: .video) {
            // 画面は縦向き固定なので、映像も縦向きでもらう
            if connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = device.position == .front
            }
        }
        DispatchQueue.main.async {
            self.rotationCoordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
        }
    }

    private static func camera(at position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
    }

    // MARK: - カメラの切り替え

    func switchCamera() {
        guard status == .running else { return }
        let next: AVCaptureDevice.Position = position == .back ? .front : .back
        sessionQueue.async {
            guard let device = Self.camera(at: next),
                  let input = try? AVCaptureDeviceInput(device: device) else { return }
            self.session.beginConfiguration()
            if let current = self.videoInput { self.session.removeInput(current) }
            if self.session.canAddInput(input) {
                self.session.addInput(input)
                self.videoInput = input
            } else if let current = self.videoInput {
                self.session.addInput(current)
            }
            self.setUpConnections(for: self.videoInput?.device ?? device)
            self.session.commitConfiguration()
            let now = self.videoInput?.device.position ?? next
            DispatchQueue.main.async { self.position = now }
        }
    }

    // MARK: - 撮影

    func capture() {
        guard status == .running, !isSaving else { return }
        isSaving = true
        shotCount += 1

        let options = LookOptions(mode: mode, dateStamp: dateStamp)
        let angle = rotationCoordinator?.videoRotationAngleForHorizonLevelCapture ?? 90
        let mirrored = position == .front

        sessionQueue.async {
            if let connection = self.photoOutput.connection(with: .video) {
                if connection.isVideoRotationAngleSupported(angle) {
                    connection.videoRotationAngle = angle
                }
                if connection.isVideoMirroringSupported {
                    connection.automaticallyAdjustsVideoMirroring = false
                    connection.isVideoMirrored = mirrored
                }
            }
            let settings = AVCapturePhotoSettings()
            settings.maxPhotoDimensions = self.photoOutput.maxPhotoDimensions
            settings.photoQualityPrioritization = .quality
            let processor = PhotoCaptureProcessor { [weak self] data in
                self?.finishCapture(data: data, options: options, id: settings.uniqueID)
            }
            self.inFlight[settings.uniqueID] = processor
            self.photoOutput.capturePhoto(with: settings, delegate: processor)
        }
    }

    private func finishCapture(data: Data?, options: LookOptions, id: Int64) {
        sessionQueue.async { self.inFlight[id] = nil }

        guard let data,
              let image = CIImage(data: data, options: [.applyOrientationProperty: true]) else {
            DispatchQueue.main.async {
                self.isSaving = false
                self.message = "撮影に失敗しました"
            }
            return
        }

        processingQueue.async {
            let output = LookRenderer.apply(image, options: options)
            let colorSpace = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
            let quality = kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption
            guard let jpeg = self.ciContext.jpegRepresentation(
                of: output, colorSpace: colorSpace, options: [quality: 0.92]) else {
                DispatchQueue.main.async {
                    self.isSaving = false
                    self.message = "画像の作成に失敗しました"
                }
                return
            }
            let thumbnail = UIImage(data: jpeg)
            DispatchQueue.main.async {
                self.lastPhoto = thumbnail
                self.isSaving = false
            }
            self.saveToLibrary(jpeg)
        }
    }

    private func saveToLibrary(_ jpeg: Data) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async {
                    self.message = "写真への保存が許可されていません（設定 → フィルムカメラ → 写真）"
                }
                return
            }
            PHPhotoLibrary.shared().performChanges({
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, data: jpeg, options: nil)
            }) { success, _ in
                if !success {
                    DispatchQueue.main.async { self.message = "写真の保存に失敗しました" }
                }
            }
        }
    }
}

// MARK: - 映像フレームの受け取り

extension CameraModel: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let frame = CIImage(cvPixelBuffer: pixelBuffer)
        frameLock.lock()
        _latestFrame = frame
        frameLock.unlock()
    }
}

// MARK: - 写真の受け取り役

private final class PhotoCaptureProcessor: NSObject, AVCapturePhotoCaptureDelegate {
    private let completion: (Data?) -> Void

    init(completion: @escaping (Data?) -> Void) {
        self.completion = completion
    }

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        completion(error == nil ? photo.fileDataRepresentation() : nil)
    }
}
