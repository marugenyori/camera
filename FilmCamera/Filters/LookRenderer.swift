import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

/// プレビューの1フレームにも、保存する写真にも同じ処理をかける。
/// 粒子の大きさや周辺減光の範囲は画像サイズからの割合で決めるので、
/// 画面で見えている雰囲気のまま保存される。
enum LookRenderer {

    static func apply(_ input: CIImage, options: LookOptions, date: Date = Date()) -> CIImage {
        // 原点を (0, 0) にそろえる
        let image = input.transformed(by: CGAffineTransform(
            translationX: -input.extent.minX, y: -input.extent.minY))

        switch options.mode {
        case .film:
            var out = film(image, seed: options.grainSeed)
            if options.dateStamp { out = stamp(date, on: out) }
            return out
        case .flash:
            var out = flash(image, seed: options.grainSeed)
            if options.dateStamp { out = stamp(date, on: out) }
            return out
        case .instant:
            var out = instant(image, seed: options.grainSeed)
            if options.dateStamp { out = stamp(date, on: out) }
            return instantFrame(out)
        }
    }

    // MARK: - フィルム風（写ルンです・ポートラ風）

    private static func film(_ image: CIImage, seed: CGPoint) -> CIImage {
        let extent = image.extent

        // 彩度とコントラストを少し下げる
        let controls = CIFilter.colorControls()
        controls.inputImage = image
        controls.saturation = 0.82
        controls.contrast = 0.94
        controls.brightness = 0.0

        // 黒を持ち上げ、白を少し抑える（色あせた感じ）
        let curve = toneCurve(controls.outputImage, [
            (0.00, 0.07), (0.25, 0.25), (0.50, 0.53), (0.75, 0.79), (1.00, 0.96),
        ])

        // 暖色寄りにし、影に少し緑を足す
        let warm = colorMatrix(curve,
                               r: 1.06, g: 1.00, b: 0.88,
                               bias: (0.010, 0.016, 0.000))

        // ハイライトのにじみ（ハレーション）
        let bloom = CIFilter.bloom()
        bloom.inputImage = warm
        bloom.radius = Float(longSide(extent) * 0.010)
        bloom.intensity = 0.30
        let glowed = (bloom.outputImage ?? warm).cropped(to: extent)

        let grained = grain(glowed, amount: 0.10, seed: seed)
        return vignette(grained, strength: 0.42, inner: 0.40)
    }

    // MARK: - フラッシュ風（直射フラッシュ）

    private static func flash(_ image: CIImage, seed: CGPoint) -> CIImage {
        let extent = image.extent
        // 人の顔が来やすい、中央より少し上を中心にする（Core Image は下が原点）
        let center = CGPoint(x: extent.midX, y: extent.midY + extent.height * 0.06)

        let bright = exposure(image, ev: 0.9)
        let dark = exposure(image, ev: -1.3)

        // 中央は明るく、外側ほど暗くなるマスク
        let gradient = CIFilter.radialGradient()
        gradient.center = center
        gradient.radius0 = Float(shortSide(extent) * 0.22)
        gradient.radius1 = Float(longSide(extent) * 0.78)
        gradient.color0 = CIColor(red: 1, green: 1, blue: 1)
        gradient.color1 = CIColor(red: 0, green: 0, blue: 0)
        let mask = (gradient.outputImage ?? image).cropped(to: extent)

        let blend = CIFilter.blendWithMask()
        blend.inputImage = bright
        blend.backgroundImage = dark
        blend.maskImage = mask
        let lit = blend.outputImage ?? image

        // コントラスト強め・白飛び気味
        let controls = CIFilter.colorControls()
        controls.inputImage = lit
        controls.saturation = 1.08
        controls.contrast = 1.15
        let punchy = toneCurve(controls.outputImage, [
            (0.00, 0.00), (0.25, 0.19), (0.50, 0.52), (0.75, 0.86), (1.00, 1.00),
        ])

        // フラッシュ光の少し青白い色
        let cool = colorMatrix(punchy, r: 0.98, g: 1.00, b: 1.05, bias: (0, 0, 0.01))

        let sharpen = CIFilter.sharpenLuminance()
        sharpen.inputImage = cool
        sharpen.sharpness = 0.5
        let sharp = (sharpen.outputImage ?? cool).cropped(to: extent)

        let grained = grain(sharp, amount: 0.04, seed: seed)
        return vignette(grained, strength: 0.20, inner: 0.50)
    }

