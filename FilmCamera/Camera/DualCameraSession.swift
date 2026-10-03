import AVFoundation
import CoreImage

/// 外カメラと内カメラを同時に動かす（AVCaptureMultiCamSession）。
/// ふだんの撮影とは別のセッションで、「前後同時」をオンにしている間だけ使う。
/// すべて CameraModel の sessionQueue から呼ぶ
final class DualCameraSession: NSObject {
    static var isSupported: Bool { AVCaptureMultiCamSession.isMultiCamSupported }

    /// 映像のコマが届いたとき（back = 外カメラ）。dualQueue から呼ばれる
    var onFrame: ((CIImage, _ isBack: Bool) -> Void)?

    private let session = AVCaptureMultiCamSession()
    private let queue = DispatchQueue(label: "camera.dual")
    private let backVideo = AVCaptureVideoDataOutput()
    private let frontVideo = AVCaptureVideoDataOutput()
    private let backPhoto = AVCapturePhotoOutput()
    private let frontPhoto = AVCapturePhotoOutput()
    private var isConfigured = false
    private var inFlight: [DualPhotoProcessor] = []

    func start() -> Bool {
        if !isConfigured { isConfigured = configure() }
        guard isConfigured else { return false }
        if !session.isRunning { session.startRunning() }
        return true
    }

    /// 止めて、カメラを手放す（ふだんのセッションがすぐにカメラを使えるように）
    func stop() {
        if session.isRunning { session.stopRunning() }
        guard isConfigured else { return }
        session.beginConfiguration()
        for connection in session.connections { session.removeConnection(connection) }
        for input in session.inputs { session.removeInput(input) }
        for output in session.outputs { session.removeOutput(output) }
        session.commitConfiguration()
        isConfigured = false
    }

    // MARK: - 準備

    private func configure() -> Bool {
        guard Self.isSupported,
              let back = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let front = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
        else { return false }

        // 2 台同時はカメラへの負荷に上限があるので、映像が小さめの設定から順に試す
        for maxVideoArea: Int32 in [1920 * 1440, 1440 * 1080, 1280 * 960] {
            if setUp(back: back, front: front, maxVideoArea: maxVideoArea) { return true }
        }
        return false
    }

    private func setUp(back: AVCaptureDevice, front: AVCaptureDevice, maxVideoArea: Int32) -> Bool {
        session.beginConfiguration()
        for connection in session.connections { session.removeConnection(connection) }
        for input in session.inputs { session.removeInput(input) }
        for output in session.outputs { session.removeOutput(output) }

        guard let backFormat = Self.format(of: back, maxVideoArea: maxVideoArea),
              let frontFormat = Self.format(of: front, maxVideoArea: maxVideoArea),
              setFormat(backFormat, on: back), setFormat(frontFormat, on: front),
              add(device: back, video: backVideo, photo: backPhoto, mirrored: false),
              add(device: front, video: frontVideo, photo: frontPhoto, mirrored: true)
        else {
            session.commitConfiguration()
            return false
        }
        session.commitConfiguration()
        return session.hardwareCost <= 1.0
    }

    /// 2 台同時に使える設定のうち、映像が上限以下で、写真がいちばん大きく撮れるもの
    private static func format(of device: AVCaptureDevice, maxVideoArea: Int32) -> AVCaptureDevice.Format? {
        let eightBit: Set<OSType> = [kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
                                     kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange]
        func videoArea(_ f: AVCaptureDevice.Format) -> Int32 {
            let d = CMVideoFormatDescriptionGetDimensions(f.formatDescription)
            return d.width * d.height
        }
        func photoArea(_ f: AVCaptureDevice.Format) -> Int32 {
            f.supportedMaxPhotoDimensions.map { $0.width * $0.height }.max() ?? 0
        }
        func isFourByThree(_ f: AVCaptureDevice.Format) -> Bool {
            let d = CMVideoFormatDescriptionGetDimensions(f.formatDescription)
            return abs(Double(d.width) / Double(d.height) - 4.0 / 3.0) < 0.01
        }
        return device.formats
            .filter {
                $0.isMultiCamSupported
                    && eightBit.contains(CMFormatDescriptionGetMediaSubType($0.formatDescription))
                    && $0.videoSupportedFrameRateRanges.contains { $0.maxFrameRate >= 30 }
                    && isFourByThree($0)
                    && videoArea($0) <= maxVideoArea
            }
            .max { (photoArea($0), videoArea($0)) < (photoArea($1), videoArea($1)) }
    }

