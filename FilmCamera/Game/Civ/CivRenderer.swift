import SwiftUI

/// 「ふたりの文明」の地図を、箱庭と同じ斜め上からの絵で描く（木・家・ボートは箱庭の絵を小さくして使う）
enum CivRenderer {
    /// プレイヤーの色（1 人目＝オレンジ、2 人目＝青）
    static let playerColors: [Color] = [Color(red: 0.95, green: 0.5, blue: 0.15), Color(red: 0.2, green: 0.5, blue: 0.95)]

    static func color(of player: Int) -> Color {
        playerColors[max(player, 0) % playerColors.count]
    }

    static func layout(size: CGSize, zoom: CGFloat, pan: CGSize) -> HLayout {
        HLayout(size: size, n: CivState.size, rot: 0, zoom: zoom, pan: pan)
    }

    static func topHeight(_ tile: CivTile) -> Double {
        guard tile.revealed else { return 1 }
        return tile.terrain == .water ? -0.3 : Double(tile.terrain.height)
    }

    private static func polygon(_ points: [CGPoint]) -> Path {
        Path { path in
            guard let first = points.first else { return }
            path.move(to: first)
            for point in points.dropFirst() { path.addLine(to: point) }
            path.closeSubpath()
        }
    }

    private static func topColor(_ terrain: CivTerrain, odd: Bool) -> Color {
        let shade = odd ? 0.03 : 0
        switch terrain {
        case .grass: return Color(red: 0.47 + shade, green: 0.74 + shade, blue: 0.35)
        case .plains: return Color(red: 0.76 + shade, green: 0.78 + shade, blue: 0.43)
        case .forest: return Color(red: 0.33 + shade, green: 0.58 + shade, blue: 0.3)
        case .hills: return Color(red: 0.57 + shade, green: 0.66 + shade, blue: 0.4)
        case .mountain: return Color(red: 0.55 + shade, green: 0.53 + shade, blue: 0.5)
        case .water: return Color(red: 0.3, green: 0.6 + shade, blue: 0.88)
        case .desert: return Color(red: 0.93, green: 0.84 + shade, blue: 0.58)
        }
    }

    // MARK: - 全体

