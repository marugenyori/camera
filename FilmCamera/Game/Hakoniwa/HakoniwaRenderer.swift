import SwiftUI

/// 箱庭を斜め上から見た絵（アイソメトリック）で描く。画像は使わず、すべて図形で描く。
/// マスは回転（90 度ずつ）してから、奥から手前の順に「土台の柱 → 置いたもの → いきもの」を重ねる
struct HLayout {
    let n: Int
    let rot: Int
    /// マスの横幅（画面上）
    let w: CGFloat
    /// 高さ 1 段ぶんの画面上の長さ
    let unit: CGFloat
    /// 箱庭の中心（高さ 0）の画面上の位置
    let center: CGPoint

    init(size: CGSize, n: Int, rot: Int, zoom: CGFloat, pan: CGSize) {
        self.n = n
        self.rot = rot
        let base = min(size.width * 0.94 / CGFloat(n), size.height * 0.62 / (CGFloat(n) * 0.5 + 3))
        w = base * zoom
        unit = w * 0.3
        center = CGPoint(x: size.width / 2 + pan.width, y: size.height * 0.5 + pan.height + w * 0.6)
    }

    /// 道具の列の見本用：マス 1 つを、決めた大きさ・位置に
    init(previewWidth: CGFloat, at point: CGPoint) {
        n = 1
        rot = 0
        w = previewWidth
        unit = previewWidth * 0.3
        center = point
    }

    /// 回したあとのマスの座標（gx, gy）と高さ z を、画面の位置に
    func p(_ gx: Double, _ gy: Double, _ z: Double) -> CGPoint {
        CGPoint(x: center.x + CGFloat(gx - gy) * w / 2,
                y: center.y + CGFloat(gx + gy - Double(n)) * w / 4 - CGFloat(z) * unit)
    }

    /// 元の座標（なめらかな位置）を、回したあとの座標に
    func rotated(_ x: Double, _ y: Double) -> (Double, Double) {
        let size = Double(n)
        switch rot {
        case 1: return (size - y, x)
        case 2: return (size - x, size - y)
        case 3: return (y, size - x)
        default: return (x, y)
        }
    }

    func rotatedCell(_ x: Int, _ y: Int) -> (Int, Int) {
        switch rot {
        case 1: return (n - 1 - y, x)
        case 2: return (n - 1 - x, n - 1 - y)
        case 3: return (y, n - 1 - x)
        default: return (x, y)
        }
    }

    func originalCell(_ i: Int, _ j: Int) -> (Int, Int) {
        switch rot {
        case 1: return (j, n - 1 - i)
        case 2: return (n - 1 - i, n - 1 - j)
        case 3: return (n - 1 - j, i)
        default: return (i, j)
        }
    }
}

enum HakoniwaRenderer {
    static let bottom = -0.7

    // MARK: - 全体

    @MainActor
    static func draw(_ context: inout GraphicsContext, size: CGSize, model: HakoniwaModel, time: Double) {
        let layout = HLayout(size: size, n: HakoniwaModel.size, rot: model.rotation, zoom: model.zoom, pan: model.pan)
        let tod = model.timeOfDay
        let night = nightAmount(tod)
        drawSky(&context, size: size, tod: tod, night: night, time: time)

        var glows: [(CGPoint, CGFloat)] = []
        context.drawLayer { layer in
            drawScene(&layer, layout: layout, model: model, time: time, night: night, glows: &glows)
            // 時間帯の色をかぶせる（箱庭の上だけ）
            var tint = overlay(tod)
            if model.weather != .clear {
                tint = blend(tint, (0.35, 0.4, 0.5, 0.22))
            }
            layer.blendMode = .sourceAtop
            layer.fill(Path(CGRect(origin: .zero, size: size)),
                       with: .color(Color(red: tint.0, green: tint.1, blue: tint.2).opacity(tint.3)))
        }
        // 夜の明かり
        if night > 0.05 {
            for (point, radius) in glows {
                let r = radius * (1 + 0.04 * CGFloat(sin(time * 3 + Double(point.x))))
                context.fill(Path(ellipseIn: CGRect(x: point.x - r, y: point.y - r, width: r * 2, height: r * 2)),
                             with: .radialGradient(Gradient(colors: [Color(red: 1, green: 0.85, blue: 0.45).opacity(0.55 * night),
                                                                     .clear]),
                                                   center: point, startRadius: 0, endRadius: r))
            }
        }
        drawWeather(&context, size: size, weather: model.weather, time: time)
    }

