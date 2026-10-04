import SwiftUI
import UIKit

/// 塗り絵の問題：マス目の大きさ、使う色（パレット）、各マスの正解の色番号
struct JewelPuzzle {
    let columns: Int
    let rows: Int
    let palette: [Color]
    let uiColors: [UIColor]
    private let rgb: [SIMD3<Float>]
    let targets: [Int]

    /// 写真から問題を作る。縦長 3:4 に切り抜き、横 48 マスにして、色を 24 色ほどにまとめる
    /// （本物の Jewel Coloring のように細かく、たくさんの色で）
    init?(image: UIImage, columns: Int = 48, colors: Int = 24) {
        guard let cgImage = image.cgImage ?? Self.render(image) else { return nil }
        let rows = columns * 4 / 3
        guard let raw = Self.pixels(of: cgImage, orientation: image.imageOrientation,
                                    columns: columns, rows: rows) else { return nil }
        // 暗い写真や色の薄い写真でも見分けやすいよう、明るさを広げて色を濃くする
        let pixels = Self.vivid(raw)
        // 似すぎた色はまとめる（灰色ばかりで見分けられない、をなくす）
        let centers = Self.mergeClose(Self.kMeans(pixels, k: colors))
        // 明るい色から順に番号をふる
        let order = centers.indices.sorted { Self.luma(centers[$0]) > Self.luma(centers[$1]) }
        let sorted = order.map { centers[$0] }
        self.columns = columns
        self.rows = rows
        self.rgb = sorted
        self.palette = sorted.map { Color(red: Double($0.x), green: Double($0.y), blue: Double($0.z)) }
        self.uiColors = sorted.map { UIColor(red: CGFloat($0.x), green: CGFloat($0.y), blue: CGFloat($0.z), alpha: 1) }
        self.targets = pixels.map { Self.nearest($0, in: sorted) }
    }

    /// 色と正解の番号を直接与えて作る（ドット絵の問題用）
    init(columns: Int, rows: Int, colors: [SIMD3<Float>], targets: [Int]) {
        self.columns = columns
        self.rows = rows
        self.rgb = colors
        self.palette = colors.map { Color(red: Double($0.x), green: Double($0.y), blue: Double($0.z)) }
        self.uiColors = colors.map { UIColor(red: CGFloat($0.x), green: CGFloat($0.y), blue: CGFloat($0.z), alpha: 1) }
        self.targets = targets
    }

    /// 文字で描いたドット絵から作る（1 文字 = 1 マス）
    static func pixelArt(_ art: [String], colors: [Character: SIMD3<Float>]) -> JewelPuzzle {
        let keys = Array(Set(art.joined())).sorted()
        let index = Dictionary(uniqueKeysWithValues: keys.enumerated().map { ($1, $0) })
        let targets = art.joined().map { index[$0] ?? 0 }
        return JewelPuzzle(columns: art[0].count, rows: art.count,
                           colors: keys.map { colors[$0] ?? SIMD3(0.5, 0.5, 0.5) }, targets: targets)
    }

