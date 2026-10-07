import SwiftUI
import UIKit

/// かくれカメレオンの進行と、塗る・探すの中身。
/// ステージは 900 × 1200 の画像。隠れるキャラは、ステージ上の中心・大きさ・向きと、
/// 体に塗った絵（400 × 280 の画像。形の外は表示しない）を持つ
@MainActor
final class ChameleonGame: ObservableObject {
    enum Mode: String, CaseIterable, Identifiable {
        case solo, party
        var id: String { rawValue }
        var title: String { self == .solo ? "ひとりで" : "みんなで" }
    }

    enum Phase: Equatable {
        case setup
        /// 隠れる人に渡す（ほかの人は見ないで）
        case hideHandoff(Int)
        case hiding(Int)
        /// 鬼に渡す
        case seekHandoff
        case seeking
        case result
    }

    struct Hider: Identifiable {
        let id = UUID()
        var name: String
        var shape: HiderShape = .chameleon
        var center: CGPoint
        var scale: CGFloat = 1
        var angle: Double = 0
        var paint: UIImage
        var found = false
        /// 見つかるまでの秒数
        var foundAfter: Double?
    }

    enum Tool: String, CaseIterable, Identifiable {
        case brush, spray, dropper, fill, eraser
        var id: String { rawValue }
        var title: String {
            switch self {
            case .brush: return "筆"
            case .spray: return "スプレー"
            case .dropper: return "スポイト"
            case .fill: return "塗りつぶし"
            case .eraser: return "消しゴム"
            }
        }
        var systemImage: String {
            switch self {
            case .brush: return "paintbrush.pointed.fill"
            case .spray: return "aqi.medium"
            case .dropper: return "eyedropper.halffull"
            case .fill: return "drop.fill"
            case .eraser: return "eraser.fill"
            }
        }
    }

    static let stageSize = StagePreset.size
    static let bitmapSize = CGSize(width: 400, height: 280)
    static let hideSeconds: Double = 90
    static let seekSeconds: Double = 45

    @Published var phase: Phase = .setup
    @Published var mode: Mode = .party
    @Published var names: [String] = ["プレイヤー1", "プレイヤー2"]
    @Published private(set) var stage: UIImage?
    @Published var stageTitle = ""
    @Published private(set) var hiders: [Hider] = []
    @Published private(set) var shotsLeft = 0
    @Published private(set) var deadline = Date()
    @Published private(set) var seekStarted = Date()
    @Published private(set) var level: Int
    /// 塗る道具
    @Published var tool: Tool = .brush
    @Published var color: Color = Color(red: 0.4, green: 0.7, blue: 0.3)
    @Published var brushSize: CGFloat = 14

    private var pixels: [UInt8] = []
    private var undo: [UUID: [UIImage]] = [:]

    init() {
        level = max(1, UserDefaults.standard.integer(forKey: "chameleonLevel"))
    }

    // MARK: - ステージ

    func setStage(_ image: UIImage, title: String) {
        let normalized = Self.normalize(image)
        stage = normalized
        stageTitle = title
        pixels = Self.pixels(of: normalized)
    }

