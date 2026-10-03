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
    private var _subjectDistance: CGFloat?
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

    /// 画面中央にあるもの（主な被写体）までの距離（メートル）。フラッシュの強さをこの距離に合わせる
    var subjectDistance: CGFloat? {
        frameLock.lock()
        defer { frameLock.unlock() }
        return _subjectDistance
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

        guard let device = Self.camera(at: position, wantDepth: wantDepth),
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

        applyFormat(for: device, wantDepth: wantDepth)
        setUpConnections(for: device)
        return true
    }

    /// 写真用の最高画質の設定と、距離を測る設定を切り替える。
    /// 距離を測れる設定は写真の最大解像度が下がる（4800万画素で撮れない）ため、フラッシュモードのときだけ使う。
    /// sessionQueue の beginConfiguration〜commitConfiguration の中で呼ぶ
    private func applyFormat(for device: AVCaptureDevice, wantDepth: Bool) {
        var depthOn = false
        if wantDepth {
            if !hasDepthOutput, session.canAddOutput(depthOutput) {
                session.addOutput(depthOutput)
                hasDepthOutput = true
            }
            if hasDepthOutput, let format = Self.bestDepthFormat(of: device),
               let depthFormat = Self.bestDepthDataFormat(of: format) {
                depthOn = setFormat(format, depthFormat: depthFormat, on: device)
            }
        }
        if !depthOn {
            if hasDepthOutput {
                session.removeOutput(depthOutput)
                hasDepthOutput = false
            }
            // 写真がいちばん大きく撮れる設定を自分で選ぶ（標準の設定だと 1200万画素になる機種がある）
            let photoFormatSet = Self.bestPhotoFormat(of: device)
                .map { setFormat($0, depthFormat: nil, on: device) } ?? false
            if !photoFormatSet {
                session.sessionPreset = .photo
            }
        }

        isDepthOn = depthOn
        depthOutput.connection(with: .depthData)?.isEnabled = depthOn
        refreshPhotoDepthDelivery()
        if !depthOn {
            frameLock.lock()
            _latestDepth = nil
            _subjectDistance = nil
            frameLock.unlock()
        }
        DispatchQueue.main.async { self.isDepthActive = depthOn }
    }

    private func setFormat(_ format: AVCaptureDevice.Format, depthFormat: AVCaptureDevice.Format?,
                           on device: AVCaptureDevice) -> Bool {
        do {
            try device.lockForConfiguration()
            device.activeFormat = format
            if let depthFormat { device.activeDepthDataFormat = depthFormat }
            device.unlockForConfiguration()
            return true
        } catch {
            return false
        }
    }

    /// 写真がいちばん大きく撮れる設定（映像は 30fps 以上・8 ビットのもの）。
    /// 同じ大きさなら、プレビューの映像が 1920×1440 に近いものを選ぶ
    private static func bestPhotoFormat(of device: AVCaptureDevice) -> AVCaptureDevice.Format? {
        let target: Int32 = 1920 * 1440
        let eightBit: Set<OSType> = [kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
                                     kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange]
        let candidates = device.formats.filter { format in
            eightBit.contains(CMFormatDescriptionGetMediaSubType(format.formatDescription))
                && format.videoSupportedFrameRateRanges.contains { $0.maxFrameRate >= 30 }
        }
        return candidates.max { a, b in
            (photoArea(a), -abs(videoArea(a) - target)) < (photoArea(b), -abs(videoArea(b) - target))
        }
    }

    private static func photoArea(_ f: AVCaptureDevice.Format) -> Int32 {
        f.supportedMaxPhotoDimensions.map { $0.width * $0.height }.max() ?? 0
    }

    private static func videoArea(_ f: AVCaptureDevice.Format) -> Int32 {
        let d = CMVideoFormatDescriptionGetDimensions(f.formatDescription)
        return d.width * d.height
    }

    /// 写真にも距離を付けるか。対応しているかどうかは設定を変えた後に決まるので、
    /// 設定の確定後にもう一度呼ぶ（sessionQueue で呼ぶ）
    private func refreshPhotoDepthDelivery() {
        photoOutput.isDepthDataDeliveryEnabled = isDepthOn && photoOutput.isDepthDataDeliverySupported
    }

    /// 距離を測れる設定のうち、写真がいちばん大きく撮れるもの
    private static func bestDepthFormat(of device: AVCaptureDevice) -> AVCaptureDevice.Format? {
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

    /// 距離を使うときの背面は、距離を測れるカメラを優先する（LiDAR → デュアルカメラ → 広角）。
    /// それ以外はふつうの広角カメラ（4800万画素で撮れるのはこちら）
    private static func camera(at position: AVCaptureDevice.Position, wantDepth: Bool) -> AVCaptureDevice? {
        let types: [AVCaptureDevice.DeviceType] = position == .back && wantDepth
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
            guard let current = self.videoInput?.device else { return }
            self.session.beginConfiguration()
            let device = self.useCamera(at: current.position, wantDepth: wantDepth) ?? current
            self.applyFormat(for: device, wantDepth: wantDepth)
            self.setUpConnections(for: device)
            self.session.commitConfiguration()
            self.refreshPhotoDepthDelivery()
        }
    }

    /// 使うカメラを切り替える（同じなら何もしない）。切り替えたカメラ、または今のカメラを返す。
    /// sessionQueue の beginConfiguration〜commitConfiguration の中で呼ぶ
    private func useCamera(at position: AVCaptureDevice.Position, wantDepth: Bool) -> AVCaptureDevice? {
        guard let device = Self.camera(at: position, wantDepth: wantDepth) else {
            return videoInput?.device
        }
        if device.uniqueID == videoInput?.device.uniqueID { return device }
        guard let input = try? AVCaptureDeviceInput(device: device) else { return videoInput?.device }
        // 前の設定のままだと新しいカメラで使えないことがあるので、いったん標準に戻す
        session.sessionPreset = .photo
        if let current = videoInput { session.removeInput(current) }
        if session.canAddInput(input) {
            session.addInput(input)
            videoInput = input
        } else if let current = videoInput {
            session.addInput(current)
        }
        return videoInput?.device
    }

    func switchCamera() {
        guard status == .running else { return }
        let next: AVCaptureDevice.Position = position == .back ? .front : .back
        let wantDepth = mode.usesDepth
        sessionQueue.async {
            self.session.beginConfiguration()
            guard let active = self.useCamera(at: next, wantDepth: wantDepth) else {
                self.session.commitConfiguration()
                return
            }
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

        var options = LookOptions(mode: mode, dateStamp: dateStamp)
        let angle = rotationCoordinator?.videoRotationAngleForHorizonLevelCapture ?? 90
        let mirrored = position == .front

        // フラッシュ：距離を測れる設定だと 1200万画素でしか撮れないので、
        // 直前のプレビューで測った距離を借りて、撮影の瞬間だけ 4800万画素の設定に切り替える
        let borrowDepth = options.mode.usesDepth && isDepthActive && position == .back
        if borrowDepth, let depth = latestDepth {
            // プレビューは縦向き（90°）。写真の向き（angle）に合わせて回す
            let radians = -(angle - 90) * .pi / 180
            options.depth = depth.transformed(by: CGAffineTransform(rotationAngle: radians))
            options.subjectDistance = subjectDistance
        }

        sessionQueue.async {
            if borrowDepth { self.switchToFullResolutionForCapture() }
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
            if options.mode.usesDepth && !borrowDepth && self.photoOutput.isDepthDataDeliveryEnabled {
                settings.isDepthDataDeliveryEnabled = true
                settings.embedsDepthDataInPhoto = false
            }
            let processor = PhotoCaptureProcessor { [weak self] data, depth, distance in
                self?.finishCapture(data: data, depth: depth, distance: distance,
                                    options: options, id: settings.uniqueID)
                if borrowDepth {
                    // 撮り終わったら距離を測る設定に戻す（その間にモードが変わっていれば戻さない）
                    DispatchQueue.main.async {
                        if self?.mode.usesDepth == true { self?.updateDepth() }
                    }
                }
            }
            self.inFlight[settings.uniqueID] = processor
            self.photoOutput.capturePhoto(with: settings, delegate: processor)
        }
    }

    /// 背面の広角カメラ・最大解像度の設定に切り替え、露出が落ち着くまで少し待つ（sessionQueue で呼ぶ）
    private func switchToFullResolutionForCapture() {
        session.beginConfiguration()
        if let device = useCamera(at: .back, wantDepth: false) {
            applyFormat(for: device, wantDepth: false)
            setUpConnections(for: device)
        }
        session.commitConfiguration()
        refreshPhotoDepthDelivery()
        guard let device = videoInput?.device else { return }
        let deadline = Date().addingTimeInterval(1.0)
        Thread.sleep(forTimeInterval: 0.15)
        while device.isAdjustingExposure && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
    }

    private func finishCapture(data: Data?, depth: CIImage?, distance: CGFloat?,
                               options: LookOptions, id: Int64) {
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
        if let depth {
            options.depth = depth
            options.subjectDistance = distance
        }

        processingQueue.async {
            // 撮影日時やカメラ・レンズの情報を残す（向きは適用済みなので「そのまま」にする）
            var properties = image.properties
            properties[kCGImagePropertyOrientation as String] = 1
            let output = LookRenderer.resizeForSaving(LookRenderer.apply(image, options: options))
                .settingProperties(properties)
            // 10 ビットの HEIF で保存する（JPEG の 8 ビットより階調がなめらかで、ファイルも小さい）
            let p3 = CGColorSpace(name: CGColorSpace.displayP3)!
            let quality = kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption
            let file: (data: Data, type: String)
            if let heif = try? self.ciContext.heif10Representation(of: output, colorSpace: p3,
                                                                   options: [quality: 0.85]) {
                file = (heif, "public.heic")
            } else if let jpeg = self.ciContext.jpegRepresentation(of: output, colorSpace: p3,
                                                                    options: [quality: 0.90]) {
                file = (jpeg, "public.jpeg")
            } else {
                DispatchQueue.main.async {
                    self.isSaving = false
                    self.message = "画像の作成に失敗しました"
                }
                return
            }
            let thumbnail = self.previewImage(of: output)
            DispatchQueue.main.async {
                self.lastPhoto = thumbnail
                self.isSaving = false
            }
            self.saveToLibrary(file.data, type: file.type)
        }
    }

    /// 撮った写真を画面で見る用に縮小する（大きな写真をそのまま読み込まないため）
    private func previewImage(of image: CIImage) -> UIImage? {
        let long = max(image.extent.width, image.extent.height)
        guard long > 0 else { return nil }
        let scale = min(1, 2400 / long)
        let small = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cg = ciContext.createCGImage(small, from: small.extent,
                                               format: .RGBA8,
                                               colorSpace: CGColorSpace(name: CGColorSpace.displayP3)) else {
            return nil
        }
        return UIImage(cgImage: cg)
    }

    private func saveToLibrary(_ data: Data, type: String) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async {
                    self.message = "写真への保存が許可されていません（設定 → フィルムカメラ → 写真）"
                }
                return
            }
            PHPhotoLibrary.shared().performChanges({
                let request = PHAssetCreationRequest.forAsset()
                let options = PHAssetResourceCreationOptions()
                options.uniformTypeIdentifier = type
                request.addResource(with: .photo, data: data, options: options)
            }) { success, _ in
                if !success {
                    DispatchQueue.main.async { self.message = "写真の保存に失敗しました" }
                }
            }
        }
    }

    /// 距離データを、メートル単位の 1 チャンネル画像と、画面中央の被写体までの距離にする
    static func depthImage(from depthData: AVDepthData) -> (image: CIImage, subject: CGFloat?) {
        let converted = depthData.depthDataType == kCVPixelFormatType_DepthFloat32
            ? depthData
            : depthData.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32)
        let map = converted.depthDataMap
        let image = CIImage(cvPixelBuffer: map, options: [.colorSpace: NSNull()])
        return (image, centerDistance(of: map))
    }

    /// 画面中央（縦横それぞれ真ん中 40%）で測れた距離の中央値。
    /// カメラのフラッシュが被写体に合わせて光の強さを決めるのと同じ考え方
    private static func centerDistance(of map: CVPixelBuffer) -> CGFloat? {
        CVPixelBufferLockBaseAddress(map, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(map, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(map) else { return nil }
        let width = CVPixelBufferGetWidth(map)
        let height = CVPixelBufferGetHeight(map)
        let rowBytes = CVPixelBufferGetBytesPerRow(map)
        var values: [Float] = []
        values.reserveCapacity(width * height / 6)
        for y in (height * 3 / 10)..<(height * 7 / 10) {
            let row = base.advanced(by: y * rowBytes).assumingMemoryBound(to: Float32.self)
            for x in (width * 3 / 10)..<(width * 7 / 10) {
                let v = row[x]
                if v.isFinite && v > 0.1 { values.append(v) }
            }
        }
        guard values.count > 10 else { return nil }
        values.sort()
        let median = CGFloat(values[values.count / 2])
        return min(max(median, 0.4), 4.0)
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
        let measured = Self.depthImage(from: depthData)
        var depth = measured.image
        frameLock.lock()
        let rotated = _depthRotatedByConnection
        frameLock.unlock()
        if !rotated {
            // センサーの向き（横）のままなので、映像に合わせて縦向きに回す
            depth = depth.oriented(.right)
        }
        frameLock.lock()
        _latestDepth = depth
        if let subject = measured.subject {
            // 毎コマ少しずつ追いかけ、明るさがちらつかないようにする
            _subjectDistance = _subjectDistance.map { $0 * 0.8 + subject * 0.2 } ?? subject
        }
        frameLock.unlock()
    }
}

// MARK: - 写真の受け取り役

private final class PhotoCaptureProcessor: NSObject, AVCapturePhotoCaptureDelegate {
    private let completion: (Data?, CIImage?, CGFloat?) -> Void

    init(completion: @escaping (Data?, CIImage?, CGFloat?) -> Void) {
        self.completion = completion
    }

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        guard error == nil else {
            completion(nil, nil, nil)
            return
        }
        // 写真と同じ向きにそろえた距離
        var depth: CIImage?
        var distance: CGFloat?
        if var depthData = photo.depthData {
            if let raw = photo.metadata[kCGImagePropertyOrientation as String] as? UInt32,
               let orientation = CGImagePropertyOrientation(rawValue: raw) {
                depthData = depthData.applyingExifOrientation(orientation)
            }
            let measured = CameraModel.depthImage(from: depthData)
            depth = measured.image
            distance = measured.subject
        }
        completion(photo.fileDataRepresentation(), depth, distance)
    }
}
