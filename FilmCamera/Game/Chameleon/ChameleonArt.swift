import SwiftUI
import UIKit

// かくれカメレオンの絵：隠れるキャラの形（3 種類）と、用意した背景（模様）

/// 隠れるキャラの形。すべて 200 × 140 の箱（中心が 0,0）の中の座標で、いくつかの部品の重ね合わせ
enum HiderShape: String, CaseIterable, Identifiable {
    case chameleon, ball, flat

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chameleon: return "カメレオン"
        case .ball: return "まるまる"
        case .flat: return "ぺったんこ"
        }
    }

    static let box = CGRect(x: -100, y: -70, width: 200, height: 140)

    /// 体の部品（重なった部分も含めて、全部を合わせた形が体）
    var parts: [Path] {
        switch self {
        case .chameleon: return Self.chameleonParts
        case .ball: return [Path(ellipseIn: CGRect(x: -62, y: -62, width: 124, height: 124))]
        case .flat: return [Path(roundedRect: CGRect(x: -96, y: -30, width: 192, height: 60), cornerRadius: 30)]
        }
    }

    /// 塗る人にだけ見せる目の位置（鬼には見えない）
    var eye: CGPoint? {
        switch self {
        case .chameleon: return CGPoint(x: 60, y: -27)
        case .ball: return CGPoint(x: 22, y: -18)
        case .flat: return CGPoint(x: 70, y: -6)
        }
    }

    func contains(_ point: CGPoint) -> Bool {
        parts.contains { $0.contains(point) }
    }

    private static let chameleonParts: [Path] = {
        var parts: [Path] = [
            Path(ellipseIn: CGRect(x: -64, y: -40, width: 116, height: 74)),     // 胴
            Path(ellipseIn: CGRect(x: 26, y: -48, width: 62, height: 52)),       // 頭
            Path(ellipseIn: CGRect(x: 66, y: -32, width: 30, height: 22)),       // 口先
            Path(ellipseIn: CGRect(x: 26, y: -62, width: 38, height: 26)),       // とさか
            Path(roundedRect: CGRect(x: 12, y: 18, width: 15, height: 36), cornerRadius: 7),    // 前足
            Path(roundedRect: CGRect(x: -42, y: 18, width: 15, height: 36), cornerRadius: 7),   // 後ろ足
            Path(ellipseIn: CGRect(x: 8, y: 46, width: 24, height: 12)),
            Path(ellipseIn: CGRect(x: -46, y: 46, width: 24, height: 12)),
        ]
        // くるっと巻いたしっぽ（小さくなる円をうずまき状に並べる）
        let center = CGPoint(x: -80, y: 20)
        for i in 0..<18 {
            let t = Double(i) / 17
            let angle = -0.42 * .pi - t * 1.8 * .pi
            let radius = 26 * (1 - 0.68 * t)
            let r = 11 - 6.5 * t
            let x = center.x + cos(angle) * radius
            let y = center.y + sin(angle) * radius
            parts.append(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)))
        }
        return parts
    }()
}