    static func draw(_ context: inout GraphicsContext, size: CGSize, state: CivState, zoom: CGFloat, pan: CGSize,
                     selected: (Int, Int)?, time: Double) {
        context.fill(Path(CGRect(origin: .zero, size: size)),
                     with: .linearGradient(Gradient(colors: [Color(red: 0.55, green: 0.78, blue: 0.95),
                                                             Color(red: 0.86, green: 0.94, blue: 1)]),
                                           startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
        let layout = Self.layout(size: size, zoom: zoom, pan: pan)
        let n = CivState.size
        var labels: [(CGPoint, String, Int, Bool)] = []
        for sum in 0...(2 * (n - 1)) {
            for x in 0..<n {
                let y = sum - x
                guard (0..<n).contains(y) else { continue }
                let tile = state.tiles[state.index(x, y)]
                drawTile(&context, layout: layout, state: state, x: x, y: y, tile: tile, time: time)
                if let cityIndex = state.city(at: x, y) {
                    let city = state.cities[cityIndex]
                    drawCity(&context, layout: layout, state: state, cityIndex: cityIndex, top: topHeight(tile))
                    labels.append((layout.p(Double(x) + 0.5, Double(y) + 0.5, topHeight(tile) + 3.2),
                                   "\(city.name) 👤\(city.pop)", city.founder, cityIndex == 0))
                }
                if let selected, selected == (x, y) {
                    let top = topHeight(tile)
                    let face = polygon([layout.p(Double(x), Double(y), top), layout.p(Double(x + 1), Double(y), top),
                                        layout.p(Double(x + 1), Double(y + 1), top), layout.p(Double(x), Double(y + 1), top)])
                    context.fill(face, with: .color(.white.opacity(0.25 + 0.15 * sin(time * 5))))
                    context.stroke(face, with: .color(.white), lineWidth: 2.5)
                }
            }
        }
        // 都市の名前の札（いちばん上に）
        for (point, text, founder, capital) in labels {
            let resolved = context.resolve(Text((capital ? "★ " : "") + text)
                .font(.system(size: max(10, layout.w * 0.32), weight: .bold, design: .rounded))
                .foregroundColor(.white))
            let measured = resolved.measure(in: CGSize(width: 400, height: 100))
            let box = CGRect(x: point.x - measured.width / 2 - 6, y: point.y - measured.height / 2 - 2,
                             width: measured.width + 12, height: measured.height + 4)
            context.fill(Path(roundedRect: box, cornerRadius: box.height / 2), with: .color(color(of: founder).opacity(0.92)))
            context.draw(resolved, at: point)
        }
    }

    // MARK: - マス

    private static let soilLeft = Color(red: 0.45, green: 0.32, blue: 0.22)
    private static let soilRight = Color(red: 0.56, green: 0.41, blue: 0.29)

    private static func drawTile(_ context: inout GraphicsContext, layout: HLayout, state: CivState, x: Int, y: Int,
                                 tile: CivTile, time: Double) {
        let gx = Double(x), gy = Double(y)
        let top = topHeight(tile)
        let bottom = -0.8
        let a = layout.p(gx, gy, top), b = layout.p(gx + 1, gy, top)
        let c = layout.p(gx + 1, gy + 1, top), d = layout.p(gx, gy + 1, top)
        let w = layout.w

        guard tile.revealed else {
            // 霧
            context.fill(polygon([d, c, layout.p(gx + 1, gy + 1, bottom), layout.p(gx, gy + 1, bottom)]),
                         with: .color(Color(red: 0.25, green: 0.27, blue: 0.32)))
            context.fill(polygon([b, c, layout.p(gx + 1, gy + 1, bottom), layout.p(gx + 1, gy, bottom)]),
                         with: .color(Color(red: 0.32, green: 0.34, blue: 0.4)))
            let face = polygon([a, b, c, d])
            context.fill(face, with: .color(Color(red: 0.42, green: 0.45, blue: 0.52)))
            let center = layout.p(gx + 0.5, gy + 0.5, top)
            let drift = CGFloat(sin(time * 0.5 + gx * 1.3 + gy)) * w * 0.05
            for k in 0..<2 {
                let r = w * (0.22 + 0.06 * CGFloat(k))
                let point = CGPoint(x: center.x + drift + CGFloat(k) * w * 0.12 - w * 0.06, y: center.y - w * 0.08 * CGFloat(k))
                context.fill(Path(ellipseIn: CGRect(x: point.x - r, y: point.y - r * 0.45, width: r * 2, height: r * 0.9)),
                             with: .color(.white.opacity(0.13)))
            }
            return
        }

        let topFill = topColor(tile.terrain, odd: (x + y) % 2 == 0)
        let leftFace = polygon([d, c, layout.p(gx + 1, gy + 1, bottom), layout.p(gx, gy + 1, bottom)])
        let rightFace = polygon([b, c, layout.p(gx + 1, gy + 1, bottom), layout.p(gx + 1, gy, bottom)])
        context.fill(leftFace, with: .color(tile.terrain == .water ? Color(red: 0.2, green: 0.42, blue: 0.7) : soilLeft))
        context.fill(rightFace, with: .color(tile.terrain == .water ? Color(red: 0.25, green: 0.5, blue: 0.78) : soilRight))
        if tile.terrain != .water {
            let band = top - 0.2
            context.fill(polygon([d, c, layout.p(gx + 1, gy + 1, band), layout.p(gx, gy + 1, band)]),
                         with: .color(topFill.opacity(0.75)))
            context.fill(polygon([b, c, layout.p(gx + 1, gy + 1, band), layout.p(gx + 1, gy, band)]),
                         with: .color(topFill.opacity(0.9)))
        }
        let face = polygon([a, b, c, d])
        context.fill(face, with: .color(topFill))
        context.stroke(face, with: .color(.black.opacity(0.06)), lineWidth: 0.5)

        // 領土：持ち主の色をうすく塗り、境目に線
        if let owner = state.owner(of: x, y) {
            let tint = color(of: state.cities[owner].founder)
            context.fill(face, with: .color(tint.opacity(0.16)))
            let edges: [(CGPoint, CGPoint, Int, Int)] = [(a, b, x, y - 1), (b, c, x + 1, y), (c, d, x, y + 1), (d, a, x - 1, y)]
            for (from, to, nx, ny) in edges where state.owner(of: nx, ny) != owner {
                var edge = Path()
                edge.move(to: from)
                edge.addLine(to: to)
                context.stroke(edge, with: .color(tint.opacity(0.9)), style: StrokeStyle(lineWidth: max(w * 0.06, 1.5), lineCap: .round))
            }
        }

        let center = layout.p(gx + 0.5, gy + 0.5, top)
        var glows: [(CGPoint, CGFloat)] = []
        func small(_ item: HItem, _ ox: Double, _ oy: Double, scale: CGFloat = 0.55) {
            let point = layout.p(gx + ox, gy + oy, top)
            let mini = HLayout(previewWidth: w * scale, at: point)
            HakoniwaRenderer.drawItem(&context, layout: mini, item: item, gx: 0, gy: 0, top: 0, tint: 0, seed: x * 7 + y,
                                      time: time, night: 0, glows: &glows)
        }

        switch tile.terrain {
        case .forest:
            if state.city(at: x, y) == nil {
                small((x + y) % 2 == 0 ? .pine : .tree, 0.3, 0.35)
                small(.pine, 0.7, 0.6)
            }
        case .hills:
            for (ox, oy) in [(0.35, 0.4), (0.65, 0.62)] {
                let point = layout.p(gx + ox, gy + oy, top)
                let r = w * 0.17
                context.fill(Path(ellipseIn: CGRect(x: point.x - r, y: point.y - r * 0.7, width: r * 2, height: r)),
                             with: .color(Color(red: 0.5, green: 0.6, blue: 0.35)))
            }
        case .mountain:
            let corners = [layout.p(gx + 0.12, gy + 0.12, top), layout.p(gx + 0.88, gy + 0.12, top),
                           layout.p(gx + 0.88, gy + 0.88, top), layout.p(gx + 0.12, gy + 0.88, top)]
            let apex = layout.p(gx + 0.5, gy + 0.5, top + 2.4)
            context.fill(polygon([corners[0], corners[1], apex]), with: .color(Color(red: 0.6, green: 0.58, blue: 0.56)))
            context.fill(polygon([corners[3], corners[0], apex]), with: .color(Color(red: 0.5, green: 0.48, blue: 0.47)))
            context.fill(polygon([corners[3], corners[2], apex]), with: .color(Color(red: 0.45, green: 0.43, blue: 0.42)))
            context.fill(polygon([corners[1], corners[2], apex]), with: .color(Color(red: 0.62, green: 0.6, blue: 0.58)))
            func toward(_ p: CGPoint) -> CGPoint { CGPoint(x: apex.x + (p.x - apex.x) * 0.3, y: apex.y + (p.y - apex.y) * 0.3) }
            context.fill(polygon([toward(corners[3]), toward(corners[2]), apex]), with: .color(.white.opacity(0.95)))
            context.fill(polygon([toward(corners[1]), toward(corners[2]), apex]), with: .color(.white))
        case .water:
            for k in 0..<2 {
                let f = (time * 0.25 + Double(k) * 0.5 + Double((x * 7 + y * 3) % 10) * 0.07).truncatingRemainder(dividingBy: 1)
                var wave = Path()
                wave.move(to: layout.p(gx + 0.2, gy + 0.1 + f * 0.8, top))
                wave.addLine(to: layout.p(gx + 0.5, gy + 0.1 + f * 0.8, top))
                context.stroke(wave, with: .color(.white.opacity(0.5 * sin(f * .pi))),
                               style: StrokeStyle(lineWidth: max(w * 0.03, 0.8), lineCap: .round))
            }
        case .desert:
            var dune = Path()
            dune.move(to: layout.p(gx + 0.2, gy + 0.6, top))
            dune.addQuadCurve(to: layout.p(gx + 0.8, gy + 0.55, top), control: layout.p(gx + 0.5, gy + 0.35, top))
            context.stroke(dune, with: .color(Color(red: 0.8, green: 0.68, blue: 0.42)), lineWidth: max(w * 0.025, 0.8))
        default:
            break
        }

        switch tile.improvement {
        case .farm?:
            for k in 1..<4 {
                let row = gy + Double(k) * 0.25
                var line = Path()
                line.move(to: layout.p(gx + 0.1, row, top))
                line.addLine(to: layout.p(gx + 0.9, row, top))
                context.stroke(line, with: .color(Color(red: 0.85, green: 0.75, blue: 0.3)), lineWidth: max(w * 0.06, 1.5))
            }
        case .mine?:
            let r = w * 0.1
            context.fill(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r * 1.4, width: r * 2, height: r * 1.6)),
                         with: .color(.black.opacity(0.7)))
            var frame = Path()
            frame.move(to: CGPoint(x: center.x - r * 1.2, y: center.y))
            frame.addLine(to: CGPoint(x: center.x - r * 1.2, y: center.y - r * 1.5))
            frame.addLine(to: CGPoint(x: center.x + r * 1.2, y: center.y - r * 1.5))
            frame.addLine(to: CGPoint(x: center.x + r * 1.2, y: center.y))
            context.stroke(frame, with: .color(Color(red: 0.55, green: 0.38, blue: 0.24)), lineWidth: max(w * 0.04, 1))
        case .harbor?:
            small(.boat, 0.5, 0.5, scale: 0.8)
        case nil:
            break
        }

        if tile.ruin {
            for ox in [0.35, 0.5, 0.65] {
                let base = layout.p(gx + ox, gy + 0.5, top)
                let height = w * (ox == 0.5 ? 0.18 : 0.24)
                context.fill(Path(CGRect(x: base.x - w * 0.03, y: base.y - height, width: w * 0.06, height: height)),
                             with: .color(Color(red: 0.8, green: 0.78, blue: 0.72)))
            }
            let label = context.resolve(Text("?").font(.system(size: max(9, w * 0.3), weight: .heavy)).foregroundColor(.white))
            context.draw(label, at: CGPoint(x: center.x, y: center.y - w * 0.4))
        }
    }

