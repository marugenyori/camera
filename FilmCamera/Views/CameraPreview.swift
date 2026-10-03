import CoreImage
import MetalKit
import SwiftUI

/// カメラの映像に、選んだモードのフィルタをかけながら表示する（毎秒30コマ）
struct CameraPreview: UIViewRepresentable {
    let model: CameraModel

    func makeCoordinator() -> PreviewRenderer {
        PreviewRenderer(model: model)
    }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: context.coordinator.device)
        view.framebufferOnly = false
        // 画面の画素数どおりに描く（指定しないと1倍で描かれて粗くなることがある）
        view.contentScaleFactor = UIScreen.main.nativeScale
        view.colorPixelFormat = .bgra8Unorm
        view.preferredFramesPerSecond = 30
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        view.backgroundColor = .black
        view.delegate = context.coordinator
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {}
}

final class PreviewRenderer: NSObject, MTKViewDelegate {
    let device: MTLDevice?
    private let commandQueue: MTLCommandQueue?
    private let context: CIContext?
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    private weak var model: CameraModel?

    init(model: CameraModel) {
        self.model = model
        device = MTLCreateSystemDefaultDevice()
        commandQueue = device?.makeCommandQueue()
        context = device.map { CIContext(mtlDevice: $0, options: [.cacheIntermediates: false]) }
        super.init()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let model,
              let frame = model.latestFrame,
              let context,
              let commandBuffer = commandQueue?.makeCommandBuffer(),
              let drawable = view.currentDrawable else { return }

        let size = view.drawableSize
        guard size.width > 0, size.height > 0 else { return }

        // 先に画面の大きさまで縮めてからフィルタをかける（軽くするため）
        let origin = frame.transformed(by: CGAffineTransform(
            translationX: -frame.extent.minX, y: -frame.extent.minY))
        let shrink = min(1, size.width / origin.extent.width, size.height / origin.extent.height)
        let small = origin.transformed(by: CGAffineTransform(scaleX: shrink, y: shrink))

        let options = LookOptions(mode: model.mode, dateStamp: model.dateStamp)
        let look = LookRenderer.apply(small, options: options)

        // 枠いっぱいに収まるよう拡大・縮小して中央に置く
        let fit = min(size.width / look.extent.width, size.height / look.extent.height)
        let w = look.extent.width * fit
        let h = look.extent.height * fit
        let placed = look
            .transformed(by: CGAffineTransform(scaleX: fit, y: fit))
            .transformed(by: CGAffineTransform(translationX: (size.width - w) / 2,
                                               y: (size.height - h) / 2))
        let bounds = CGRect(origin: .zero, size: size)
        let image = placed.composited(over: CIImage(color: .black).cropped(to: bounds))

        context.render(image, to: drawable.texture, commandBuffer: commandBuffer,
                       bounds: bounds, colorSpace: colorSpace)
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
