import PhotosUI
import SwiftUI
import UIKit

/// 隠しゲーム「ジュエル塗り絵」（Jewel Coloring のような、番号どおりに宝石を置いていく塗り絵）。
/// 写真を小さなマス目に分け、色を数色にまとめて番号をふる。色を選んでマスをなぞると、
/// 番号が合うマスにだけ宝石がはまる。全部埋めると写真が宝石のモザイクになって完成
struct JewelGameView: View {
    /// 最初に使う写真（最後に撮った写真。なければ見本の絵）
    let initialImage: UIImage?
    @Environment(\.dismiss) private var dismiss

    @State private var puzzle: JewelPuzzle?
    @State private var filled: [Bool] = []
    @State private var selected = 0
    @State private var pickerItem: PhotosPickerItem?

    private var filledCount: Int { filled.lazy.filter { $0 }.count }
    private var isComplete: Bool { !filled.isEmpty && filledCount == filled.count }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(white: 0.08).ignoresSafeArea()
                if let puzzle {
                    VStack(spacing: 14) {
                        progressBar(puzzle)
                        board(puzzle)
                        palette(puzzle)
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                } else {
                    ProgressView().tint(.white)
                }
                if isComplete, let puzzle {
                    completeBanner(puzzle)
                }
            }
            .navigationTitle("ジュエル塗り絵")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Image(systemName: "photo.on.rectangle")
                    }
                    .accessibilityLabel("ほかの写真で遊ぶ")
                }
            }
            .sensoryFeedback(.impact(weight: .light), trigger: filledCount)
            .sensoryFeedback(.success, trigger: isComplete)
        }
        .preferredColorScheme(.dark)
        .task { start(with: initialImage ?? JewelPuzzle.sampleImage()) }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    start(with: image)
                }
            }
        }
    }

    private func start(with image: UIImage) {
        guard let made = JewelPuzzle(image: image) else { return }
        puzzle = made
        filled = Array(repeating: false, count: made.targets.count)
        selected = 0
    }

    // MARK: - 盤面

    private func board(_ puzzle: JewelPuzzle) -> some View {
        GeometryReader { geo in
            let cell = min(geo.size.width / CGFloat(puzzle.columns), geo.size.height / CGFloat(puzzle.rows))
            let size = CGSize(width: cell * CGFloat(puzzle.columns), height: cell * CGFloat(puzzle.rows))
            Canvas { context, _ in
                let numbers = (0..<puzzle.palette.count).map {
                    context.resolve(Text("\($0 + 1)")
                        .font(.system(size: cell * 0.42, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color(white: 0.45)))
                }
                for index in puzzle.targets.indices {
                    let rect = CGRect(x: CGFloat(index % puzzle.columns) * cell,
                                      y: CGFloat(index / puzzle.columns) * cell,
                                      width: cell, height: cell)
                    let target = puzzle.targets[index]
                    if filled[index] {
                        Self.drawJewel(in: rect, color: puzzle.palette[target], context: &context)
                    } else {
                        let highlight = target == selected
                        context.fill(Path(rect.insetBy(dx: 0.5, dy: 0.5)),
                                     with: .color(highlight ? Color(white: 0.82) : Color(white: 0.93)))
                        context.draw(numbers[target], at: CGPoint(x: rect.midX, y: rect.midY))
                    }
                }
            }
            .frame(width: size.width, height: size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in paint(at: value.location, cell: cell, puzzle: puzzle) }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// なぞったマスに、選んだ色の宝石を置く（番号が違うマスには置かない）
    private func paint(at point: CGPoint, cell: CGFloat, puzzle: JewelPuzzle) {
        guard cell > 0, point.x >= 0, point.y >= 0 else { return }
        let column = Int(point.x / cell)
        let row = Int(point.y / cell)
        guard column < puzzle.columns, row < puzzle.rows else { return }
        let index = row * puzzle.columns + column
        guard !filled[index], puzzle.targets[index] == selected else { return }
        filled[index] = true
        // この色を塗り終えたら、次の残っている色に移る
        if !puzzle.targets.indices.contains(where: { !filled[$0] && puzzle.targets[$0] == selected }),
           let next = nextColor(after: selected, puzzle: puzzle) {
            selected = next
        }
    }

    private func nextColor(after color: Int, puzzle: JewelPuzzle) -> Int? {
        let count = puzzle.palette.count
        for step in 1..<max(count, 2) {
            let candidate = (color + step) % count
            if remaining(of: candidate, puzzle: puzzle) > 0 { return candidate }
        }
        return nil
    }

    private func remaining(of color: Int, puzzle: JewelPuzzle) -> Int {
        puzzle.targets.indices.filter { puzzle.targets[$0] == color && !filled[$0] }.count
    }

    /// 宝石 1 粒：角の丸い台に、光る面（左上）と影の面（右下）、真ん中のテーブル面と小さなきらめき
    private static func drawJewel(in rect: CGRect, color: Color, context: inout GraphicsContext) {
        let r = rect.insetBy(dx: rect.width * 0.04, dy: rect.height * 0.04)
        let outline = Path(roundedRect: r, cornerRadius: r.width * 0.2)
        context.fill(outline, with: .color(color))
        context.drawLayer { layer in
            layer.clip(to: outline)
            var light = Path()
            light.move(to: CGPoint(x: r.minX, y: r.minY))
            light.addLine(to: CGPoint(x: r.maxX, y: r.minY))
            light.addLine(to: CGPoint(x: r.minX, y: r.maxY))
            light.closeSubpath()
            layer.fill(light, with: .color(.white.opacity(0.28)))
            var shade = Path()
            shade.move(to: CGPoint(x: r.maxX, y: r.minY))
            shade.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
            shade.addLine(to: CGPoint(x: r.minX, y: r.maxY))
            shade.closeSubpath()
            layer.fill(shade, with: .color(.black.opacity(0.22)))
        }
        let table = r.insetBy(dx: r.width * 0.27, dy: r.height * 0.27)
        context.fill(Path(roundedRect: table, cornerRadius: table.width * 0.15), with: .color(color))
        context.fill(Path(roundedRect: table, cornerRadius: table.width * 0.15), with: .color(.white.opacity(0.1)))
        let spark = CGRect(x: r.minX + r.width * 0.18, y: r.minY + r.height * 0.16,
                           width: r.width * 0.16, height: r.height * 0.16)
        context.fill(Path(ellipseIn: spark), with: .color(.white.opacity(0.75)))
    }

    // MARK: - 色の選択と進み具合

    private func palette(_ puzzle: JewelPuzzle) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(puzzle.palette.indices, id: \.self) { index in
                    let left = remaining(of: index, puzzle: puzzle)
                    Button {
                        selected = index
                    } label: {
                        VStack(spacing: 4) {
                            ZStack {
                                Circle()
                                    .fill(puzzle.palette[index])
                                    .frame(width: 44, height: 44)
                                if left == 0 {
                                    Image(systemName: "checkmark")
                                        .font(.footnote.weight(.bold))
                                        .foregroundStyle(.white)
                                        .shadow(radius: 2)
                                } else {
                                    Text("\(index + 1)")
                                        .font(.footnote.weight(.bold).monospacedDigit())
                                        .foregroundStyle(puzzle.isLight(index) ? Color.black : Color.white)
                                }
                            }
                            .overlay(Circle().stroke(Color.white, lineWidth: selected == index ? 3 : 0))
                            Text(left == 0 ? "完了" : "\(left)")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .opacity(left == 0 ? 0.45 : 1)
                }
            }
            .padding(.horizontal, 4)
        }
        .frame(height: 70)
    }

    private func progressBar(_ puzzle: JewelPuzzle) -> some View {
        HStack(spacing: 10) {
            ProgressView(value: Double(filledCount), total: Double(max(filled.count, 1)))
                .tint(.orange)
            Text("\(filledCount * 100 / max(filled.count, 1))%")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.top, 8)
    }

    private func completeBanner(_ puzzle: JewelPuzzle) -> some View {
        VStack(spacing: 12) {
            Text("完成！")
                .font(.title.weight(.heavy))
            Text("\(filled.count) 粒の宝石をはめました")
                .font(.footnote)
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                if let image = finishedImage(puzzle) {
                    ShareLink(item: Image(uiImage: image),
                              preview: SharePreview("ジュエル塗り絵", image: Image(uiImage: image))) {
                        Label("保存・共有", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.borderedProminent)
                }
                Button("もう一度") {
                    filled = Array(repeating: false, count: filled.count)
                    selected = 0
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(24)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(32)
        .transition(.scale.combined(with: .opacity))
    }

    /// 完成した宝石のモザイクを画像にする（1 マス 40px）
    private func finishedImage(_ puzzle: JewelPuzzle) -> UIImage? {
        let cell: CGFloat = 40
        let canvas = Canvas { context, _ in
            for index in puzzle.targets.indices {
                let rect = CGRect(x: CGFloat(index % puzzle.columns) * cell,
                                  y: CGFloat(index / puzzle.columns) * cell,
                                  width: cell, height: cell)
                Self.drawJewel(in: rect, color: puzzle.palette[puzzle.targets[index]], context: &context)
            }
        }
        .frame(width: cell * CGFloat(puzzle.columns), height: cell * CGFloat(puzzle.rows))
        .background(Color(white: 0.08))
        return ImageRenderer(content: canvas).uiImage
    }
}

/// 塗り絵の問題：マス目の大きさ、使う色（パレット）、各マスの正解の色番号
struct JewelPuzzle {
    let columns: Int
    let rows: Int
    let palette: [Color]
    private let rgb: [SIMD3<Float>]
    let targets: [Int]

    /// 写真から問題を作る。縦長 3:4 に切り抜き、横 20 マスにして、色を 10 色にまとめる
    init?(image: UIImage, columns: Int = 20, colors: Int = 10) {
        guard let cgImage = image.cgImage ?? Self.render(image) else { return nil }
        let rows = columns * 4 / 3
        guard let pixels = Self.pixels(of: cgImage, orientation: image.imageOrientation,
                                       columns: columns, rows: rows) else { return nil }
        let centers = Self.kMeans(pixels, k: colors)
        // 明るい色から順に番号をふる
        let order = centers.indices.sorted { Self.luma(centers[$0]) > Self.luma(centers[$1]) }
        let sorted = order.map { centers[$0] }
        self.columns = columns
        self.rows = rows
        self.rgb = sorted
        self.palette = sorted.map { Color(red: Double($0.x), green: Double($0.y), blue: Double($0.z)) }
        self.targets = pixels.map { Self.nearest($0, in: sorted) }
    }

    func isLight(_ index: Int) -> Bool { Self.luma(rgb[index]) > 0.6 }

    private static func luma(_ c: SIMD3<Float>) -> Float { 0.299 * c.x + 0.587 * c.y + 0.114 * c.z }

    private static func nearest(_ p: SIMD3<Float>, in centers: [SIMD3<Float>]) -> Int {
        var best = 0
        var bestDistance = Float.greatestFiniteMagnitude
        for (i, c) in centers.enumerated() {
            let d = p - c
            let distance = (d * d).sum()
            if distance < bestDistance {
                bestDistance = distance
                best = i
            }
        }
        return best
    }

    /// 似た色をまとめて k 色にする（k-means）。初めの色は明るさ順に均等に選ぶ
    private static func kMeans(_ pixels: [SIMD3<Float>], k: Int) -> [SIMD3<Float>] {
        let byLuma = pixels.sorted { luma($0) < luma($1) }
        var centers = (0..<k).map { byLuma[min(byLuma.count - 1, ($0 * 2 + 1) * byLuma.count / (k * 2))] }
        for _ in 0..<10 {
            var sums = [SIMD3<Float>](repeating: .zero, count: k)
            var counts = [Float](repeating: 0, count: k)
            for p in pixels {
                let i = nearest(p, in: centers)
                sums[i] += p
                counts[i] += 1
            }
            for i in 0..<k where counts[i] > 0 {
                centers[i] = sums[i] / counts[i]
            }
        }
        // 同じ色になってしまった分は除く
        var unique: [SIMD3<Float>] = []
        for c in centers where !unique.contains(where: { ((c - $0) * (c - $0)).sum() < 0.0004 }) {
            unique.append(c)
        }
        return unique
    }

    /// 写真を縦 3:4 の中央で切り抜き、columns × rows に縮めた色を読む
    private static func pixels(of image: CGImage, orientation: UIImage.Orientation,
                               columns: Int, rows: Int) -> [SIMD3<Float>]? {
        let upright = UIImage(cgImage: image, scale: 1, orientation: orientation)
        let size = upright.size
        let target = CGSize(width: columns, height: rows)
        let scale = max(target.width / size.width, target.height / size.height)
        let drawSize = CGSize(width: size.width * scale, height: size.height * scale)
        let origin = CGPoint(x: (target.width - drawSize.width) / 2, y: (target.height - drawSize.height) / 2)

        var bytes = [UInt8](repeating: 0, count: columns * rows * 4)
        let drew: Bool = bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: columns, height: rows,
                                          bitsPerComponent: 8, bytesPerRow: columns * 4,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .high
            UIGraphicsPushContext(context)
            // UIKit の座標（上が 0）で描くため、上下を反転する
            context.translateBy(x: 0, y: CGFloat(rows))
            context.scaleBy(x: 1, y: -1)
            upright.draw(in: CGRect(origin: origin, size: drawSize))
            UIGraphicsPopContext()
            return true
        }
        guard drew else { return nil }
        return (0..<(columns * rows)).map { i in
            SIMD3(Float(bytes[i * 4]) / 255, Float(bytes[i * 4 + 1]) / 255, Float(bytes[i * 4 + 2]) / 255)
        }
    }

    private static func render(_ image: UIImage) -> CGImage? {
        UIGraphicsImageRenderer(size: image.size).image { _ in image.draw(at: .zero) }.cgImage
    }

    /// 写真がないときの見本の絵（夕焼けの海と太陽）
    static func sampleImage() -> UIImage {
        let size = CGSize(width: 300, height: 400)
        return UIGraphicsImageRenderer(size: size).image { renderer in
            let context = renderer.cgContext
            let sky = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                 colors: [UIColor(red: 0.18, green: 0.2, blue: 0.5, alpha: 1).cgColor,
                                          UIColor(red: 0.95, green: 0.45, blue: 0.35, alpha: 1).cgColor,
                                          UIColor(red: 1, green: 0.8, blue: 0.4, alpha: 1).cgColor] as CFArray,
                                 locations: [0, 0.6, 1])!
            context.drawLinearGradient(sky, start: .zero, end: CGPoint(x: 0, y: 260), options: [])
            UIColor(red: 1, green: 0.9, blue: 0.55, alpha: 1).setFill()
            context.fillEllipse(in: CGRect(x: 105, y: 170, width: 90, height: 90))
            UIColor(red: 0.1, green: 0.3, blue: 0.55, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 260, width: 300, height: 140))
            UIColor(red: 0.95, green: 0.65, blue: 0.4, alpha: 1).setFill()
            for y in stride(from: 275, to: 400, by: 22) {
                context.fill(CGRect(x: 110 - (y - 260) / 4, y: y, width: 80 + (y - 260) / 2, height: 5))
            }
        }
    }
}