    // MARK: - 都市

    private static func drawCity(_ context: inout GraphicsContext, layout: HLayout, state: CivState, cityIndex: Int,
                                 top: Double) {
        let city = state.cities[cityIndex]
        let gx = Double(city.x), gy = Double(city.y)
        let w = layout.w
        var glows: [(CGPoint, CGFloat)] = []
        // 世界の不思議（首都の奥に）
        if cityIndex == 0 && state.wonders.contains(.pyramids) {
            let corners = [layout.p(gx + 0.05, gy + 0.05, top), layout.p(gx + 0.4, gy + 0.05, top),
                           layout.p(gx + 0.4, gy + 0.4, top), layout.p(gx + 0.05, gy + 0.4, top)]
            let apex = layout.p(gx + 0.22, gy + 0.22, top + 1.6)
            context.fill(polygon([corners[3], corners[2], apex]), with: .color(Color(red: 0.85, green: 0.72, blue: 0.4)))
            context.fill(polygon([corners[1], corners[2], apex]), with: .color(Color(red: 0.95, green: 0.83, blue: 0.5)))
        }
        // 家：人口が増えると増える。新しい時代は真ん中にビル
        let spots: [(Double, Double)] = [(0.3, 0.3), (0.72, 0.32), (0.32, 0.72), (0.5, 0.5), (0.72, 0.72)]
        let houses = min(1 + city.pop / 2, spots.count)
        let modern = state.techs.count >= 9
        for (k, spot) in spots.prefix(houses).sorted(by: { $0.0 + $0.1 < $1.0 + $1.1 }).enumerated() {
            let point = layout.p(gx + spot.0, gy + spot.1, top)
            if modern && spot == (0.5, 0.5) {
                drawTower(&context, layout: layout, gx: gx + 0.5, gy: gy + 0.5, top: top, founder: city.founder)
                continue
            }
            let mini = HLayout(previewWidth: w * 0.5, at: point)
            HakoniwaRenderer.drawItem(&context, layout: mini, item: .house, gx: 0, gy: 0, top: 0,
                                      tint: city.founder == 0 ? 0 : 1, seed: k, time: 0, night: 0, glows: &glows)
        }
        // 旗
        let flagBase = layout.p(gx + 0.85, gy + 0.15, top)
        let flagTop = CGPoint(x: flagBase.x, y: flagBase.y - w * 0.75)
        var pole = Path()
        pole.move(to: flagBase)
        pole.addLine(to: flagTop)
        context.stroke(pole, with: .color(Color(white: 0.3)), lineWidth: max(w * 0.025, 0.8))
        context.fill(polygon([flagTop, CGPoint(x: flagTop.x + w * 0.22, y: flagTop.y + w * 0.06),
                              CGPoint(x: flagTop.x, y: flagTop.y + w * 0.14)]), with: .color(color(of: city.founder)))
        if cityIndex == 0 && state.wonders.contains(.spaceship) {
            let base = layout.p(gx + 0.2, gy + 0.8, top)
            context.fill(Path(roundedRect: CGRect(x: base.x - w * 0.05, y: base.y - w * 0.6, width: w * 0.1, height: w * 0.6),
                              cornerRadius: w * 0.05), with: .color(.white))
            context.fill(polygon([CGPoint(x: base.x - w * 0.05, y: base.y - w * 0.55), CGPoint(x: base.x + w * 0.05, y: base.y - w * 0.55),
                                  CGPoint(x: base.x, y: base.y - w * 0.72)]), with: .color(.red))
        }
    }

