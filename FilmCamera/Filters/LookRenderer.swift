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

        var out: CIImage
        switch options.mode {
        case .film: out = film(image, seed: options.grainSeed)
        case .flash: out = flash(image, seed: options.grainSeed)
        case .iwai: out = iwai(image, seed: options.grainSeed)
        }
        if options.dateStamp { out = stamp(date, on: out) }
        return out
    }

    // MARK: - フィルム風（写ルンです・ネガフィルム）

    /// 黒が締まりきらない低いコントラスト、クリーム〜ピンクがかったハイライト、
    /// 緑っぽい影、くすんだ緑、ハイライトのふんわりしたにじみ、細かい粒子
    private static func film(_ image: CIImage, seed: CGPoint) -> CIImage {
        let extent = image.extent

        let controls = CIFilter.colorControls()
        controls.inputImage = toSRGB(exposure(image, ev: 0.15))
        controls.saturation = 0.80
        controls.contrast = 0.95

        // 色ごとのトーンカーブ（入力 x に対する 3 次式）
        // 赤：ハイライトを持ち上げる／緑：影を持ち上げ、ハイライトを抑える／青：ハイライトを抑える
        let toned = polynomial(controls.outputImage ?? image,
                               r: (0.03, 0.87, 0.25, -0.17),
                               g: (0.045, 0.94, -0.02, -0.07),
                               b: (0.04, 0.82, 0.06, -0.04))

        // 粒子は画質が落ちて見えるため入れない（`grain` は残してある）
        let grained = diffusion(toned, radius: longSide(extent) * 0.006, amount: 0.10)
        return toLinear(vignette(grained, strength: 0.28, inner: 0.42))
    }

    // MARK: - フラッシュ風（2000年代のコンデジの直射フラッシュ）

    /// 手前の被写体が平たく明るく照らされ、白は飛び気味、黒はつぶれ、
    /// 背景は少し暗く沈む。色は濃く、くっきり
    private static func flash(_ image: CIImage, seed: CGPoint) -> CIImage {
        let extent = image.extent
        // 人が来やすい、中央より少し上を中心にする（Core Image は下が原点）
        let center = CGPoint(x: extent.midX, y: extent.midY + extent.height * 0.05)

        let bright = exposure(image, ev: 0.15)
        let dark = exposure(image, ev: -1.2)

        // 中央は明るく、外側はゆるやかに暗くなるマスク
        let gradient = CIFilter.radialGradient()
        gradient.center = center
        gradient.radius0 = Float(shortSide(extent) * 0.22)
        gradient.radius1 = Float(longSide(extent) * 0.80)
        gradient.color0 = CIColor(red: 1, green: 1, blue: 1)
        gradient.color1 = CIColor(red: 0, green: 0, blue: 0)
        let mask = (gradient.outputImage ?? image).cropped(to: extent)

        let blend = CIFilter.blendWithMask()
        blend.inputImage = bright
        blend.backgroundImage = dark
        blend.maskImage = mask
        let lit = blend.outputImage ?? image

        let controls = CIFilter.colorControls()
        controls.inputImage = toSRGB(lit)
        controls.saturation = 1.05
        controls.contrast = 1.02

        // 黒をつぶし、白を飛ばす
        let punchy = toneCurve(controls.outputImage, [
            (0.00, 0.00), (0.20, 0.15), (0.50, 0.51), (0.80, 0.90), (1.00, 1.00),
        ])

        // フラッシュ光のやや青白い色
        let cool = colorMatrix(punchy, r: 0.97, g: 1.00, b: 1.04, bias: (0, 0, 0.005))

        let sharpen = CIFilter.sharpenLuminance()
        sharpen.inputImage = cool
        sharpen.sharpness = 0.25
        let sharp = (sharpen.outputImage ?? cool).cropped(to: extent)

        let grained = sharp
        return toLinear(vignette(grained, strength: 0.12, inner: 0.55))
    }

    // MARK: - 岩井俊二風（淡い水色・白飛び・やわらかな光）

    /// 明るめの露出、持ち上がった青緑の影、水色がかった白、
    /// 低い彩度、ハイライトが大きくにじむ空気感
    private static func iwai(_ image: CIImage, seed: CGPoint) -> CIImage {
        let extent = image.extent

        let controls = CIFilter.colorControls()
        controls.inputImage = toSRGB(exposure(image, ev: 0.25))
        controls.saturation = 0.70
        controls.contrast = 0.95

        // 赤を抑え、緑と青の影を持ち上げる
        let toned = polynomial(controls.outputImage ?? image,
                               r: (0.03, 0.86, 0.10, -0.05),
                               g: (0.05, 0.91, 0.05, -0.04),
                               b: (0.08, 0.89, 0.04, -0.04))

        let grained = diffusion(toned, radius: longSide(extent) * 0.010, amount: 0.18)
        return toLinear(vignette(grained, strength: 0.10, inner: 0.55))
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
            // 1画素ずつの白い点にならないよう、少しぼかして粒にする
            .applyingGaussianBlur(sigma: Double(scale * 0.6))
            .cropped(to: extent)

        // 白黒の、0.5 を中心にした弱いノイズにする
        // ぼかすと揺れ幅が小さくなるので、その分を補う
        let a = amount * 2
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

    /// 色ごとに out = a0 + a1·x + a2·x² + a3·x³ をかける
    private static func polynomial(_ image: CIImage,
                                   r: (CGFloat, CGFloat, CGFloat, CGFloat),
                                   g: (CGFloat, CGFloat, CGFloat, CGFloat),
                                   b: (CGFloat, CGFloat, CGFloat, CGFloat)) -> CIImage {
        let f = CIFilter.colorPolynomial()
        f.inputImage = image
        f.redCoefficients = CIVector(x: r.0, y: r.1, z: r.2, w: r.3)
        f.greenCoefficients = CIVector(x: g.0, y: g.1, z: g.2, w: g.3)
        f.blueCoefficients = CIVector(x: b.0, y: b.1, z: b.2, w: b.3)
        f.alphaCoefficients = CIVector(x: 0, y: 1, z: 0, w: 0)
        return f.outputImage ?? image
    }

    /// ぼかした像をスクリーン合成で薄く重ね、明るい部分をふんわりにじませる。
    /// 元の像はぼかさないので、細部は残る
    private static func diffusion(_ image: CIImage, radius: CGFloat, amount: CGFloat) -> CIImage {
        let extent = image.extent
        let blurred = image
            .clampedToExtent()
            .applyingGaussianBlur(sigma: Double(radius))
            .cropped(to: extent)
        let faded = colorMatrix(blurred, r: amount, g: amount, b: amount, bias: (0, 0, 0))
        let screen = CIFilter.screenBlendMode()
        screen.inputImage = faded
        screen.backgroundImage = image
        return (screen.outputImage ?? image).cropped(to: extent)
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

    /// Core Image は明るさを「光の量に比例する値（リニア）」で計算するため、
    /// 色の調整は見た目どおりの明るさ（sRGB）に変換してから行い、最後に戻す。
    /// リニアのまま黒を持ち上げると、画面全体が白っぽく霞んでしまう
    /// あわせて 0〜1 の範囲に収める。iPhone の写真は色域が広く、
    /// sRGB にすると範囲外（マイナスや 1 超え）の値が出る。そのまま 3 次式や
    /// トーンカーブにかけると値が暴れ、色付きの白い点やまだらになる
    private static func toSRGB(_ image: CIImage) -> CIImage {
        let srgb = image.applyingFilter("CILinearToSRGBToneCurve")
        let clamp = CIFilter.colorClamp()
        clamp.inputImage = srgb
        clamp.minComponents = CIVector(x: 0, y: 0, z: 0, w: 0)
        clamp.maxComponents = CIVector(x: 1, y: 1, z: 1, w: 1)
        return clamp.outputImage ?? srgb
    }

    private static func toLinear(_ image: CIImage) -> CIImage {
        image.applyingFilter("CISRGBToneCurveToLinear")
    }

    private static func longSide(_ r: CGRect) -> CGFloat { max(r.width, r.height) }
    private static func shortSide(_ r: CGRect) -> CGFloat { min(r.width, r.height) }
}