    /// 写真などを 900 × 1200 に切り抜いて縮める
    static func normalize(_ image: UIImage) -> UIImage {
        let size = stageSize
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            let ratio = max(size.width / image.size.width, size.height / image.size.height)
            let drawn = CGSize(width: image.size.width * ratio, height: image.size.height * ratio)
            image.draw(in: CGRect(x: (size.width - drawn.width) / 2, y: (size.height - drawn.height) / 2,
                                  width: drawn.width, height: drawn.height))
        }
    }

    private static func pixels(of image: UIImage) -> [UInt8] {
        guard let cg = image.cgImage else { return [] }
        let w = Int(stageSize.width), h = Int(stageSize.height)
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                          bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            context.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        return bytes
    }

    /// ステージのその場所の色（スポイト）
    func sampleColor(at point: CGPoint) -> Color? {
        let w = Int(Self.stageSize.width), h = Int(Self.stageSize.height)
        let x = Int(point.x), y = Int(point.y)
        guard x >= 0, y >= 0, x < w, y < h, !pixels.isEmpty else { return nil }
        // CGContext は下から上なので、上下を反転して読む
        let i = ((h - 1 - y) * w + x) * 4
        return Color(red: Double(pixels[i]) / 255, green: Double(pixels[i + 1]) / 255, blue: Double(pixels[i + 2]) / 255)
    }

    // MARK: - 始める

    var canStart: Bool { stage != nil }

    func start() {
        guard stage != nil else { return }
        if mode == .solo {
            hiders = makeComputerHiders()
            beginSeeking()
            phase = .seeking
        } else {
            hiders = names.enumerated().map { index, name in
                Hider(name: name.isEmpty ? "プレイヤー\(index + 1)" : name,
                      center: CGPoint(x: 220 + Double(index % 2) * 460, y: 380 + Double(index / 2) * 440),
                      paint: Self.blankPaint())
            }
            undo = [:]
            phase = .hideHandoff(0)
        }
    }

    func again() {
        phase = .setup
        hiders = []
    }

    static func blankPaint() -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: bitmapSize, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: bitmapSize))
        }
    }

    // MARK: - 隠れる

    func beginHiding(_ index: Int) {
        tool = .brush
        deadline = Date().addingTimeInterval(Self.hideSeconds)
        phase = .hiding(index)
        GameAudio.shared.playMusic(.jewel)
    }

    func finishHiding(_ index: Int) {
        guard phase == .hiding(index) else { return }
        GameAudio.shared.play(.place)
        if index + 1 < hiders.count {
            phase = .hideHandoff(index + 1)
        } else {
            GameAudio.shared.stopMusic()
            phase = .seekHandoff
        }
    }

    func move(_ index: Int, center: CGPoint? = nil, scale: CGFloat? = nil, angle: Double? = nil) {
        guard hiders.indices.contains(index) else { return }
        if let center {
            hiders[index].center = CGPoint(x: min(max(center.x, 40), Self.stageSize.width - 40),
                                           y: min(max(center.y, 40), Self.stageSize.height - 40))
        }
        if let scale { hiders[index].scale = min(max(scale, 0.45), 2.2) }
        if let angle { hiders[index].angle = angle }
    }

    func setShape(_ index: Int, _ shape: HiderShape) {
        guard hiders.indices.contains(index) else { return }
        hiders[index].shape = shape
    }

    /// ステージの点を、キャラの中の座標（-100…100, -70…70）にする
    static func local(_ point: CGPoint, in hider: Hider) -> CGPoint {
        let dx = point.x - hider.center.x, dy = point.y - hider.center.y
        let c = cos(-hider.angle), s = sin(-hider.angle)
        return CGPoint(x: (dx * c - dy * s) / hider.scale, y: (dx * s + dy * c) / hider.scale)
    }

    private static func bitmapPoint(_ local: CGPoint) -> CGPoint {
        CGPoint(x: (local.x + 100) * 2, y: (local.y + 70) * 2)
    }

    /// 塗り始め（元に戻すために、今の絵を取っておく）
    func beginStroke(_ index: Int) {
        guard hiders.indices.contains(index) else { return }
        var stack = undo[hiders[index].id] ?? []
        stack.append(hiders[index].paint)
        if stack.count > 30 { stack.removeFirst() }
        undo[hiders[index].id] = stack
    }

    func undoStroke(_ index: Int) {
        guard hiders.indices.contains(index), var stack = undo[hiders[index].id], let last = stack.popLast() else { return }
        hiders[index].paint = last
        undo[hiders[index].id] = stack
        GameAudio.shared.tick()
    }

    func canUndo(_ index: Int) -> Bool {
        hiders.indices.contains(index) && !(undo[hiders[index].id] ?? []).isEmpty
    }

    /// 筆・スプレー・消しゴムで、ステージの a から b まで塗る。width はステージ上の太さ
    func stroke(_ index: Int, from a: CGPoint, to b: CGPoint, width: CGFloat) {
        guard hiders.indices.contains(index) else { return }
        let hider = hiders[index]
        let p0 = Self.bitmapPoint(Self.local(a, in: hider))
        let p1 = Self.bitmapPoint(Self.local(b, in: hider))
        let lineWidth = width * 2 / hider.scale
        let ui = tool == .eraser ? UIColor.white : UIColor(color)
        let spray = tool == .spray
        hiders[index].paint = Self.draw(on: hider.paint) { c in
            if spray {
                // スプレー：少しずつ明るさの違う点をまわりに散らす（質感が出る）
                let distance = max(1, hypot(p1.x - p0.x, p1.y - p0.y))
                let count = Int(min(80, 10 + distance * 0.8))
                var h: CGFloat = 0, s: CGFloat = 0, v: CGFloat = 0, alpha: CGFloat = 0
                ui.getHue(&h, saturation: &s, brightness: &v, alpha: &alpha)
                for _ in 0..<count {
                    let t = CGFloat.random(in: 0...1)
                    let angle = CGFloat.random(in: 0...(2 * .pi))
                    let radius = CGFloat.random(in: 0...(lineWidth * 1.4))
                    let x = p0.x + (p1.x - p0.x) * t + cos(angle) * radius
                    let y = p0.y + (p1.y - p0.y) * t + sin(angle) * radius
                    let dot = CGFloat.random(in: 1.5...max(2, lineWidth * 0.22))
                    let shade = UIColor(hue: h, saturation: min(1, s * CGFloat.random(in: 0.8...1.15)),
                                        brightness: min(1, v * CGFloat.random(in: 0.75...1.2)), alpha: 0.9)
                    c.setFillColor(shade.cgColor)
                    c.fillEllipse(in: CGRect(x: x - dot, y: y - dot, width: dot * 2, height: dot * 2))
                }
            } else {
                c.setStrokeColor(ui.cgColor)
                c.setLineWidth(lineWidth)
                c.setLineCap(.round)
                c.setLineJoin(.round)
                c.move(to: p0)
                c.addLine(to: p1)
                c.strokePath()
            }
        }
    }

    func fill(_ index: Int) {
        guard hiders.indices.contains(index) else { return }
        let ui = UIColor(color)
        hiders[index].paint = Self.draw(on: hiders[index].paint) { c in
            c.setFillColor(ui.cgColor)
            c.fill(CGRect(origin: .zero, size: Self.bitmapSize))
        }
        GameAudio.shared.play(.place)
    }

    private static func draw(on image: UIImage, _ body: (CGContext) -> Void) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: bitmapSize, format: format).image { context in
            image.draw(at: .zero)
            body(context.cgContext)
        }
    }

    // MARK: - コンピュータが隠れる（ひとりで）

    /// 隠れる場所の背景を写し取って体に塗り、少しだけ色をずらす（レベルが上がるほど見分けにくい）
    private func makeComputerHiders() -> [Hider] {
        guard let stage else { return [] }
        let count = min(1 + (level - 1) / 2, 4)
        let tint = max(0.05, 0.26 - Double(level) * 0.025)
        var placed: [Hider] = []
        for i in 0..<count {
            var hider = Hider(name: "カメレオン\(i + 1)", shape: HiderShape.allCases.randomElement() ?? .chameleon,
                              center: .zero, scale: CGFloat.random(in: 0.65...1.25),
                              angle: Double.random(in: -0.5...0.5), paint: Self.blankPaint())
            // ほかと重ならない場所
            for _ in 0..<40 {
                hider.center = CGPoint(x: CGFloat.random(in: 120...(Self.stageSize.width - 120)),
                                       y: CGFloat.random(in: 120...(Self.stageSize.height - 120)))
                if placed.allSatisfy({ hypot($0.center.x - hider.center.x, $0.center.y - hider.center.y) > 240 }) { break }
            }
            hider.paint = Self.camouflage(for: hider, stage: stage, tint: tint)
            placed.append(hider)
        }
        return placed
    }

    private static func camouflage(for hider: Hider, stage: UIImage, tint: Double) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let shift = UIColor(hue: CGFloat.random(in: 0...1), saturation: 0.6, brightness: CGFloat.random(in: 0.3...1), alpha: 1)
        return UIGraphicsImageRenderer(size: bitmapSize, format: format).image { context in
            let c = context.cgContext
            // 体の画像の点 → ステージの点 の逆をたどって、ステージを描く
            c.saveGState()
            c.translateBy(x: 200, y: 140)
            c.scaleBy(x: 2 / hider.scale, y: 2 / hider.scale)
            c.rotate(by: -hider.angle)
            c.translateBy(x: -hider.center.x, y: -hider.center.y)
            stage.draw(at: .zero)
            c.restoreGState()
            c.setFillColor(shift.withAlphaComponent(tint).cgColor)
            c.fill(CGRect(origin: .zero, size: bitmapSize))
        }
    }

    // MARK: - 探す

    func beginSeeking() {
        for i in hiders.indices {
            hiders[i].found = false
            hiders[i].foundAfter = nil
        }
        shotsLeft = hiders.count + 3
        seekStarted = Date()
        deadline = Date().addingTimeInterval(Self.seekSeconds)
        phase = .seeking
        GameAudio.shared.playMusic(.candy)
    }

    /// その場所を撃つ。見つけたキャラを返す（はずれは nil）
    func shoot(at point: CGPoint) -> Hider? {
        guard phase == .seeking, shotsLeft > 0 else { return nil }
        shotsLeft -= 1
        var hit: Hider?
        for i in hiders.indices where !hiders[i].found {
            if hiders[i].shape.contains(Self.local(point, in: hiders[i])) {
                hiders[i].found = true
                hiders[i].foundAfter = Date().timeIntervalSince(seekStarted)
                hit = hiders[i]
                break
            }
        }
        if hit != nil {
            GameAudio.shared.play(.pop(combo: 4))
            GameAudio.shared.play(.special)
        } else {
            GameAudio.shared.play(.invalid)
        }
        if hiders.allSatisfy(\.found) || shotsLeft == 0 {
            Task {
                try? await Task.sleep(for: .seconds(1.1))
                finishSeeking()
            }
        }
        return hit
    }

    func finishSeeking() {
        guard phase == .seeking else { return }
        GameAudio.shared.stopMusic()
        let allFound = hiders.allSatisfy(\.found)
        if mode == .solo {
            GameAudio.shared.play(allFound ? .win : .lose)
            if allFound {
                level += 1
                UserDefaults.standard.set(level, forKey: "chameleonLevel")
            }
        } else {
            GameAudio.shared.play(.complete)
        }
        phase = .result
    }

    /// ひとりで：結果のあと、同じステージで次のレベル（またはもう一度）
    func nextRound() {
        hiders = makeComputerHiders()
        beginSeeking()
    }
}