    @MainActor
    private static func drawScene(_ context: inout GraphicsContext, layout: HLayout, model: HakoniwaModel,
                                  time: Double, night: Double, glows: inout [(CGPoint, CGFloat)]) {
        let n = layout.n
        // 描く順番：マスは回したあとの (i + j + 1)、いきものは位置の和。小さい（奥）ものから
        enum Item { case cell(Int, Int), critter(HCritter) }
        var list: [(Double, Item)] = []
        for j in 0..<n {
            for i in 0..<n {
                list.append((Double(i + j + 1), .cell(i, j)))
            }
        }
        for critter in model.critters {
            let (gx, gy) = layout.rotated(critter.x, critter.y)
            list.append((gx + gy + 0.01, .critter(critter)))
        }
        list.sort { $0.0 < $1.0 }

        // 箱庭の下の影
        let shadow = Path { path in
            path.move(to: layout.p(0, 0, bottom - 0.3))
            path.addLine(to: layout.p(Double(n), 0, bottom - 0.3))
            path.addLine(to: layout.p(Double(n), Double(n), bottom - 0.3))
            path.addLine(to: layout.p(0, Double(n), bottom - 0.3))
            path.closeSubpath()
        }
        context.fill(shadow, with: .color(.black.opacity(0.18)))

        for (_, entry) in list {
            switch entry {
            case .cell(let i, let j):
                let (x, y) = layout.originalCell(i, j)
                guard let cell = model.cell(x, y) else { continue }
                let top = topHeight(cell)
                drawColumn(&context, layout: layout, i: i, j: j, cell: cell, top: top, seed: x * 31 + y * 17, time: time)
                if let item = cell.item {
                    drawItem(&context, layout: layout, item: item, gx: Double(i), gy: Double(j), top: top,
                             tint: cell.tint, seed: x * 13 + y * 7, time: time, night: night, glows: &glows)
                }
            case .critter(let critter):
                let cx = min(max(Int(critter.x), 0), n - 1)
                let cy = min(max(Int(critter.y), 0), n - 1)
                guard let cell = model.cell(cx, cy) else { continue }
                drawCritter(&context, layout: layout, critter: critter, top: topHeight(cell), time: time)
            }
        }
    }

    static func topHeight(_ cell: HCell) -> Double {
        Double(cell.height) - (cell.ground == .water ? 0.3 : 0)
    }

    // MARK: - 土台の柱

    private static let soilLeft = Color(red: 0.47, green: 0.33, blue: 0.22)
    private static let soilRight = Color(red: 0.58, green: 0.42, blue: 0.29)

    private static func polygon(_ points: [CGPoint]) -> Path {
        Path { path in
            guard let first = points.first else { return }
            path.move(to: first)
            for point in points.dropFirst() { path.addLine(to: point) }
            path.closeSubpath()
        }
    }

    private static func drawColumn(_ context: inout GraphicsContext, layout: HLayout, i: Int, j: Int, cell: HCell,
                                   top: Double, seed: Int, time: Double) {
        let gi = Double(i), gj = Double(j)
        let a = layout.p(gi, gj, top), b = layout.p(gi + 1, gj, top)
        let c = layout.p(gi + 1, gj + 1, top), d = layout.p(gi, gj + 1, top)
        // 横の面（左手前・右手前）
        let leftFace = polygon([d, c, layout.p(gi + 1, gj + 1, bottom), layout.p(gi, gj + 1, bottom)])
        let rightFace = polygon([b, c, layout.p(gi + 1, gj + 1, bottom), layout.p(gi + 1, gj, bottom)])
        context.fill(leftFace, with: .color(soilLeft))
        context.fill(rightFace, with: .color(soilRight))
        // いちばん上の帯（草・砂などの厚み）
        let band = top - 0.22
        context.fill(polygon([d, c, layout.p(gi + 1, gj + 1, band), layout.p(gi, gj + 1, band)]),
                     with: .color(cell.ground.band.opacity(0.95)))
        context.fill(polygon([b, c, layout.p(gi + 1, gj + 1, band), layout.p(gi + 1, gj, band)]),
                     with: .color(cell.ground.band))
        context.fill(leftFace, with: .color(.black.opacity(0.12)))

        // 上の面
        let topFace = polygon([a, b, c, d])
        context.fill(topFace, with: .color(cell.ground.top((i + j) % 2 == 0)))
        context.stroke(topFace, with: .color(.black.opacity(0.06)), lineWidth: 0.5)

        switch cell.ground {
        case .water:
            // きらきら動く波
            for k in 0..<2 {
                let f = (time * 0.25 + Double(k) * 0.5 + hash(seed + k) * 0.7).truncatingRemainder(dividingBy: 1)
                let start = layout.p(gi + 0.15 + 0.3 * hash(seed + 5 + k), gj + 0.1 + f * 0.8, top)
                let end = layout.p(gi + 0.45 + 0.3 * hash(seed + 5 + k), gj + 0.1 + f * 0.8, top)
                var wave = Path()
                wave.move(to: start)
                wave.addLine(to: end)
                context.stroke(wave, with: .color(.white.opacity(0.55 * sin(f * .pi))),
                               style: StrokeStyle(lineWidth: max(layout.w * 0.03, 0.8), lineCap: .round))
            }
        case .meadow:
            let colors: [Color] = [.white, .yellow, .pink, Color(red: 0.7, green: 0.6, blue: 1)]
            for k in 0..<6 {
                let point = layout.p(gi + 0.15 + 0.7 * hash(seed + k), gj + 0.15 + 0.7 * hash(seed + 40 + k), top)
                let r = layout.w * 0.03
                context.fill(Path(ellipseIn: CGRect(x: point.x - r, y: point.y - r * 0.7, width: r * 2, height: r * 1.4)),
                             with: .color(colors[(seed + k) % colors.count]))
            }
        case .farm:
            for k in 1..<4 {
                let gy = gj + Double(k) * 0.25
                var row = Path()
                row.move(to: layout.p(gi + 0.08, gy, top))
                row.addLine(to: layout.p(gi + 0.92, gy, top))
                context.stroke(row, with: .color(Color(red: 0.4, green: 0.27, blue: 0.16)),
                               lineWidth: max(layout.w * 0.04, 1))
                // 芽
                for m in 0..<3 {
                    let sprout = layout.p(gi + 0.2 + Double(m) * 0.3, gy, top)
                    let r = layout.w * 0.022
                    context.fill(Path(ellipseIn: CGRect(x: sprout.x - r, y: sprout.y - r * 2, width: r * 2, height: r * 2)),
                                 with: .color(Color(red: 0.45, green: 0.75, blue: 0.3)))
                }
            }
        case .path:
            for k in 0..<4 {
                let point = layout.p(gi + 0.2 + 0.6 * hash(seed + k), gj + 0.2 + 0.6 * hash(seed + 20 + k), top)
                let r = layout.w * (0.05 + 0.03 * hash(seed + 60 + k))
                context.fill(Path(ellipseIn: CGRect(x: point.x - r, y: point.y - r * 0.5, width: r * 2, height: r)),
                             with: .color(.white.opacity(0.25)))
            }
        default:
            break
        }
    }

