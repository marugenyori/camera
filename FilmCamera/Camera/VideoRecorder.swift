import AVFoundation
import CoreImage

/// フィルタをかけた映像（と音声）を、HEVC の動画ファイルに書き出す。
/// すべて同じキュー（CameraModel の videoQueue）から呼ぶ
final class VideoRecorder {
    let url: URL
    private let writer: AVAssetWriter
    private let videoInput: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private let audioInput: AVAssetWriterInput?
    private let size: CGSize
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    private var started = false

    /// transform は再生時の向き（端末を横にして撮ったときに横向きの動画にする）
    init?(size: CGSize, transform: CGAffineTransform, withAudio: Bool) {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")
        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mov) else { return nil }
        self.writer = writer

        // 動画の縦横は偶数にする
        let width = Int(size.width) & ~1
        let height = Int(size.height) & ~1
        self.size = CGSize(width: width, height: height)

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 30_000_000],
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
            ],
        ]
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = true
        videoInput.transform = transform
        guard writer.canAdd(videoInput) else { return nil }
        writer.add(videoInput)
        self.videoInput = videoInput

        adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
                kCVPixelBufferMetalCompatibilityKey as String: true,
            ])

        var audioInput: AVAssetWriterInput?
        if withAudio {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVNumberOfChannelsKey: 1,
                AVSampleRateKey: 44_100,
                AVEncoderBitRateKey: 128_000,
            ])
            input.expectsMediaDataInRealTime = true
            if writer.canAdd(input) {
                writer.add(input)
                audioInput = input
            }
        }
        self.audioInput = audioInput
    }

    /// フィルタをかけた 1 コマを書き込む（最初のコマの時刻から動画が始まる）
    func append(_ image: CIImage, at time: CMTime, context: CIContext) {
        if !started {
            guard writer.startWriting() else { return }
            writer.startSession(atSourceTime: time)
            started = true
        }
        guard videoInput.isReadyForMoreMediaData, let pool = adaptor.pixelBufferPool else { return }
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
        guard let buffer else { return }
        let placed = image.transformed(by: CGAffineTransform(
            translationX: -image.extent.minX, y: -image.extent.minY))
        context.render(placed, to: buffer, bounds: CGRect(origin: .zero, size: size), colorSpace: colorSpace)
        adaptor.append(buffer, withPresentationTime: time)
    }

    func append(audio sample: CMSampleBuffer) {
        guard started, let audioInput, audioInput.isReadyForMoreMediaData else { return }
        audioInput.append(sample)
    }

    /// 書き出しを終える。成功したらファイルの場所を返す
    func finish(_ completion: @escaping (URL?) -> Void) {
        guard started else {
            completion(nil)
            return
        }
        videoInput.markAsFinished()
        audioInput?.markAsFinished()
        writer.finishWriting {
            completion(self.writer.status == .completed ? self.url : nil)
        }
    }
}