    // MARK: - インスタント風（チェキ・ポラロイド風）

    private static func instant(_ image: CIImage, seed: CGPoint) -> CIImage {
        // 中央を正方形に切り抜く
        let side = shortSide(image.extent)
        let square = image
            .cropped(to: CGRect(x: (image.extent.width - side) / 2,
                                y: (image.extent.height - side) / 2,
                                width: side, height: side))
        let base = square.transformed(by: CGAffineTransform(
            translationX: -square.extent.minX, y: -square.extent.minY))
        let extent = base.extent

        let controls = CIFilter.colorControls()
        controls.inputImage = base
        controls.saturation = 0.72
        controls.contrast = 0.86
        controls.brightness = 0.03

        let curve = toneCurve(controls.outputImage, [
            (0.00, 0.10), (0.25, 0.31), (0.50, 0.57), (0.75, 0.81), (1.00, 0.94),
        ])

        // 影は青緑寄り、全体はやや黄みのある淡い色
        let tinted = colorMatrix(curve,
                                 r: 1.03, g: 1.01, b: 0.93,
                                 bias: (-0.010, 0.020, 0.045))

        // 少しだけ柔らかく
        let soft = tinted
            .clampedToExtent()
            .applyingGaussianBlur(sigma: Double(side * 0.0008))
            .cropped(to: extent)

        let grained = grain(soft, amount: 0.06, seed: seed)
        return vignette(grained, strength: 0.30, inner: 0.45)
    }

    /// 白フチを付ける（下だけ太い）
    private static func instantFrame(_ photo: CIImage) -> CIImage {
        let side = photo.extent.width
        let border = side * 0.06
        let bottom = side * 0.24
        let canvasRect = CGRect(x: 0, y: 0,
                                width: side + border * 2,
                                height: photo.extent.height + border + bottom)
        let paper = CIImage(color: CIColor(red: 0.97, green: 0.96, blue: 0.93))
            .cropped(to: canvasRect)
        let placed = photo.transformed(by: CGAffineTransform(translationX: border, y: bottom))
        return placed.composited(over: paper)
    }

    // MARK: - 日付の写し込み（オレンジの文字）