    private func setFormat(_ format: AVCaptureDevice.Format, on device: AVCaptureDevice) -> Bool {
        guard (try? device.lockForConfiguration()) != nil else { return false }
        device.activeFormat = format
        device.unlockForConfiguration()
        return true
    }

    /// カメラ 1 台分の入力・映像・写真を、つなぎ先を指定して追加する
    private func add(device: AVCaptureDevice, video: AVCaptureVideoDataOutput,
                     photo: AVCapturePhotoOutput, mirrored: Bool) -> Bool {
        guard let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return false }
        session.addInputWithNoConnections(input)

        video.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        video.alwaysDiscardsLateVideoFrames = true
        video.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(video), session.canAddOutput(photo) else { return false }
        session.addOutputWithNoConnections(video)
        session.addOutputWithNoConnections(photo)

        guard let port = input.ports(for: .video, sourceDeviceType: device.deviceType,
                                     sourceDevicePosition: device.position).first else { return false }
        let videoConnection = AVCaptureConnection(inputPorts: [port], output: video)
        let photoConnection = AVCaptureConnection(inputPorts: [port], output: photo)
        guard session.canAddConnection(videoConnection), session.canAddConnection(photoConnection) else {
            return false
        }
        session.addConnection(videoConnection)
        session.addConnection(photoConnection)

        // 画面は縦向き固定なので映像も縦向きでもらい、内カメラは鏡のように左右反転する
        if videoConnection.isVideoRotationAngleSupported(90) { videoConnection.videoRotationAngle = 90 }
        if videoConnection.isVideoMirroringSupported {
            videoConnection.automaticallyAdjustsVideoMirroring = false
            videoConnection.isVideoMirrored = mirrored
        }
        if let largest = device.activeFormat.supportedMaxPhotoDimensions
            .max(by: { $0.width * $0.height < $1.width * $1.height }) {
            photo.maxPhotoDimensions = largest
        }
        return true
    }

    // MARK: - 撮影

    /// 外と内を同時に撮る。どちらも向きを適用した画像で返す（失敗した方は nil）
    func capture(angle: CGFloat, completion: @escaping (_ back: CIImage?, _ front: CIImage?) -> Void) {
        var back: CIImage?
        var front: CIImage?
        let group = DispatchGroup()

        for (output, isBack) in [(backPhoto, true), (frontPhoto, false)] {
            if let connection = output.connection(with: .video) {
                if connection.isVideoRotationAngleSupported(angle) { connection.videoRotationAngle = angle }
                if connection.isVideoMirroringSupported {
                    connection.automaticallyAdjustsVideoMirroring = false
                    connection.isVideoMirrored = !isBack
                }
            }
            let settings = AVCapturePhotoSettings()
            settings.maxPhotoDimensions = output.maxPhotoDimensions
            settings.photoQualityPrioritization = .balanced
            group.enter()
            let processor = DualPhotoProcessor { image in
                self.queue.async {
                    if isBack { back = image } else { front = image }
                    group.leave()
                }
            }
            inFlight.append(processor)
            output.capturePhoto(with: settings, delegate: processor)
        }

        group.notify(queue: queue) {
            self.inFlight.removeAll()
            completion(back, front)
        }
    }
}

extension DualCameraSession: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        onFrame?(CIImage(cvPixelBuffer: pixelBuffer), output === backVideo)
    }
}

private final class DualPhotoProcessor: NSObject, AVCapturePhotoCaptureDelegate {
    private let completion: (CIImage?) -> Void

    init(completion: @escaping (CIImage?) -> Void) {
        self.completion = completion
    }

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        let image = error == nil
            ? photo.fileDataRepresentation().flatMap { CIImage(data: $0, options: [.applyOrientationProperty: true]) }
            : nil
        completion(image)
    }
}