/// 背景（ステージ）。用意した模様は 900 × 1200 の画像として作る
enum StagePreset: String, CaseIterable, Identifiable {
    case bricks, leaves, dots, books, flowers, stripes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bricks: return "レンガの壁"
        case .leaves: return "森の葉っぱ"
        case .dots: return "水玉"
        case .books: return "本だな"
        case .flowers: return "お花畑"
        case .stripes: return "ストライプ"
        }
    }

    static let size = CGSize(width: 900, height: 1200)

    func render() -> UIImage {
        var random = SeededRandom(seed: UInt64(rawValue.unicodeScalars.reduce(0) { $0 &* 31 &+ Int($1.value) }))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: Self.size, format: format).image { renderer in
            let c = renderer.cgContext
            let w = Self.size.width, h = Self.size.height
            switch self {
            case .bricks:
                c.setFillColor(UIColor(red: 0.78, green: 0.74, blue: 0.68, alpha: 1).cgColor)
                c.fill(CGRect(origin: .zero, size: Self.size))
                let bw = 120.0, bh = 50.0
                var row = 0
                for y in stride(from: 0.0, to: h, by: bh) {
                    let offset = row % 2 == 0 ? 0 : -bw / 2
                    for x in stride(from: offset, to: w, by: bw) {
                        let r = 0.55 + random.next() * 0.2, g = 0.25 + random.next() * 0.12, b = 0.18 + random.next() * 0.08
                        c.setFillColor(UIColor(red: r, green: g, blue: b, alpha: 1).cgColor)
                        c.fill(CGRect(x: x + 4, y: y + 4, width: bw - 8, height: bh - 8))
                        // ざらざら
                        for _ in 0..<14 {
                            let shade = random.next() * 0.25
                            c.setFillColor(UIColor(white: shade, alpha: 0.18).cgColor)
                            c.fill(CGRect(x: x + 4 + random.next() * (bw - 14), y: y + 4 + random.next() * (bh - 14),
                                          width: 3 + random.next() * 6, height: 3 + random.next() * 4))
                        }
                    }
                    row += 1
                }
            case .leaves:
                c.setFillColor(UIColor(red: 0.12, green: 0.3, blue: 0.14, alpha: 1).cgColor)
                c.fill(CGRect(origin: .zero, size: Self.size))
                for _ in 0..<900 {
                    let x = random.next() * w, y = random.next() * h
                    let size = 30 + random.next() * 50
                    let hue = 0.2 + random.next() * 0.15
                    let color = UIColor(hue: hue, saturation: 0.55 + random.next() * 0.35,
                                        brightness: 0.35 + random.next() * 0.5, alpha: 1)
                    c.saveGState()
                    c.translateBy(x: x, y: y)
                    c.rotate(by: random.next() * .pi * 2)
                    c.setFillColor(color.cgColor)
                    c.fillEllipse(in: CGRect(x: -size / 2, y: -size / 5, width: size, height: size / 2.5))
                    c.setStrokeColor(UIColor(white: 0, alpha: 0.2).cgColor)
                    c.setLineWidth(1.5)
                    c.move(to: CGPoint(x: -size / 2, y: 0))
                    c.addLine(to: CGPoint(x: size / 2, y: 0))
                    c.strokePath()
                    c.restoreGState()
                }
            case .dots:
                c.setFillColor(UIColor(red: 1, green: 0.95, blue: 0.85, alpha: 1).cgColor)
                c.fill(CGRect(origin: .zero, size: Self.size))
                let colors: [UIColor] = [.systemPink, .systemTeal, .systemYellow, .systemPurple, .systemOrange, .systemGreen]
                for _ in 0..<260 {
                    let r = 14 + random.next() * 40
                    let x = random.next() * w, y = random.next() * h
                    c.setFillColor(colors[Int(random.next() * Double(colors.count)) % colors.count]
                        .withAlphaComponent(0.85).cgColor)
                    c.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
                }
            case .books:
                c.setFillColor(UIColor(red: 0.35, green: 0.22, blue: 0.14, alpha: 1).cgColor)
                c.fill(CGRect(origin: .zero, size: Self.size))
                let shelf = 200.0
                for top in stride(from: 0.0, to: h, by: shelf) {
                    var x = 10.0
                    while x < w - 10 {
                        let bw = 22 + random.next() * 34
                        let bh = shelf - 40 - random.next() * 50
                        let color = UIColor(hue: random.next(), saturation: 0.4 + random.next() * 0.4,
                                            brightness: 0.35 + random.next() * 0.5, alpha: 1)
                        c.setFillColor(color.cgColor)
                        c.fill(CGRect(x: x, y: top + shelf - 22 - bh, width: bw, height: bh))
                        c.setFillColor(UIColor(white: 1, alpha: 0.25).cgColor)
                        c.fill(CGRect(x: x + 4, y: top + shelf - 22 - bh + 18, width: bw - 8, height: 5))
                        x += bw + 2
                    }
                    c.setFillColor(UIColor(red: 0.5, green: 0.33, blue: 0.2, alpha: 1).cgColor)
                    c.fill(CGRect(x: 0, y: top + shelf - 22, width: w, height: 22))
                }
            case .flowers:
                c.setFillColor(UIColor(red: 0.45, green: 0.7, blue: 0.3, alpha: 1).cgColor)
                c.fill(CGRect(origin: .zero, size: Self.size))
                for _ in 0..<700 {
                    let x = random.next() * w, y = random.next() * h
                    c.setFillColor(UIColor(hue: 0.25 + random.next() * 0.1, saturation: 0.6, brightness: 0.4 + random.next() * 0.3,
                                           alpha: 1).cgColor)
                    c.fill(CGRect(x: x, y: y, width: 3, height: 12 + random.next() * 14))
                }
                let petals: [UIColor] = [.systemPink, .white, .systemYellow, .systemRed, .systemPurple]
                for _ in 0..<240 {
                    let x = random.next() * w, y = random.next() * h
                    let r = 9 + random.next() * 12
                    let color = petals[Int(random.next() * Double(petals.count)) % petals.count]
                    c.setFillColor(color.cgColor)
                    for k in 0..<5 {
                        let a = Double(k) / 5 * 2 * .pi
                        c.fillEllipse(in: CGRect(x: x + cos(a) * r - r * 0.6, y: y + sin(a) * r - r * 0.6,
                                                 width: r * 1.2, height: r * 1.2))
                    }
                    c.setFillColor(UIColor.systemYellow.cgColor)
                    c.fillEllipse(in: CGRect(x: x - r * 0.45, y: y - r * 0.45, width: r * 0.9, height: r * 0.9))
                }
            case .stripes:
                let colors: [UIColor] = [UIColor(red: 0.95, green: 0.4, blue: 0.35, alpha: 1),
                                         UIColor(red: 1, green: 0.85, blue: 0.4, alpha: 1),
                                         UIColor(red: 0.3, green: 0.65, blue: 0.85, alpha: 1),
                                         UIColor(red: 0.98, green: 0.96, blue: 0.9, alpha: 1)]
                var x = -h
                var i = 0
                while x < w {
                    let bw = 40 + random.next() * 70
                    c.setFillColor(colors[i % colors.count].cgColor)
                    c.move(to: CGPoint(x: x, y: h))
                    c.addLine(to: CGPoint(x: x + h * 0.6, y: 0))
                    c.addLine(to: CGPoint(x: x + h * 0.6 + bw, y: 0))
                    c.addLine(to: CGPoint(x: x + bw, y: h))
                    c.closePath()
                    c.fillPath()
                    x += bw
                    i += 1
                }
            }
        }
    }

    /// 選ぶ画面の小さい見本
    func thumbnail() -> UIImage {
        let full = render()
        let size = CGSize(width: 150, height: 200)
        return UIGraphicsImageRenderer(size: size).image { _ in full.draw(in: CGRect(origin: .zero, size: size)) }
    }
}

/// 決まった順番の「でたらめな」数（背景の模様を毎回同じにする）
struct SeededRandom {
    var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }
    mutating func next() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double((state >> 33) % 1_000_000) / 1_000_000
    }
}