    private static let stampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "''yy  M  d"
        return f
    }()

    private static func stamp(_ date: Date, on image: CIImage) -> CIImage {
        let extent = image.extent
        let text = CIFilter.textImageGenerator()
        text.text = stampFormatter.string(from: date)
        text.fontName = "DBLCDTempBlack"
        text.fontSize = Float(shortSide(extent) * 0.045)
        text.scaleFactor = 1
        guard let glyphs = text.outputImage else { return image }

        // 文字の形（アルファ）だけ使ってオレンジで塗る
        let orange = CIImage(color: CIColor(red: 1.0, green: 0.55, blue: 0.12))
            .cropped(to: glyphs.extent)
        let colored = CIFilter.blendWithAlphaMask()
        colored.inputImage = orange
        colored.backgroundImage = CIImage.empty()
        colored.maskImage = glyphs
        guard let label = colored.outputImage else { return image }

        // 右下に置き、少しにじませる
        let margin = shortSide(extent) * 0.05
        let moved = label.transformed(by: CGAffineTransform(
            translationX: extent.maxX - glyphs.extent.width - margin,
            y: extent.minY + margin))
        let glow = moved.applyingGaussianBlur(sigma: Double(shortSide(extent) * 0.004))
        return moved.composited(over: glow.composited(over: image)).cropped(to: extent)
    }

    // MARK: - 部品

    private static func grain(_ image: CIImage, amount: CGFloat, seed: CGPoint) -> CIImage {
        let extent = image.extent
        guard let random = CIFilter.randomGenerator().outputImage else { return image }

        // 画像が大きいほど粒を大きくして、見た目の粒の細かさをそろえる
        let scale = max(1, longSide(extent) / 1600)
        let noise = random
            .transformed(by: CGAffineTransform(translationX: seed.x, y: seed.y))
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            .cropped(to: extent)

        // 白黒の、0.5 を中心にした弱いノイズにする
        let a = amount
        let mono = CIFilter.colorMatrix()
        mono.inputImage = noise
        mono.rVector = CIVector(x: a, y: 0, z: 0, w: 0)
        mono.gVector = CIVector(x: a, y: 0, z: 0, w: 0)
        mono.bVector = CIVector(x: a, y: 0, z: 0, w: 0)
        mono.aVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        mono.biasVector = CIVector(x: 0.5 - a / 2, y: 0.5 - a / 2, z: 0.5 - a / 2, w: 1)

        let blend = CIFilter.softLightBlendMode()
        blend.inputImage = mono.outputImage
        blend.backgroundImage = image
        return (blend.outputImage ?? image).cropped(to: extent)
    }

    /// 周辺減光。inner は対角線の半分に対する「暗くなり始める位置」の割合
    private static func vignette(_ image: CIImage, strength: CGFloat, inner: CGFloat) -> CIImage {
        let extent = image.extent
        let halfDiagonal = hypot(extent.width, extent.height) / 2
        let edge = 1 - strength

        let gradient = CIFilter.radialGradient()
        gradient.center = CGPoint(x: extent.midX, y: extent.midY)
        gradient.radius0 = Float(halfDiagonal * inner)
        gradient.radius1 = Float(halfDiagonal * 1.05)
        gradient.color0 = CIColor(red: 1, green: 1, blue: 1)
        gradient.color1 = CIColor(red: edge, green: edge, blue: edge)
        guard let shade = gradient.outputImage?.cropped(to: extent) else { return image }

        let multiply = CIFilter.multiplyCompositing()
        multiply.inputImage = shade
        multiply.backgroundImage = image
        return (multiply.outputImage ?? image).cropped(to: extent)
    }

    private static func toneCurve(_ image: CIImage?, _ p: [(CGFloat, CGFloat)]) -> CIImage {
        let curve = CIFilter.toneCurve()
        curve.inputImage = image
        curve.point0 = CGPoint(x: p[0].0, y: p[0].1)
        curve.point1 = CGPoint(x: p[1].0, y: p[1].1)
        curve.point2 = CGPoint(x: p[2].0, y: p[2].1)
        curve.point3 = CGPoint(x: p[3].0, y: p[3].1)
        curve.point4 = CGPoint(x: p[4].0, y: p[4].1)
        return curve.outputImage ?? image ?? CIImage.empty()
    }

    private static func colorMatrix(_ image: CIImage, r: CGFloat, g: CGFloat, b: CGFloat,
                                    bias: (CGFloat, CGFloat, CGFloat)) -> CIImage {
        let m = CIFilter.colorMatrix()
        m.inputImage = image
        m.rVector = CIVector(x: r, y: 0, z: 0, w: 0)
        m.gVector = CIVector(x: 0, y: g, z: 0, w: 0)
        m.bVector = CIVector(x: 0, y: 0, z: b, w: 0)
        m.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        m.biasVector = CIVector(x: bias.0, y: bias.1, z: bias.2, w: 0)
        return m.outputImage ?? image
    }

    private static func exposure(_ image: CIImage, ev: Float) -> CIImage {
        let f = CIFilter.exposureAdjust()
        f.inputImage = image
        f.ev = ev
        return f.outputImage ?? image
    }

    private static func longSide(_ r: CGRect) -> CGFloat { max(r.width, r.height) }
    private static func shortSide(_ r: CGRect) -> CGFloat { min(r.width, r.height) }
}
