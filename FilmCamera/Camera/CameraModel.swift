import AVFoundation
import CoreImage
import ImageIO
import Photos
import UIKit

/// カメラの制御。映像の各フレームは `latestFrame` に置き、
/// 画面側（CameraPreview）がそれを取り出してフィルタをかけて表示する。
///
/// フラッシュモードのときだけ、LiDAR（なければデュアルカメラ）で距離を測り、
/// `latestDepth` に置く。距離が近いものほど強く光が当たったように見せるのに使う。
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
    /// 距離の測定が動いているか（フラッシュモードで LiDAR などが使えるとき）
    @Published private(set) var isDepthActive = false
    @Published var message: String?

    @Published var mode: LookMode {
        didSet {
            UserDefaults.standard.set(mode.rawValue, forKey: "mode")
            if mode.usesDepth != oldValue.usesDepth { updateDepth() }
        }
    }
    @Published var dateStamp: Bool {
        didSet { UserDefaults.standard.set(dateStamp, forKey: "dateStamp") }
    }

    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "camera.session")
    private let videoQueue = DispatchQueue(label: "camera.video")
    private let processingQueue = DispatchQueue(label: "camera.processing", qos: .userInitiated)
    private let videoOutput = AVCaptureVideoDataOutput()
    private let depthOutput = AVCaptureDepthDataOutput()
    private let photoOutput = AVCapturePhotoOutput()
    private var videoInput: AVCaptureDeviceInput?
    private var isConfigured = false
    /// 距離の出力をセッションに追加できたか（sessionQueue で触る）
    private var hasDepthOutput = false
    /// 今、距離を測る設定になっているか（sessionQueue で触る）
    private var isDepthOn = false

    /// 端末の傾きから、保存する写真の向きを決める（メインスレッドで使う）
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?

    /// 撮影中の写真の受け取り役（撮影が終わるまで保持する。sessionQueue で触る）
    private var inFlight: [Int64: PhotoCaptureProcessor] = [:]

    private let frameLock = NSLock()
    private var _latestFrame: CIImage?
    private var _latestDepth: CIImage?
    /// 距離の画像を接続側で縦向きにできたか（できなければ自分で回す）
    private var _depthRotatedByConnection = false

    /// 最新の映像フレーム（縦向き・インカメラは左右反転済み）
    var latestFrame: CIImage? {
        frameLock.lock()
        defer { frameLock.unlock() }
        return _latestFrame
    }

    /// 最新の距離（メートル）。映像と同じ縦向き。距離を測っていないときは nil
    var latestDepth: CIImage? {
        frameLock.lock()
        defer { frameLock.unlock() }
        return _latestDepth
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
        let wantDepth = mode.usesDepth
        sessionQueue.async {
            if !self.isConfigured {
                self.isConfigured = self.configure(position: position, wantDepth: wantDepth)
            }
            guard self.isConfigured else {
                DispatchQueue.main.async { self.status = .unavailable }
                return
            }
            self.refreshPhotoDepthDelivery()
            if !self.session.isRunning { self.session.startRunning() }
            DispatchQueue.main.async { self.status = .running }
        }
    }

    /// sessionQueue で呼ぶ
    private func configure(position: AVCaptureDevice.Position, wantDepth: Bool) -> Bool {
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

        depthOutput.isFilteringEnabled = true   // 穴やノイズをならした距離をもらう
        depthOutput.alwaysDiscardsLateDepthData = true
        depthOutput.setDelegate(self, callbackQueue: videoQueue)
        if session.canAddOutput(depthOutput) {
            session.addOutput(depthOutput)
            hasDepthOutput = true
        }

        applyFormat(for: device, wantDepth: wantDepth)
        setUpConnections(for: device)
        return true
    }

    /// 写真用の最高画質の設定と、距離を測る設定を切り替える。
    /// 距離を測れる設定は写真の最大解像度が下がる機種があるため、フラッシュモードのときだけ使う。
    /// sessionQueue の beginConfiguration〜commitConfiguration の中で呼ぶ
    private func applyFormat(for device: AVCaptureDevice, wantDepth: Bool) {
        var depthOn = false
        if wantDepth, hasDepthOutput, let format = Self.bestDepthFormat(of: device),
           let depthFormat = Self.bestDepthDataFormat(of: format) {
            do {
                try device.lockForConfiguration()
                device.activeFormat = format
                device.activeDepthDataFormat = depthFormat
                device.unlockForConfiguration()
                depthOn = true
            } catch {
                depthOn = false
            }
        }
        if !depthOn {
            session.sessionPreset = .photo
        }

        isDepthOn = depthOn
        depthOutput.connection(with: .depthData)?.isEnabled = depthOn
        refreshPhotoDepthDelivery()
        if !depthOn {
            frameLock.lock()
            _latestDepth = nil
            frameLock.unlock()
        }
        DispatchQueue.main.async { self.isDepthActive = depthOn }
    }

    /// 写真にも距離を付けるか。対応しているかどうかは設定を変えた後に決まるので、
    /// 設定の確定後にもう一度呼ぶ（sessionQueue で呼ぶ）
    private func refreshPhotoDepthDelivery() {
        photoOutput.isDepthDataDeliveryEnabled = isDepthOn && photoOutput.isDepthDataDeliverySupported
    }

    /// 距離を測れる設定のうち、写真がいちばん大きく撮れるもの
    private static func bestDepthFormat(of device: AVCaptureDevice) -> AVCaptureDevice.Format? {
        func photoArea(_ f: AVCaptureDevice.Format) -> Int32 {
            f.supportedMaxPhotoDimensions.map { $0.width * $0.height }.max() ?? 0
        }
        func videoArea(_ f: AVCaptureDevice.Format) -> Int32 {
            let d = CMVideoFormatDescriptionGetDimensions(f.formatDescription)
            return d.width * d.height
        }
        let candidates = device.formats.filter { format in
            !format.supportedDepthDataFormats.isEmpty
                && format.videoSupportedFrameRateRanges.contains { $0.maxFrameRate >= 30 }
                // プレビューが重くならないよう、映像は 1920×1440 程度までにする
                && videoArea(format) <= 1920 * 1440
        }
        return candidates.max { a, b in
            (photoArea(a), videoArea(a)) < (photoArea(b), videoArea(b))
        }
    }

    /// 距離データの形式のうち、いちばん細かいもの（距離そのものの形式を優先）
    private static func bestDepthDataFormat(of format: AVCaptureDevice.Format) -> AVCaptureDevice.Format? {
        let depthTypes: Set<OSType> = [kCVPixelFormatType_DepthFloat32, kCVPixelFormatType_DepthFloat16]
        func width(_ f: AVCaptureDevice.Format) -> Int32 {
            CMVideoFormatDescriptionGetDimensions(f.formatDescription).width
        }
        func isDepth(_ f: AVCaptureDevice.Format) -> Bool {
            depthTypes.contains(CMFormatDescriptionGetMediaSubType(f.formatDescription))
        }
        let formats = format.supportedDepthDataFormats
        return formats.filter(isDepth).max { width($0) < width($1) }
            ?? formats.max { width($0) < width($1) }
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

        var depthRotated = false
        if let connection = depthOutput.connection(with: .depthData),
           connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
            depthRotated = true
        }
        frameLock.lock()
        _depthRotatedByConnection = depthRotated
        frameLock.unlock()

        DispatchQueue.main.async {
            self.rotationCoordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
        }
    }

    /// 背面は距離を測れるカメラを優先する（LiDAR → デュアルカメラ → ふつうの広角）
    private static func camera(at position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        let types: [AVCaptureDevice.DeviceType] = position == .back
            ? [.builtInLiDARDepthCamera, .builtInDualWideCamera, .builtInDualCamera, .builtInWideAngleCamera]
            : [.builtInWideAngleCamera]
        for type in types {
            if let device = AVCaptureDevice.default(type, for: .video, position: position) {
                return device
            }
        }
        return nil
    }

    // MARK: - モードとカメラの切り替え

    private func updateDepth() {
        guard isConfigured else { return }
        let wantDepth = mode.usesDepth
        sessionQueue.async {
            guard let device = self.videoInput?.device else { return }
            self.session.beginConfiguration()
            self.applyFormat(for: device, wantDepth: wantDepth)
            self.setUpConnections(for: device)
            self.session.commitConfiguration()
            self.refreshPhotoDepthDelivery()
        }
    }

    func switchCamera() {
        guard status == .running else { return }
        let next: AVCaptureDevice.Position = position == .back ? .front : .back
        let wantDepth = mode.usesDepth
        sessionQueue.async {
            guard let device = Self.camera(at: next),
                  let input = try? AVCaptureDeviceInput(device: device) else { return }
            self.session.beginConfiguration()
            // 前の設定のままだと新しいカメラで使えないことがあるので、いったん標準に戻す
            self.session.sessionPreset = .photo
            if let current = self.videoInput { self.session.removeInput(current) }
            if self.session.canAddInput(input) {
                self.session.addInput(input)
                self.videoInput = input
            } else if let current = self.videoInput {
                self.session.addInput(current)
            }
            let active = self.videoInput?.device ?? device
            self.applyFormat(for: active, wantDepth: wantDepth)
            self.setUpConnections(for: active)
            self.session.commitConfiguration()
            self.refreshPhotoDepthDelivery()
            let now = active.position
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
            if options.mode.usesDepth && self.photoOutput.isDepthDataDeliveryEnabled {
                settings.isDepthDataDeliveryEnabled = true
                settings.embedsDepthDataInPhoto = false
            }
            let processor = PhotoCaptureProcessor { [weak self] data, depth in
                self?.finishCapture(data: data, depth: depth, options: options, id: settings.uniqueID)
            }
            self.inFlight[settings.uniqueID] = processor
            self.photoOutput.capturePhoto(with: settings, delegate: processor)
        }
    }

    private func finishCapture(data: Data?, depth: CIImage?, options: LookOptions, id: Int64) {
        sessionQueue.async { self.inFlight[id] = nil }

        guard let data,
              let image = CIImage(data: data, options: [.applyOrientationProperty: true]) else {
            DispatchQueue.main.async {
                self.isSaving = false
                self.message = "撮影に失敗しました"
            }
            return
        }

        var options = options
        options.depth = depth

        processingQueue.async {
            let output = LookRenderer.apply(image, options: options)
            let colorSpace = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
            let quality = kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption
            guard let jpeg = self.ciContext.jpegRepresentation(
                of: output, colorSpace: colorSpace, options: [quality: 0.97]) else {
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

    /// 距離データを、メートル単位の 1 チャンネル画像にする（色の変換はかけない）
    static func depthImage(from depthData: AVDepthData) -> CIImage {
        let converted = depthData.depthDataType == kCVPixelFormatType_DepthFloat32
            ? depthData
            : depthData.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32)
        return CIImage(cvPixelBuffer: converted.depthDataMap, options: [.colorSpace: NSNull()])
    }
}

// MARK: - 映像フレームと距離の受け取り

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

extension CameraModel: AVCaptureDepthDataOutputDelegate {
    func depthDataOutput(_ output: AVCaptureDepthDataOutput,
                         didOutput depthData: AVDepthData,
                         timestamp: CMTime,
                         connection: AVCaptureConnection) {
        var depth = Self.depthImage(from: depthData)
        frameLock.lock()
        let rotated = _depthRotatedByConnection
        frameLock.unlock()
        if !rotated {
            // センサーの向き（横）のままなので、映像に合わせて縦向きに回す
            depth = depth.oriented(.right)
        }
        frameLock.lock()
        _latestDepth = depth
        frameLock.unlock()
    }
}

// MARK: - 写真の受け取り役

private final class PhotoCaptureProcessor: NSObject, AVCapturePhotoCaptureDelegate {
    private let completion: (Data?, CIImage?) -> Void

    init(completion: @escaping (Data?, CIImage?) -> Void) {
        self.completion = completion
    }

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        guard error == nil else {
            completion(nil, nil)
            return
        }
        // 写真と同じ向きにそろえた距離
        var depth: CIImage?
        if var depthData = photo.depthData {
            if let raw = photo.metadata[kCGImagePropertyOrientation as String] as? UInt32,
               let orientation = CGImagePropertyOrientation(rawValue: raw) {
                depthData = depthData.applyingExifOrientation(orientation)
            }
            depth = CameraModel.depthImage(from: depthData)
        }
        completion(photo.fileDataRepresentation(), depth)
    }
}
