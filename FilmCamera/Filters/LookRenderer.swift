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
        case .flash: out = flash(image, depth: options.depth, subject: options.subjectDistance)
        case .warmFlash: out = flash(image, depth: options.depth, subject: options.subjectDistance, warm: true)
        case .iwai: out = iwai(image, seed: options.grainSeed)
        case .cross: out = cross(image)
        case .double: out = multiple(image, overlays: options.overlays,
                                     total: options.exposureTotal, seed: options.grainSeed)
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
        return toLinear(vignette(detail(grained), strength: 0.28, inner: 0.42))
    }

    // MARK: - フラッシュ風（2000年代のコンデジの直射フラッシュ）

    /// 手前の被写体が平たく明るく照らされ、白は飛び気味、黒はつぶれ、
    /// 背景は少し暗く沈む。色は濃く、くっきり
    private static func flash(_ image: CIImage, depth: CIImage?, subject: CGFloat?,
                              warm: Bool = false) -> CIImage {
        let extent = image.extent
        // 人が来やすい、中央より少し上を中心にする（Core Image は下が原点）
        let center = CGPoint(x: extent.midX, y: extent.midY + extent.height * 0.05)

        let bright: CIImage
        let dark: CIImage
        let mask: CIImage
        if let depth, let falloff = flashFalloff(depth: depth, subject: subject ?? 1.0, guide: image) {
            // 距離が分かるとき：近いものほど強く照らし、遠くは暗く沈める（本物のフラッシュと同じ）
            bright = exposure(image, ev: 0.6)
            dark = exposure(image, ev: -1.4)
            let beam = radialMask(center: center, extent: extent,
                                  inner: shortSide(extent) * 0.35, outer: longSide(extent) * 0.9,
                                  edge: 0.6)
            let multiply = CIFilter.multiplyCompositing()
            multiply.inputImage = falloff
            multiply.backgroundImage = beam
            mask = (multiply.outputImage ?? falloff).cropped(to: extent)
        } else {
            // 距離が分からないとき：中央を近いとみなし、外側ほど暗くする
            bright = exposure(image, ev: 0.15)
            dark = exposure(image, ev: -1.2)
            mask = radialMask(center: center, extent: extent,
                              inner: shortSide(extent) * 0.22, outer: longSide(extent) * 0.80,
                              edge: 0)
        }

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

        // ふつうはフラッシュ光のやや青白い色。暖フラッシュは電球や古いストロボのような黄〜橙
        let cool = warm
            ? colorMatrix(punchy, r: 1.07, g: 1.00, b: 0.84, bias: (0.02, 0.005, -0.01))
            : colorMatrix(punchy, r: 0.97, g: 1.00, b: 1.04, bias: (0, 0, 0.005))

        let sharpen = CIFilter.sharpenLuminance()
        sharpen.inputImage = cool
        sharpen.sharpness = 0.25
        let sharp = (sharpen.outputImage ?? cool).cropped(to: extent)

        let grained = sharp
        return toLinear(vignette(grained, strength: 0.12, inner: 0.55))
    }

    /// 距離（メートル）から、フラッシュの光の当たり具合（1 = よく当たる、0 = 届かない）を作る。
    /// 本物のカメラと同じく、主な被写体（subject）にちょうどよく当たるよう強さを合わせ、
    /// そこから距離の 2 乗で弱める（被写体の 1.5 倍の距離で約半分、2 倍で 1/4、4 倍以上で届かない）。
    /// 距離の画像は粗いので、写真の輪郭に沿って拡大し、物の縁から光がはみ出さないようにする
    private static func flashFalloff(depth: CIImage, subject: CGFloat, guide: CIImage) -> CIImage? {
        let d = depth.extent
        guard d.width > 0, d.height > 0 else { return nil }
        let small = depth.transformed(by: CGAffineTransform(translationX: -d.minX, y: -d.minY))

        // 「被写体までの距離の何倍か」を 4 で割った値（0〜1）にし、3 色とも同じ値にする
        let normalize = CIFilter.colorMatrix()
        normalize.inputImage = small
        let k: CGFloat = 1.0 / (max(subject, 0.3) * 4)
        normalize.rVector = CIVector(x: k, y: 0, z: 0, w: 0)
        normalize.gVector = CIVector(x: k, y: 0, z: 0, w: 0)
        normalize.bVector = CIVector(x: k, y: 0, z: 0, w: 0)
        normalize.aVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        normalize.biasVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        let clamp = CIFilter.colorClamp()
        clamp.inputImage = normalize.outputImage
        clamp.minComponents = CIVector(x: 0, y: 0, z: 0, w: 1)
        clamp.maxComponents = CIVector(x: 1, y: 1, z: 1, w: 1)
        guard let normalized = clamp.outputImage else { return nil }

        // 横軸は（距離 ÷ 被写体の距離）÷ 4。0.25 が被写体の位置
        let falloff = toneCurve(normalized, [
            (0.00, 1.00), (0.18, 1.00), (0.375, 0.45), (0.50, 0.25), (1.00, 0.00),
        ])

        // 距離が測れなかった所（0m 扱い）は「近い」と誤解して白く飛ぶので、光を当てない
        let valid = CIFilter.colorThreshold()
        valid.inputImage = normalized
        valid.threshold = 0.02
        let multiply = CIFilter.multiplyCompositing()
        multiply.inputImage = falloff
        multiply.backgroundImage = valid.outputImage ?? normalized
        let masked = (multiply.outputImage ?? falloff).cropped(to: small.extent)

        // 写真の明るさの輪郭を手がかりに拡大する
        let upsample = CIFilter.edgePreserveUpsample()
        upsample.inputImage = guide
        upsample.smallImage = masked
        upsample.spatialSigma = 3
        upsample.lumaSigma = 0.15
        return upsample.outputImage?.cropped(to: guide.extent)
    }

    /// 中央が 1、外側が edge になる円形のマスク
    private static func radialMask(center: CGPoint, extent: CGRect,
                                   inner: CGFloat, outer: CGFloat, edge: CGFloat) -> CIImage {
        let gradient = CIFilter.radialGradient()
        gradient.center = center
        gradient.radius0 = Float(inner)
        gradient.radius1 = Float(outer)
        gradient.color0 = CIColor(red: 1, green: 1, blue: 1)
        gradient.color1 = CIColor(red: edge, green: edge, blue: edge)
        return (gradient.outputImage ?? CIImage(color: .white)).cropped(to: extent)
    }

    // MARK: - クロス（クロスプロセス風）

    /// 持ち主が気に入った「アンバランスな色」。初期のフラッシュの処理をそのまま残したもの。
    /// 色の調整をあえてリニアのまま行うので、暖色（床や木）はより黄色く、
    /// 影や奥は青く沈み、暖色と寒色がぶつかる濃く硬い色になる。粒子は入れない
    private static func cross(_ image: CIImage) -> CIImage {
        let extent = image.extent
        let center = CGPoint(x: extent.midX, y: extent.midY + extent.height * 0.05)

        let bright = exposure(image, ev: 0.8)
        let dark = exposure(image, ev: -0.5)
        let mask = radialMask(center: center, extent: extent,
                              inner: shortSide(extent) * 0.30, outer: longSide(extent) * 0.95,
                              edge: 0)
        let blend = CIFilter.blendWithMask()
        blend.inputImage = bright
        blend.backgroundImage = dark
        blend.maskImage = mask
        let lit = blend.outputImage ?? image

        let controls = CIFilter.colorControls()
        controls.inputImage = lit
        controls.saturation = 1.20
        controls.contrast = 1.08

        let punchy = toneCurve(controls.outputImage, [
            (0.00, 0.00), (0.20, 0.11), (0.50, 0.52), (0.80, 0.93), (1.00, 1.00),
        ])
        let cool = colorMatrix(punchy, r: 0.97, g: 1.00, b: 1.04, bias: (0, 0, 0.005))

        let sharpen = CIFilter.sharpenLuminance()
        sharpen.inputImage = cool
        sharpen.sharpness = 0.6
        let sharp = (sharpen.outputImage ?? cool).cropped(to: extent)
        return vignette(sharp, strength: 0.12, inner: 0.55)
    }

    // MARK: - 多重露光

    /// フィルムで同じコマに何回も露光したように、先に撮った分と今の像を「スクリーン」で重ねる
    /// （明るい部分が足し合わさり、暗い部分にはほかの像が透けて見える）。
    /// 重ねるほど明るくなりすぎるので、枚数に応じて 1 枚ずつ暗くしてから重ね、仕上げにフィルムの色をかける
    private static func multiple(_ image: CIImage, overlays: [CIImage], total: Int, seed: CGPoint) -> CIImage {
        guard !overlays.isEmpty else { return film(image, seed: seed) }
        let extent = image.extent
        let ev = Float(-0.35 * log2(Double(max(total, 2))))
        var combined = toSRGB(exposure(image, ev: ev))
        for overlay in overlays {
            let layer = toSRGB(exposure(fill(overlay, into: extent), ev: ev))
            let screen = CIFilter.screenBlendMode()
            screen.inputImage = layer
            screen.backgroundImage = combined
            combined = (screen.outputImage ?? combined).cropped(to: extent)
        }
        return film(toLinear(combined), seed: seed)
    }

    /// 縦横比を保ったまま extent いっぱいに広げ、はみ出しは中央で切る
    static func fill(_ image: CIImage, into extent: CGRect) -> CIImage {
        let e = image.extent
        guard e.width > 0, e.height > 0 else { return image }
        let scale = max(extent.width / e.width, extent.height / e.height)
        let scaled = image
            .transformed(by: CGAffineTransform(translationX: -e.minX, y: -e.minY))
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let dx = extent.minX - (scaled.extent.width - extent.width) / 2
        let dy = extent.minY - (scaled.extent.height - extent.height) / 2
        return scaled.transformed(by: CGAffineTransform(translationX: dx, y: dy)).cropped(to: extent)
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
        return toLinear(vignette(detail(grained), strength: 0.10, inner: 0.55))
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
    /// にじみで甘くなった輪郭を、明るさだけ少し締める（色ノイズは強調しない）
    private static func detail(_ image: CIImage) -> CIImage {
        let extent = image.extent
        let sharpen = CIFilter.sharpenLuminance()
        sharpen.inputImage = image
        sharpen.sharpness = 0.45
        sharpen.radius = Float(max(1, longSide(extent) / 2000) * 1.2)
        return (sharpen.outputImage ?? image).cropped(to: extent)
    }

    // MARK: - 保存用の拡大

    /// 保存する写真の長い辺の最小値（約2700万画素）。これより小さければ高品質な拡大（Lanczos）で
    /// 大きくする。大きい写真（4800万画素など）は縮めない。拡大したときに細部が残るよう、
    /// カメラが撮った画素はそのまま保存する
    static let savedLongSide: CGFloat = 6048

    /// 写真を保存用の大きさにする。拡大で増えるのは画素数で、写っている情報は増えないため、
    /// 拡大したときは輪郭を軽く締めて見た目の細かさを補う
    static func resizeForSaving(_ image: CIImage) -> CIImage {
        let extent = image.extent
        let long = longSide(extent)
        guard long > 0, long < savedLongSide * 0.95 else { return image }
        let scale = savedLongSide / long
        let lanczos = CIFilter.lanczosScaleTransform()
        lanczos.inputImage = image
        lanczos.scale = Float(scale)
        lanczos.aspectRatio = 1
        guard let up = lanczos.outputImage else { return image }
        let sharpen = CIFilter.sharpenLuminance()
        sharpen.inputImage = up
        sharpen.sharpness = 0.3
        sharpen.radius = Float(scale * 1.2)
        return (sharpen.outputImage ?? up).cropped(to: up.extent)
    }

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