    // MARK: - 置いたもの

    private static let roofColors: [Color] = [
        Color(red: 0.85, green: 0.3, blue: 0.25), Color(red: 0.25, green: 0.45, blue: 0.75),
        Color(red: 0.3, green: 0.6, blue: 0.4), Color(red: 0.55, green: 0.38, blue: 0.3),
        Color(red: 0.6, green: 0.4, blue: 0.7),
    ]
    private static let tentColors: [Color] = [
        Color(red: 0.95, green: 0.55, blue: 0.2), Color(red: 0.35, green: 0.65, blue: 0.45),
        Color(red: 0.35, green: 0.55, blue: 0.85),
    ]
    private static let wood = Color(red: 0.55, green: 0.38, blue: 0.24)

    static func drawItem(_ context: inout GraphicsContext, layout: HLayout, item: HItem, gx: Double, gy: Double,
                         top: Double, tint: Int, seed: Int, time: Double, night: Double,
                         glows: inout [(CGPoint, CGFloat)]) {
        let w = layout.w
        let c = layout.p(gx + 0.5, gy + 0.5, top)
        func circle(_ point: CGPoint, _ r: CGFloat, _ color: Color) {
            context.fill(Path(ellipseIn: CGRect(x: point.x - r, y: point.y - r, width: r * 2, height: r * 2)), with: .color(color))
        }
        func shadow(_ width: CGFloat) {
            context.fill(Path(ellipseIn: CGRect(x: c.x - width / 2, y: c.y - width * 0.2, width: width, height: width * 0.4)),
                         with: .color(.black.opacity(0.18)))
        }
        func line(_ from: CGPoint, _ to: CGPoint, _ color: Color, _ width: CGFloat) {
            var path = Path()
            path.move(to: from)
            path.addLine(to: to)
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round))
        }
        // 風で少しゆれる
        let sway = CGFloat(sin(time * 1.6 + Double(seed))) * w * 0.012

        switch item {
        case .tree, .sakura:
            shadow(w * 0.45)
            context.fill(Path(CGRect(x: c.x - w * 0.035, y: c.y - w * 0.3, width: w * 0.07, height: w * 0.3)),
                         with: .color(wood))
            let leaf = item == .tree ? Color(red: 0.25, green: 0.55, blue: 0.28) : Color(red: 0.95, green: 0.62, blue: 0.75)
            let light = item == .tree ? Color(red: 0.38, green: 0.7, blue: 0.35) : Color(red: 1, green: 0.8, blue: 0.87)
            let crown = CGPoint(x: c.x + sway, y: c.y - w * 0.45)
            circle(CGPoint(x: crown.x - w * 0.1, y: crown.y + w * 0.06), w * 0.15, leaf)
            circle(CGPoint(x: crown.x + w * 0.11, y: crown.y + w * 0.05), w * 0.14, leaf)
            circle(crown, w * 0.19, leaf)
            circle(CGPoint(x: crown.x - w * 0.06, y: crown.y - w * 0.06), w * 0.1, light)
        case .pine:
            shadow(w * 0.4)
            context.fill(Path(CGRect(x: c.x - w * 0.03, y: c.y - w * 0.14, width: w * 0.06, height: w * 0.14)),
                         with: .color(wood))
            for k in 0..<3 {
                let half = w * (0.2 - CGFloat(k) * 0.045)
                let baseY = c.y - w * (0.1 + CGFloat(k) * 0.17)
                let tip = CGPoint(x: c.x + sway * CGFloat(k + 1) * 0.5, y: baseY - w * 0.28)
                context.fill(polygon([CGPoint(x: c.x - half, y: baseY), CGPoint(x: c.x + half, y: baseY), tip]),
                             with: .color(Color(red: 0.13, green: 0.42, blue: 0.3)))
                context.fill(polygon([CGPoint(x: c.x, y: baseY), CGPoint(x: c.x + half, y: baseY), tip]),
                             with: .color(Color(red: 0.18, green: 0.5, blue: 0.35)))
            }
        case .bush:
            shadow(w * 0.5)
            let green = Color(red: 0.3, green: 0.6, blue: 0.3)
            circle(CGPoint(x: c.x - w * 0.12, y: c.y - w * 0.08), w * 0.12, green)
            circle(CGPoint(x: c.x + w * 0.12, y: c.y - w * 0.07), w * 0.11, green)
            circle(CGPoint(x: c.x + sway, y: c.y - w * 0.14), w * 0.14, Color(red: 0.36, green: 0.68, blue: 0.34))
            circle(CGPoint(x: c.x - w * 0.03, y: c.y - w * 0.2), w * 0.03, Color(red: 0.95, green: 0.3, blue: 0.35))
        case .flowers:
            let colors: [Color] = [.red, .yellow, .pink, .white, .orange, Color(red: 0.6, green: 0.5, blue: 1)]
            for k in 0..<7 {
                let point = layout.p(gx + 0.15 + 0.7 * hash(seed + k), gy + 0.15 + 0.7 * hash(seed + 30 + k), top)
                let head = CGPoint(x: point.x + sway, y: point.y - w * 0.09)
                line(point, head, Color(red: 0.3, green: 0.6, blue: 0.3), max(w * 0.015, 0.6))
                circle(head, w * 0.035, colors[(seed + k) % colors.count])
                circle(head, w * 0.012, .yellow)
            }
        case .rock:
            shadow(w * 0.45)
            let rock = polygon([CGPoint(x: c.x - w * 0.2, y: c.y - w * 0.02), CGPoint(x: c.x - w * 0.15, y: c.y - w * 0.16),
                                CGPoint(x: c.x - w * 0.02, y: c.y - w * 0.22), CGPoint(x: c.x + w * 0.14, y: c.y - w * 0.17),
                                CGPoint(x: c.x + w * 0.2, y: c.y - w * 0.03), CGPoint(x: c.x + w * 0.05, y: c.y + w * 0.04)])
            context.fill(rock, with: .color(Color(red: 0.55, green: 0.56, blue: 0.58)))
            context.fill(polygon([CGPoint(x: c.x - w * 0.15, y: c.y - w * 0.16), CGPoint(x: c.x - w * 0.02, y: c.y - w * 0.22),
                                  CGPoint(x: c.x + w * 0.14, y: c.y - w * 0.17), CGPoint(x: c.x + w * 0.02, y: c.y - w * 0.1)]),
                         with: .color(Color(red: 0.72, green: 0.73, blue: 0.75)))
        case .house:
            drawHouse(&context, layout: layout, gx: gx, gy: gy, top: top, roof: roofColors[tint % roofColors.count],
                      night: night, glows: &glows)
        case .lamp:
            let head = CGPoint(x: c.x, y: c.y - w * 0.6)
            line(c, head, Color(red: 0.2, green: 0.22, blue: 0.25), max(w * 0.035, 1))
            circle(head, w * 0.06, night > 0.3 ? Color(red: 1, green: 0.92, blue: 0.6) : Color(red: 0.85, green: 0.88, blue: 0.9))
            context.fill(polygon([CGPoint(x: head.x - w * 0.07, y: head.y - w * 0.04), CGPoint(x: head.x + w * 0.07, y: head.y - w * 0.04),
                                  CGPoint(x: head.x, y: head.y - w * 0.11)]),
                         with: .color(Color(red: 0.2, green: 0.22, blue: 0.25)))
            glows.append((head, w * 0.9))
        case .fence:
            let posts = [0.08, 0.5, 0.92]
            for z in [0.32, 0.6] {
                line(layout.p(gx + 0.08, gy + 0.5, top + z), layout.p(gx + 0.92, gy + 0.5, top + z), wood, max(w * 0.03, 1))
            }
            for post in posts {
                line(layout.p(gx + post, gy + 0.5, top), layout.p(gx + post, gy + 0.5, top + 0.8),
                     Color(red: 0.45, green: 0.3, blue: 0.18), max(w * 0.045, 1.2))
            }
        case .bench:
            shadow(w * 0.45)
            let seatZ = top + 0.45
            for (lx, ly) in [(0.3, 0.5), (0.7, 0.5), (0.3, 0.62), (0.7, 0.62)] {
                line(layout.p(gx + lx, gy + ly, top), layout.p(gx + lx, gy + ly, seatZ), Color(red: 0.25, green: 0.25, blue: 0.27),
                     max(w * 0.025, 0.8))
            }
            context.fill(polygon([layout.p(gx + 0.25, gy + 0.46, seatZ), layout.p(gx + 0.75, gy + 0.46, seatZ),
                                  layout.p(gx + 0.75, gy + 0.64, seatZ), layout.p(gx + 0.25, gy + 0.64, seatZ)]),
                         with: .color(wood))
            context.fill(polygon([layout.p(gx + 0.25, gy + 0.46, seatZ), layout.p(gx + 0.75, gy + 0.46, seatZ),
                                  layout.p(gx + 0.75, gy + 0.46, seatZ + 0.45), layout.p(gx + 0.25, gy + 0.46, seatZ + 0.45)]),
                         with: .color(Color(red: 0.62, green: 0.44, blue: 0.28)))
        case .tent:
            let color = tentColors[tint % tentColors.count]
            let ridgeBack = layout.p(gx + 0.5, gy + 0.18, top + 1.3)
            let ridgeFront = layout.p(gx + 0.5, gy + 0.82, top + 1.3)
            shadow(w * 0.6)
            // 奥の斜面 → 手前右の斜面 → 入口の三角
            context.fill(polygon([layout.p(gx + 0.18, gy + 0.18, top), layout.p(gx + 0.18, gy + 0.82, top), ridgeFront, ridgeBack]),
                         with: .color(color.opacity(0.75)))
            context.fill(polygon([layout.p(gx + 0.82, gy + 0.18, top), layout.p(gx + 0.82, gy + 0.82, top), ridgeFront, ridgeBack]),
                         with: .color(color))
            let frontLeft = layout.p(gx + 0.18, gy + 0.82, top), frontRight = layout.p(gx + 0.82, gy + 0.82, top)
            context.fill(polygon([frontLeft, frontRight, ridgeFront]), with: .color(color.opacity(0.85)))
            context.fill(polygon([layout.p(gx + 0.38, gy + 0.82, top), layout.p(gx + 0.62, gy + 0.82, top),
                                  layout.p(gx + 0.5, gy + 0.82, top + 0.8)]),
                         with: .color(.black.opacity(0.45)))
            glows.append((layout.p(gx + 0.5, gy + 0.82, top + 0.3), w * 0.5))
        case .boat:
            let bob = sin(time * 2 + Double(seed)) * 0.06
            let z = top + 0.15 + bob
            let rim: [(Double, Double)] = [(0.15, 0.5), (0.35, 0.36), (0.72, 0.4), (0.88, 0.5), (0.72, 0.6), (0.35, 0.64)]
            context.fill(polygon(rim.map { layout.p(gx + $0.0, gy + $0.1, z - 0.25) }), with: .color(Color(red: 0.4, green: 0.26, blue: 0.16)))
            context.fill(polygon(rim.map { layout.p(gx + $0.0, gy + $0.1, z) }), with: .color(wood))
            let mastBase = layout.p(gx + 0.5, gy + 0.5, z)
            let mastTop = layout.p(gx + 0.5, gy + 0.5, z + 2)
            line(mastBase, mastTop, Color(red: 0.35, green: 0.25, blue: 0.18), max(w * 0.025, 0.8))
            context.fill(polygon([CGPoint(x: mastTop.x + w * 0.02, y: mastTop.y),
                                  CGPoint(x: mastBase.x + w * 0.02, y: mastBase.y - w * 0.06),
                                  CGPoint(x: mastBase.x + w * 0.24, y: mastBase.y - w * 0.08)]),
                         with: .color(.white))
        }
    }

    private static func drawHouse(_ context: inout GraphicsContext, layout: HLayout, gx: Double, gy: Double, top: Double,
                                  roof: Color, night: Double, glows: inout [(CGPoint, CGFloat)]) {
        let x0 = gx + 0.18, x1 = gx + 0.82, y0 = gy + 0.18, y1 = gy + 0.82
        let wall = top + 1.3
        let wallLeft = Color(red: 0.88, green: 0.83, blue: 0.74)
        let wallRight = Color(red: 0.97, green: 0.93, blue: 0.85)
        context.fill(polygon([layout.p(x0, y1 + 0.05, top - 0.05), layout.p(x1 + 0.05, y1 + 0.05, top - 0.05),
                              layout.p(x1 + 0.05, y0, top - 0.05), layout.p(x1, y0, top)]),
                     with: .color(.black.opacity(0.15)))
        context.fill(polygon([layout.p(x0, y1, top), layout.p(x1, y1, top), layout.p(x1, y1, wall), layout.p(x0, y1, wall)]),
                     with: .color(wallLeft))
        context.fill(polygon([layout.p(x1, y0, top), layout.p(x1, y1, top), layout.p(x1, y1, wall), layout.p(x1, y0, wall)]),
                     with: .color(wallRight))
        // 窓と扉
        let lit = night > 0.3
        let window = lit ? Color(red: 1, green: 0.85, blue: 0.45) : Color(red: 0.42, green: 0.55, blue: 0.68)
        let leftWindow = [layout.p(x0 + 0.1, y1, top + 0.55), layout.p(x0 + 0.27, y1, top + 0.55),
                          layout.p(x0 + 0.27, y1, top + 0.95), layout.p(x0 + 0.1, y1, top + 0.95)]
        context.fill(polygon(leftWindow), with: .color(window))
        let rightWindow = [layout.p(x1, y0 + 0.14, top + 0.55), layout.p(x1, y0 + 0.31, top + 0.55),
                           layout.p(x1, y0 + 0.31, top + 0.95), layout.p(x1, y0 + 0.14, top + 0.95)]
        context.fill(polygon(rightWindow), with: .color(window))
        context.fill(polygon([layout.p(x1 - 0.28, y1, top), layout.p(x1 - 0.1, y1, top),
                              layout.p(x1 - 0.1, y1, top + 0.8), layout.p(x1 - 0.28, y1, top + 0.8)]),
                     with: .color(Color(red: 0.5, green: 0.32, blue: 0.2)))
        glows.append((layout.p(x0 + 0.18, y1, top + 0.75), layout.w * 0.45))
        glows.append((layout.p(x1, y0 + 0.22, top + 0.75), layout.w * 0.45))
        // 屋根（四角すい）。奥の面から描く
        let e = 0.08
        let e00 = layout.p(x0 - e, y0 - e, wall), e10 = layout.p(x1 + e, y0 - e, wall)
        let e11 = layout.p(x1 + e, y1 + e, wall), e01 = layout.p(x0 - e, y1 + e, wall)
        let apex = layout.p((x0 + x1) / 2, (y0 + y1) / 2, wall + 1.1)
        context.fill(polygon([e00, e01, apex]), with: .color(roof.opacity(0.8)))
        context.fill(polygon([e00, e10, apex]), with: .color(roof.opacity(0.8)))
        context.fill(polygon([e01, e11, apex]), with: .color(roof))
        context.fill(polygon([e01, e11, apex]), with: .color(.black.opacity(0.15)))
        context.fill(polygon([e10, e11, apex]), with: .color(roof))
        // 煙突
        let chimney = layout.p(x1 - 0.15, y0 + 0.2, wall + 0.5)
        context.fill(Path(CGRect(x: chimney.x - layout.w * 0.03, y: chimney.y - layout.w * 0.12,
                                 width: layout.w * 0.06, height: layout.w * 0.12)),
                     with: .color(Color(red: 0.45, green: 0.3, blue: 0.25)))
    }

    // MARK: - いきもの

    private static let shirts: [Color] = [.red, .blue, Color(red: 1, green: 0.75, blue: 0.1), .green, .purple, .orange]
    private static let catColors: [Color] = [.orange, .gray, Color(white: 0.2), .white, Color(red: 0.9, green: 0.8, blue: 0.6), .orange]

    static func drawCritter(_ context: inout GraphicsContext, layout: HLayout, critter: HCritter, top: Double, time: Double) {
        let (gx, gy) = layout.rotated(critter.x, critter.y)
        let base = layout.p(gx, gy, top)
        let w = layout.w
        // 進む向き（画面の左右）
        let (tgx, tgy) = layout.rotated(Double(critter.tx) + 0.5, Double(critter.ty) + 0.5)
        let target = layout.p(tgx, tgy, top)
        let dir: CGFloat = target.x < base.x - 0.5 ? -1 : 1
        let moving = critter.wait <= 0 && abs(target.x - base.x) + abs(target.y - base.y) > 0.5
        let bob = moving ? CGFloat(abs(sin(critter.step * 10))) * w * 0.025 : 0
        func circle(_ point: CGPoint, _ r: CGFloat, _ color: Color) {
            context.fill(Path(ellipseIn: CGRect(x: point.x - r, y: point.y - r, width: r * 2, height: r * 2)), with: .color(color))
        }
        func ellipse(_ point: CGPoint, _ rx: CGFloat, _ ry: CGFloat, _ color: Color) {
            context.fill(Path(ellipseIn: CGRect(x: point.x - rx, y: point.y - ry, width: rx * 2, height: ry * 2)), with: .color(color))
        }
        if !critter.kind.swims {
            ellipse(base, w * 0.11, w * 0.04, .black.opacity(0.2))
        }
        let c = CGPoint(x: base.x, y: base.y - bob)
        switch critter.kind {
        case .person:
            let legSwing = moving ? CGFloat(sin(critter.step * 10)) * w * 0.025 : 0
            var legs = Path()
            legs.move(to: CGPoint(x: c.x - w * 0.025, y: c.y - w * 0.1))
            legs.addLine(to: CGPoint(x: c.x - w * 0.025 + legSwing, y: c.y))
            legs.move(to: CGPoint(x: c.x + w * 0.025, y: c.y - w * 0.1))
            legs.addLine(to: CGPoint(x: c.x + w * 0.025 - legSwing, y: c.y))
            context.stroke(legs, with: .color(Color(red: 0.2, green: 0.25, blue: 0.4)),
                           style: StrokeStyle(lineWidth: max(w * 0.035, 1), lineCap: .round))
            context.fill(Path(roundedRect: CGRect(x: c.x - w * 0.06, y: c.y - w * 0.26, width: w * 0.12, height: w * 0.17),
                              cornerRadius: w * 0.04),
                         with: .color(shirts[critter.tint % shirts.count]))
            circle(CGPoint(x: c.x, y: c.y - w * 0.32), w * 0.055, Color(red: 1, green: 0.85, blue: 0.72))
            context.fill(Path(ellipseIn: CGRect(x: c.x - w * 0.058, y: c.y - w * 0.385, width: w * 0.116, height: w * 0.06)),
                         with: .color(critter.tint % 2 == 0 ? Color(red: 0.25, green: 0.18, blue: 0.12) : Color(red: 0.6, green: 0.4, blue: 0.2)))
        case .cat, .dog:
            let isDog = critter.kind == .dog
            let color = isDog ? (critter.tint % 2 == 0 ? Color(red: 0.75, green: 0.55, blue: 0.3) : .white)
                : catColors[critter.tint % catColors.count]
            let size: CGFloat = isDog ? 1.25 : 1
            ellipse(CGPoint(x: c.x, y: c.y - w * 0.07 * size), w * 0.1 * size, w * 0.05 * size, color)
            let head = CGPoint(x: c.x + dir * w * 0.1 * size, y: c.y - w * 0.13 * size)
            circle(head, w * 0.05 * size, color)
            if isDog {
                ellipse(CGPoint(x: head.x - dir * w * 0.03, y: head.y + w * 0.01), w * 0.02, w * 0.035,
                        Color(red: 0.45, green: 0.3, blue: 0.18))
            } else {
                for side in [-1.0, 1.0] {
                    let ex = head.x + CGFloat(side) * w * 0.03
                    context.fill(polygon([CGPoint(x: ex - w * 0.02, y: head.y - w * 0.03), CGPoint(x: ex + w * 0.02, y: head.y - w * 0.03),
                                          CGPoint(x: ex, y: head.y - w * 0.075)]), with: .color(color))
                }
            }
            var tail = Path()
            tail.move(to: CGPoint(x: c.x - dir * w * 0.09 * size, y: c.y - w * 0.08 * size))
            tail.addQuadCurve(to: CGPoint(x: c.x - dir * w * 0.14 * size, y: c.y - w * 0.18 * size),
                              control: CGPoint(x: c.x - dir * w * 0.17 * size, y: c.y - w * 0.08 * size))
            context.stroke(tail, with: .color(color), style: StrokeStyle(lineWidth: max(w * 0.025, 0.8), lineCap: .round))
            circle(CGPoint(x: head.x + dir * w * 0.02, y: head.y - w * 0.005), max(w * 0.008, 0.6), .black)
        case .duck:
            let float = CGFloat(sin(time * 2.5 + critter.x)) * w * 0.01
            let body = CGPoint(x: c.x, y: c.y - w * 0.03 + float)
            ellipse(CGPoint(x: body.x, y: body.y + w * 0.02), w * 0.13, w * 0.03, .white.opacity(0.35))
            let color = critter.tint % 2 == 0 ? Color.white : Color(red: 1, green: 0.88, blue: 0.3)
            ellipse(body, w * 0.09, w * 0.05, color)
            let head = CGPoint(x: body.x + dir * w * 0.07, y: body.y - w * 0.07)
            circle(head, w * 0.04, color)
            ellipse(CGPoint(x: head.x + dir * w * 0.045, y: head.y + w * 0.005), w * 0.025, w * 0.012, .orange)
            circle(CGPoint(x: head.x + dir * w * 0.012, y: head.y - w * 0.01), max(w * 0.007, 0.5), .black)
        case .chicken:
            let peck = critter.wait > 0 ? CGFloat(max(0, sin(time * 8 + critter.x))) * w * 0.03 : 0
            ellipse(CGPoint(x: c.x, y: c.y - w * 0.08), w * 0.07, w * 0.06, .white)
            let head = CGPoint(x: c.x + dir * w * 0.06, y: c.y - w * 0.15 + peck)
            circle(head, w * 0.035, .white)
            circle(CGPoint(x: head.x, y: head.y - w * 0.035), w * 0.015, .red)
            context.fill(polygon([CGPoint(x: head.x + dir * w * 0.03, y: head.y - w * 0.005),
                                  CGPoint(x: head.x + dir * w * 0.06, y: head.y + w * 0.005),
                                  CGPoint(x: head.x + dir * w * 0.03, y: head.y + w * 0.015)]), with: .color(.orange))
            var legs = Path()
            legs.move(to: CGPoint(x: c.x - w * 0.015, y: c.y - w * 0.03))
            legs.addLine(to: CGPoint(x: c.x - w * 0.015, y: c.y))
            legs.move(to: CGPoint(x: c.x + w * 0.015, y: c.y - w * 0.03))
            legs.addLine(to: CGPoint(x: c.x + w * 0.015, y: c.y))
            context.stroke(legs, with: .color(.orange), lineWidth: max(w * 0.012, 0.6))
        }
    }

    // MARK: - 空・時間・天気

    /// 夜のぐあい（0＝昼、1＝真夜中）
    static func nightAmount(_ t: Double) -> Double {
        interpolate(t, [(0, 1), (0.2, 1), (0.28, 0.25), (0.33, 0), (0.7, 0), (0.78, 0.45), (0.86, 1), (1, 1)])
    }

    private static func overlay(_ t: Double) -> (Double, Double, Double, Double) {
        let keys: [(Double, (Double, Double, Double, Double))] = [
            (0, (0.03, 0.06, 0.22, 0.55)), (0.2, (0.03, 0.06, 0.22, 0.55)), (0.25, (0.6, 0.35, 0.5, 0.25)),
            (0.31, (1, 0.85, 0.6, 0.08)), (0.4, (1, 1, 1, 0)), (0.62, (1, 1, 1, 0)), (0.69, (1, 0.8, 0.5, 0.1)),
            (0.75, (1, 0.45, 0.15, 0.28)), (0.82, (0.3, 0.2, 0.5, 0.42)), (0.88, (0.03, 0.06, 0.22, 0.55)),
            (1, (0.03, 0.06, 0.22, 0.55)),
        ]
        for k in 1..<keys.count where t <= keys[k].0 {
            let (t0, a) = keys[k - 1], (t1, b) = keys[k]
            let f = (t - t0) / max(t1 - t0, 0.0001)
            return (a.0 + (b.0 - a.0) * f, a.1 + (b.1 - a.1) * f, a.2 + (b.2 - a.2) * f, a.3 + (b.3 - a.3) * f)
        }
        return keys[0].1
    }

    private static func blend(_ a: (Double, Double, Double, Double), _ b: (Double, Double, Double, Double))
        -> (Double, Double, Double, Double) {
        let alpha = a.3 + b.3 * (1 - a.3)
        guard alpha > 0 else { return b }
        func mix(_ x: Double, _ y: Double) -> Double { (x * a.3 + y * b.3 * (1 - a.3)) / alpha }
        return (mix(a.0, b.0), mix(a.1, b.1), mix(a.2, b.2), alpha)
    }

    private static func interpolate(_ t: Double, _ keys: [(Double, Double)]) -> Double {
        for k in 1..<keys.count where t <= keys[k].0 {
            let f = (t - keys[k - 1].0) / max(keys[k].0 - keys[k - 1].0, 0.0001)
            return keys[k - 1].1 + (keys[k].1 - keys[k - 1].1) * f
        }
        return keys.last?.1 ?? 0
    }

    private static func drawSky(_ context: inout GraphicsContext, size: CGSize, tod: Double, night: Double, time: Double) {
        let dusk = max(0, 1 - abs(tod - 0.76) / 0.07) + max(0, 1 - abs(tod - 0.25) / 0.06) * 0.7
        func mix(_ day: (Double, Double, Double), _ evening: (Double, Double, Double), _ dark: (Double, Double, Double)) -> Color {
            let d = min(dusk, 1)
            var r = day.0 + (evening.0 - day.0) * d, g = day.1 + (evening.1 - day.1) * d, b = day.2 + (evening.2 - day.2) * d
            r += (dark.0 - r) * night; g += (dark.1 - g) * night; b += (dark.2 - b) * night
            return Color(red: r, green: g, blue: b)
        }
        let topColor = mix((0.42, 0.7, 0.95), (0.38, 0.35, 0.65), (0.03, 0.05, 0.16))
        let bottomColor = mix((0.82, 0.93, 1), (1, 0.62, 0.42), (0.12, 0.13, 0.3))
        context.fill(Path(CGRect(origin: .zero, size: size)),
                     with: .linearGradient(Gradient(colors: [topColor, bottomColor]),
                                           startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
        if night > 0.1 {
            for k in 0..<70 {
                let x = hash(k * 3) * size.width, y = hash(k * 7 + 1) * size.height * 0.55
                let twinkle = 0.5 + 0.5 * sin(time * (1 + hash(k)) * 2 + Double(k))
                let r = CGFloat(0.6 + hash(k * 11) * 1.2)
                context.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                             with: .color(.white.opacity(night * (0.4 + 0.6 * twinkle))))
            }
        }
    }

    private static func drawWeather(_ context: inout GraphicsContext, size: CGSize, weather: HakoniwaModel.Weather,
                                    time: Double) {
        switch weather {
        case .clear:
            break
        case .rain:
            var drops = Path()
            for k in 0..<140 {
                let x = (hash(k) + time * 0.05).truncatingRemainder(dividingBy: 1) * (size.width + 40) - 20
                let y = (hash(k + 500) + time * (1.1 + hash(k + 900) * 0.5)).truncatingRemainder(dividingBy: 1) * (size.height + 40) - 20
                drops.move(to: CGPoint(x: x, y: y))
                drops.addLine(to: CGPoint(x: x - 3, y: y + 14))
            }
            context.stroke(drops, with: .color(.white.opacity(0.45)), lineWidth: 1)
        case .snow:
            for k in 0..<110 {
                let y = (hash(k + 300) + time * (0.06 + hash(k + 700) * 0.05)).truncatingRemainder(dividingBy: 1) * (size.height + 20) - 10
                let x = hash(k) * size.width + CGFloat(sin(time * 1.3 + Double(k))) * 10
                let r = CGFloat(1.5 + hash(k + 100) * 2)
                context.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                             with: .color(.white.opacity(0.85)))
            }
        }
    }

    /// 0〜1 の決まった乱数（毎回同じ数を返すので、模様が動かない）
    static func hash(_ k: Int) -> Double {
        let x = sin(Double(k) * 12.9898 + 78.233) * 43758.5453
        return x - x.rounded(.down)
    }

    // MARK: - タップしたマス

    /// 画面の点にあるマス（元の座標）。手前の柱から順に調べる
    @MainActor
    static func cell(at point: CGPoint, size: CGSize, model: HakoniwaModel) -> (Int, Int)? {
        let layout = HLayout(size: size, n: HakoniwaModel.size, rot: model.rotation, zoom: model.zoom, pan: model.pan)
        let n = layout.n
        var order: [(Int, Int)] = []
        for j in 0..<n { for i in 0..<n { order.append((i, j)) } }
        order.sort { ($0.0 + $0.1) > ($1.0 + $1.1) }
        for (i, j) in order {
            let (x, y) = layout.originalCell(i, j)
            guard let cell = model.cell(x, y) else { continue }
            let top = topHeight(cell)
            let gi = Double(i), gj = Double(j)
            let column = polygon([layout.p(gi, gj, top), layout.p(gi + 1, gj, top), layout.p(gi + 1, gj, 0),
                                  layout.p(gi + 1, gj + 1, 0), layout.p(gi, gj + 1, 0), layout.p(gi, gj + 1, top)])
            let topFace = polygon([layout.p(gi, gj, top), layout.p(gi + 1, gj, top),
                                   layout.p(gi + 1, gj + 1, top), layout.p(gi, gj + 1, top)])
            if topFace.contains(point) || column.contains(point) { return (x, y) }
        }
        return nil
    }
}