    private static func drawTower(_ context: inout GraphicsContext, layout: HLayout, gx: Double, gy: Double, top: Double,
                                  founder: Int) {
        let x0 = gx - 0.16, x1 = gx + 0.16, y0 = gy - 0.16, y1 = gy + 0.16
        let roof = top + 3.2
        context.fill(polygon([layout.p(x0, y1, top), layout.p(x1, y1, top), layout.p(x1, y1, roof), layout.p(x0, y1, roof)]),
                     with: .color(Color(red: 0.55, green: 0.65, blue: 0.75)))
        context.fill(polygon([layout.p(x1, y0, top), layout.p(x1, y1, top), layout.p(x1, y1, roof), layout.p(x1, y0, roof)]),
                     with: .color(Color(red: 0.7, green: 0.8, blue: 0.9)))
        context.fill(polygon([layout.p(x0, y0, roof), layout.p(x1, y0, roof), layout.p(x1, y1, roof), layout.p(x0, y1, roof)]),
                     with: .color(color(of: founder)))
        for level in stride(from: top + 0.4, to: roof - 0.2, by: 0.5) {
            var line = Path()
            line.move(to: layout.p(x0, y1, level))
            line.addLine(to: layout.p(x1, y1, level))
            line.addLine(to: layout.p(x1, y0, level))
            context.stroke(line, with: .color(.white.opacity(0.6)), lineWidth: max(layout.w * 0.02, 0.6))
        }
    }

    // MARK: - タップしたマス

    static func cell(at point: CGPoint, size: CGSize, state: CivState, zoom: CGFloat, pan: CGSize) -> (Int, Int)? {
        let layout = Self.layout(size: size, zoom: zoom, pan: pan)
        let n = CivState.size
        for sum in stride(from: 2 * (n - 1), through: 0, by: -1) {
            for x in 0..<n {
                let y = sum - x
                guard (0..<n).contains(y) else { continue }
                let top = topHeight(state.tiles[state.index(x, y)])
                let gx = Double(x), gy = Double(y)
                let column = polygon([layout.p(gx, gy, top), layout.p(gx + 1, gy, top), layout.p(gx + 1, gy, 0),
                                      layout.p(gx + 1, gy + 1, 0), layout.p(gx, gy + 1, 0), layout.p(gx, gy + 1, top)])
                let face = polygon([layout.p(gx, gy, top), layout.p(gx + 1, gy, top),
                                    layout.p(gx + 1, gy + 1, top), layout.p(gx, gy + 1, top)])
                if face.contains(point) || column.contains(point) { return (x, y) }
            }
        }
        return nil
    }
}