    /// 最初のレベルで遊ぶドット絵
    static let presets: [JewelPuzzle] = [
        pixelArt(["..RR....RR..", ".RRRR..RRRR.", "RRWRRRRRRRRR", "RWRRRRRRRRRR", "RRRRRRRRRRRR", "RRRRRRRRRRRR",
                  ".RRRRRRRRRR.", "..RRRRRRRR..", "...RRRRRR...", "....RRRR....", ".....RR....."],
                 colors: [".": SIMD3(0.55, 0.88, 0.95), "R": SIMD3(0.98, 0.42, 0.55), "W": SIMD3(1, 0.93, 0.95)]),
        pixelArt(["....RRRRRR....", "..RRWWRRRRRR..", ".RRWWWRRRWWRR.", ".RRWWRRRRWWWR.", "RRRRRRRRRRWWRR",
                  "RWWRRRRRRRRRRR", "WWWWRRWWWRRRRR", "RWWRRWWWWWRRRR", ".RRRRRWWWRRRR.", "...SSSSSSSS...",
                  "...SSKSSKSS...", "...SSKSSKSS...", "...SSSSSSSS...", "....SSSSSS...."],
                 colors: [".": SIMD3(0.75, 0.93, 0.7), "R": SIMD3(0.92, 0.3, 0.32), "W": SIMD3(1, 0.97, 0.92),
                          "S": SIMD3(0.98, 0.85, 0.68), "K": SIMD3(0.3, 0.22, 0.3)]),
        pixelArt(["......YY......", ".....YYYY.....", ".....YYYY.....", "YYYYYYYYYYYYYY", ".YYYYYYYYYYYY.",
                  "..YYYKYYKYYY..", "...YYYYYYYY...", "...YYPYYPYY...", "..YYYYYYYYYY..", "..YYYY..YYYY..",
                  ".YYY......YYY.", ".YY........YY."],
                 colors: [".": SIMD3(0.62, 0.6, 0.95), "Y": SIMD3(1, 0.85, 0.3), "K": SIMD3(0.35, 0.25, 0.3),
                          "P": SIMD3(1, 0.6, 0.65)]),
        // ねこ
        pixelArt(["..K........K..", ".KOK......KOK.", ".KOOK....KOOK.", ".KOOOKKKKOOOK.", ".KOOOOOOOOOOK.",
                  "KOOWKOOOOWKOOK", "KOOKKOOOOKKOOK", "KOOOOOPPOOOOOK", "KPPOOOKKOOOPPK", ".KOOOOOOOOOOK.",
                  "..KKOOOOOOKK..", "....KKKKKK...."],
                 colors: [".": SIMD3(0.7, 0.92, 0.85), "K": SIMD3(0.36, 0.24, 0.2), "O": SIMD3(1, 0.68, 0.3),
                          "W": SIMD3(1, 1, 1), "P": SIMD3(1, 0.62, 0.72)]),
        // ひまわり
        pixelArt([".....YYY.....", "...YYYYYYY...", "..YYYBBBYYY..", ".YYYBBBBBYYY.", ".YYBBBBBBBYY.",
                  ".YYYBBBBBYYY.", "..YYYBBBYYY..", "...YYYYYYY...", ".....YGY.....", "......G......",
                  "..LL..G..LL..", "...LLLGLLL...", "......G......"],
                 colors: [".": SIMD3(0.55, 0.8, 1), "Y": SIMD3(1, 0.85, 0.2), "B": SIMD3(0.55, 0.33, 0.2),
                          "G": SIMD3(0.25, 0.6, 0.3), "L": SIMD3(0.55, 0.85, 0.4)]),
        // アイスクリーム
        pixelArt(["....PPPP....", "...PPWPPP...", "..PPPPPPPP..", "..MMMMMMMM..", ".MMWMMMMMMM.",
                  ".MMMMMMMMMM.", "..CCCCCCCC..", "..CTCCTCCT..", "...CCCCCC...", "...CTCCTC...",
                  "....CCCC....", "....CTCC....", ".....CC.....", ".....CC....."],
                 colors: [".": SIMD3(0.8, 0.75, 1), "P": SIMD3(1, 0.55, 0.7), "W": SIMD3(1, 1, 1),
                          "M": SIMD3(0.55, 0.92, 0.75), "C": SIMD3(0.95, 0.75, 0.45), "T": SIMD3(0.75, 0.5, 0.25)]),
        // さかな
        pixelArt(["..B...........", ".B...OOOOO....", "....OOSOOSO..O", "..OOOSOOOSOOOO", ".OKOOSOOOSOOO.",
                  "..OOOSOOOSOOOO", "....OOSOOSO..O", ".....OOOOO....", ".............."],
                 colors: [".": SIMD3(0.3, 0.6, 0.95), "B": SIMD3(0.85, 0.95, 1), "O": SIMD3(1, 0.55, 0.2),
                          "S": SIMD3(1, 1, 1), "K": SIMD3(0.15, 0.15, 0.25)]),
        // にじと雲
        pixelArt(["..............", "...RRRRRRRR...", "..RROOOOOORR..", ".RROOYYYYOORR.", ".ROOYGGGGYOOR.",
                  "RROYGBBBBGYORR", "ROYGB....BGYOR", "WWWWW....WWWWW", ".WWW......WWW."],
                 colors: [".": SIMD3(0.7, 0.88, 1), "R": SIMD3(1, 0.4, 0.45), "O": SIMD3(1, 0.65, 0.3),
                          "Y": SIMD3(1, 0.9, 0.35), "G": SIMD3(0.45, 0.85, 0.45), "B": SIMD3(0.4, 0.55, 1),
                          "W": SIMD3(1, 1, 1)]),
    ]

    /// 明るさを 2〜98% の範囲いっぱいに広げ、色の濃さを上げる
    private static func vivid(_ pixels: [SIMD3<Float>]) -> [SIMD3<Float>] {
        let lumas = pixels.map(luma).sorted()
        guard !lumas.isEmpty else { return pixels }
        let low = lumas[lumas.count * 2 / 100]
        let high = lumas[lumas.count * 98 / 100]
        let range = max(high - low, 0.05)
        return pixels.map { p in
            var c = (p - SIMD3(repeating: low)) / range * 0.85 + SIMD3(repeating: 0.08)
            let gray = luma(c)
            c = SIMD3(repeating: gray) + (c - SIMD3(repeating: gray)) * 1.5
            return c.clamped(lowerBound: SIMD3(repeating: 0), upperBound: SIMD3(repeating: 1))
        }
    }

    /// いちばん近い 2 色が近すぎるあいだ、平均してまとめる
    private static func mergeClose(_ colors: [SIMD3<Float>]) -> [SIMD3<Float>] {
        var list = colors
        while list.count > 2 {
            var best = (0, 1, Float.greatestFiniteMagnitude)
            for i in list.indices {
                for j in list.indices where j > i {
                    let d = list[i] - list[j]
                    let distance = (d * d).sum()
                    if distance < best.2 { best = (i, j, distance) }
                }
            }
            guard best.2 < 0.05 else { break }
            list[best.0] = (list[best.0] + list[best.1]) / 2
            list.remove(at: best.1)
        }
        return list
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
