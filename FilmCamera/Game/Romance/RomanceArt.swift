import SwiftUI
import UIKit

// 恋愛アドベンチャーの絵（立ち絵と背景）。画像ファイルは持たず、図形で描く

// MARK: - 登場人物

enum Heroine: String, CaseIterable, Codable {
    case hinata, shizuku, rin

    var name: String {
        switch self {
        case .hinata: return "ひなた"
        case .shizuku: return "しずく"
        case .rin: return "リン"
        }
    }

    var fullName: String {
        switch self {
        case .hinata: return "朝倉ひなた"
        case .shizuku: return "白石しずく"
        case .rin: return "早乙女リン"
        }
    }

    /// 名前の札の色
    var color: Color {
        switch self {
        case .hinata: return Color(red: 1, green: 0.55, blue: 0.3)
        case .shizuku: return Color(red: 0.45, green: 0.4, blue: 0.85)
        case .rin: return Color(red: 0.95, green: 0.4, blue: 0.6)
        }
    }

    fileprivate var look: Look {
        switch self {
        case .hinata:
            return Look(hair: rgb(0.86, 0.5, 0.28), hairDark: rgb(0.55, 0.28, 0.15), eye: rgb(0.85, 0.45, 0.15),
                        style: .short, ribbon: rgb(0.92, 0.25, 0.3))
        case .shizuku:
            return Look(hair: rgb(0.2, 0.22, 0.38), hairDark: rgb(0.08, 0.08, 0.18), eye: rgb(0.5, 0.35, 0.75),
                        style: .long, ribbon: rgb(0.92, 0.25, 0.3))
        case .rin:
            return Look(hair: rgb(0.99, 0.85, 0.45), hairDark: rgb(0.78, 0.55, 0.2), eye: rgb(0.2, 0.65, 0.85),
                        style: .twin, ribbon: rgb(0.25, 0.65, 0.45))
        }
    }
}

/// 表情
enum Face: String, Codable {
    case normal, smile, laugh, surprised, sad, angry, blush, shy
}

private func rgb(_ r: Double, _ g: Double, _ b: Double) -> Color { Color(red: r, green: g, blue: b) }

private struct Look {
    enum Style { case short, long, twin }
    let hair: Color
    let hairDark: Color
    let eye: Color
    let style: Style
    let ribbon: Color
}

private let skin = rgb(1, 0.91, 0.84)
private let skinShade = rgb(0.96, 0.78, 0.72)
private let line = rgb(0.32, 0.2, 0.2)

/// 立ち絵（胸から上）。横 300 × 縦 400 の大きさで描いて、表示する大きさに合わせる
struct HeroinePortrait: View {
    let heroine: Heroine
    let face: Face

    var body: some View {
        if let image = RomanceImages.sprite(heroine, face) {
            // 入れた画像があればそれを使う（背景が透明の PNG）
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
        } else {
            Canvas { context, size in
                let scale = min(size.width / 300, size.height / 400)
                context.translateBy(x: (size.width - 300 * scale) / 2, y: size.height - 400 * scale)
                context.scaleBy(x: scale, y: scale)
                draw(in: &context)
            }
            .aspectRatio(3.0 / 4.0, contentMode: .fit)
        }
    }

    private func draw(in context: inout GraphicsContext) {
        let look = heroine.look
        backHair(look, &context)
        uniform(look, &context)
        faceShape(&context)
        eyes(look, &context)
        mouthAndCheeks(&context)
        frontHair(look, &context)
        accessories(look, &context)
    }

    // MARK: 髪（うしろ）

    private func backHair(_ look: Look, _ context: inout GraphicsContext) {
        var path = Path()
        switch look.style {
        case .short:
            path.move(to: CGPoint(x: 150, y: 28))
            path.addCurve(to: CGPoint(x: 62, y: 175), control1: CGPoint(x: 80, y: 28), control2: CGPoint(x: 55, y: 100))
            path.addCurve(to: CGPoint(x: 78, y: 250), control1: CGPoint(x: 66, y: 215), control2: CGPoint(x: 60, y: 240))
            path.addLine(to: CGPoint(x: 222, y: 250))
            path.addCurve(to: CGPoint(x: 238, y: 175), control1: CGPoint(x: 240, y: 240), control2: CGPoint(x: 234, y: 215))
            path.addCurve(to: CGPoint(x: 150, y: 28), control1: CGPoint(x: 245, y: 100), control2: CGPoint(x: 220, y: 28))
        case .long:
            path.move(to: CGPoint(x: 150, y: 26))
            path.addCurve(to: CGPoint(x: 60, y: 160), control1: CGPoint(x: 80, y: 26), control2: CGPoint(x: 58, y: 90))
            path.addCurve(to: CGPoint(x: 48, y: 400), control1: CGPoint(x: 62, y: 260), control2: CGPoint(x: 40, y: 330))
            path.addLine(to: CGPoint(x: 252, y: 400))
            path.addCurve(to: CGPoint(x: 240, y: 160), control1: CGPoint(x: 260, y: 330), control2: CGPoint(x: 238, y: 260))
            path.addCurve(to: CGPoint(x: 150, y: 26), control1: CGPoint(x: 242, y: 90), control2: CGPoint(x: 220, y: 26))
        case .twin:
            path.addEllipse(in: CGRect(x: 66, y: 30, width: 168, height: 190))
            // ツインテール
            for side in [-1.0, 1.0] {
                let x = 150 + side * 88
                var tail = Path()
                tail.move(to: CGPoint(x: x, y: 95))
                tail.addCurve(to: CGPoint(x: x + side * 28, y: 370),
                              control1: CGPoint(x: x + side * 60, y: 160), control2: CGPoint(x: x + side * 55, y: 300))
                tail.addCurve(to: CGPoint(x: x - side * 8, y: 110),
                              control1: CGPoint(x: x + side * 5, y: 300), control2: CGPoint(x: x + side * 10, y: 170))
                tail.closeSubpath()
                context.fill(tail, with: .color(look.hair))
                context.stroke(tail, with: .color(look.hairDark), lineWidth: 2)
            }
        }
        context.fill(path, with: .color(look.hair))
        context.fill(path, with: .color(look.hairDark.opacity(0.25)))
        context.stroke(path, with: .color(look.hairDark), lineWidth: 2)
    }

    // MARK: 体（セーラー服）

    private func uniform(_ look: Look, _ context: inout GraphicsContext) {
        // 首
        let neck = Path(CGRect(x: 133, y: 228, width: 34, height: 80))
        context.fill(neck, with: .color(skin))
        context.fill(Path(CGRect(x: 133, y: 238, width: 34, height: 16)), with: .color(skinShade))
        // ブラウス
        var torso = Path()
        torso.move(to: CGPoint(x: 30, y: 400))
        torso.addCurve(to: CGPoint(x: 120, y: 292), control1: CGPoint(x: 38, y: 330), control2: CGPoint(x: 70, y: 300))
        torso.addLine(to: CGPoint(x: 180, y: 292))
        torso.addCurve(to: CGPoint(x: 270, y: 400), control1: CGPoint(x: 230, y: 300), control2: CGPoint(x: 262, y: 330))
        torso.closeSubpath()
        context.fill(torso, with: .color(.white))
        context.stroke(torso, with: .color(line.opacity(0.6)), lineWidth: 2)
        // えり（紺に白い線）
        let navy = rgb(0.16, 0.2, 0.42)
        for side in [-1.0, 1.0] {
            var collar = Path()
            collar.move(to: CGPoint(x: 150 + side * 32, y: 290))
            collar.addLine(to: CGPoint(x: 150 + side * 110, y: 318))
            collar.addLine(to: CGPoint(x: 150 + side * 95, y: 345))
            collar.addLine(to: CGPoint(x: 150, y: 372))
            collar.addLine(to: CGPoint(x: 150 + side * 8, y: 340))
            collar.closeSubpath()
            context.fill(collar, with: .color(navy))
            var stripe = Path()
            stripe.move(to: CGPoint(x: 150 + side * 40, y: 300))
            stripe.addLine(to: CGPoint(x: 150 + side * 100, y: 325))
            context.stroke(stripe, with: .color(.white.opacity(0.9)), lineWidth: 2)
        }
        // リボン
        var bow = Path()
        bow.move(to: CGPoint(x: 150, y: 352))
        bow.addLine(to: CGPoint(x: 118, y: 338))
        bow.addLine(to: CGPoint(x: 122, y: 370))
        bow.closeSubpath()
        bow.move(to: CGPoint(x: 150, y: 352))
        bow.addLine(to: CGPoint(x: 182, y: 338))
        bow.addLine(to: CGPoint(x: 178, y: 370))
        bow.closeSubpath()
        bow.move(to: CGPoint(x: 150, y: 352))
        bow.addLine(to: CGPoint(x: 138, y: 400))
        bow.addLine(to: CGPoint(x: 162, y: 400))
        bow.closeSubpath()
        context.fill(bow, with: .color(look.ribbon))
        context.fill(Path(ellipseIn: CGRect(x: 141, y: 344, width: 18, height: 16)), with: .color(look.ribbon))
        context.stroke(bow, with: .color(line.opacity(0.5)), lineWidth: 1.5)
    }

    // MARK: 顔

    private func faceShape(_ context: inout GraphicsContext) {
        var path = Path()
        path.move(to: CGPoint(x: 86, y: 120))
        path.addCurve(to: CGPoint(x: 150, y: 252), control1: CGPoint(x: 86, y: 200), control2: CGPoint(x: 115, y: 240))
        path.addCurve(to: CGPoint(x: 214, y: 120), control1: CGPoint(x: 185, y: 240), control2: CGPoint(x: 214, y: 200))
        path.addCurve(to: CGPoint(x: 86, y: 120), control1: CGPoint(x: 214, y: 50), control2: CGPoint(x: 86, y: 50))
        context.fill(path, with: .color(skin))
        context.stroke(path, with: .color(line.opacity(0.7)), lineWidth: 2)
    }

    private func eyes(_ look: Look, _ context: inout GraphicsContext) {
        for (index, x) in [118.0, 182.0].enumerated() {
            let y = 180.0
            let outer = index == 0 ? -1.0 : 1.0
            brow(x: x, y: y, outer: outer, &context)
            switch face {
            case .smile, .laugh:
                // にっこり閉じた目
                var arc = Path()
                arc.move(to: CGPoint(x: x - 16, y: y + 4))
                arc.addQuadCurve(to: CGPoint(x: x + 16, y: y + 4), control: CGPoint(x: x, y: y - 14))
                context.stroke(arc, with: .color(line), style: StrokeStyle(lineWidth: 4, lineCap: .round))
            default:
                openEye(look, x: x, y: y, outer: outer, &context)
            }
        }
    }

    private func brow(x: Double, y: Double, outer: Double, _ context: inout GraphicsContext) {
        // 内側・外側の高さ（表情で傾ける）
        var inner = y - 34, outside = y - 36
        switch face {
        case .sad, .shy: inner = y - 42; outside = y - 32
        case .angry: inner = y - 28; outside = y - 40
        case .surprised: inner = y - 44; outside = y - 44
        default: break
        }
        var path = Path()
        path.move(to: CGPoint(x: x - outer * 14, y: inner))
        path.addQuadCurve(to: CGPoint(x: x + outer * 16, y: outside), control: CGPoint(x: x + outer * 2, y: min(inner, outside) - 4))
        context.stroke(path, with: .color(heroine.look.hairDark), style: StrokeStyle(lineWidth: 3, lineCap: .round))
    }

    private func openEye(_ look: Look, x: Double, y: Double, outer: Double, _ context: inout GraphicsContext) {
        let surprised = face == .surprised
        let sclera = CGRect(x: x - 17, y: y - 18, width: 34, height: surprised ? 40 : 36)
        context.fill(Path(ellipseIn: sclera), with: .color(.white))
        // 瞳（上が暗く下が明るい）。照れているときは横を見る
        let lookX: Double = face == .shy ? -5 : 0
        let irisW = surprised ? 20.0 : 26.0, irisH = surprised ? 24.0 : 32.0
        let iris = CGRect(x: x - irisW / 2 + lookX, y: y - irisH / 2 + 3, width: irisW, height: irisH)
        context.fill(Path(ellipseIn: iris), with: .linearGradient(
            Gradient(colors: [look.eye.opacity(0.6), look.eye, .white.opacity(0.9)]),
            startPoint: CGPoint(x: iris.midX, y: iris.minY), endPoint: CGPoint(x: iris.midX, y: iris.maxY + 6)))
        context.fill(Path(ellipseIn: iris), with: .color(.black.opacity(0.15)))
        context.fill(Path(ellipseIn: iris.insetBy(dx: irisW * 0.28, dy: irisH * 0.3)), with: .color(.black.opacity(0.7)))
        context.stroke(Path(ellipseIn: iris), with: .color(line.opacity(0.6)), lineWidth: 1.2)
        // 光
        context.fill(Path(ellipseIn: CGRect(x: iris.minX + 3, y: iris.minY + 4, width: 9, height: 9)), with: .color(.white))
        context.fill(Path(ellipseIn: CGRect(x: iris.maxX - 8, y: iris.maxY - 11, width: 4, height: 4)), with: .color(.white))
        // 上まぶた（照れ・悲しいときは少し下がる）
        let lidDrop: Double = (face == .blush || face == .sad) ? 7 : 0
        if lidDrop > 0 {
            context.fill(Path(CGRect(x: x - 18, y: y - 20, width: 36, height: lidDrop + 2)), with: .color(skin))
        }
        var lid = Path()
        lid.move(to: CGPoint(x: x - outer * 18, y: y - 6 + lidDrop))
        lid.addQuadCurve(to: CGPoint(x: x + outer * 20, y: y - 10 + lidDrop), control: CGPoint(x: x, y: y - 26 + lidDrop))
        context.stroke(lid, with: .color(line), style: StrokeStyle(lineWidth: 4.5, lineCap: .round))
        // まつげの先
        var lash = Path()
        lash.move(to: CGPoint(x: x + outer * 19, y: y - 10 + lidDrop))
        lash.addLine(to: CGPoint(x: x + outer * 25, y: y - 15 + lidDrop))
        context.stroke(lash, with: .color(line), style: StrokeStyle(lineWidth: 3, lineCap: .round))
        if face == .sad {
            // 涙
            context.fill(Path(ellipseIn: CGRect(x: x + outer * 10 - 3, y: y + 18, width: 6, height: 9)),
                         with: .color(rgb(0.6, 0.85, 1).opacity(0.9)))
        }
    }

    private func mouthAndCheeks(_ context: inout GraphicsContext) {
        // 鼻
        var nose = Path()
        nose.move(to: CGPoint(x: 151, y: 204))
        nose.addLine(to: CGPoint(x: 148, y: 210))
        context.stroke(nose, with: .color(skinShade), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        // ほお
        if [Face.blush, .shy, .laugh, .smile].contains(face) {
            let strength = (face == .blush || face == .shy) ? 0.55 : 0.3
            for x in [106.0, 194.0] {
                context.fill(Path(ellipseIn: CGRect(x: x - 15, y: 206, width: 30, height: 12)),
                             with: .color(rgb(1, 0.5, 0.55).opacity(strength)))
                if face == .blush || face == .shy {
                    for i in 0..<3 {
                        var hatch = Path()
                        let hx = x - 8 + Double(i) * 7
                        hatch.move(to: CGPoint(x: hx + 3, y: 207))
                        hatch.addLine(to: CGPoint(x: hx - 2, y: 216))
                        context.stroke(hatch, with: .color(rgb(0.9, 0.35, 0.4).opacity(0.7)), lineWidth: 1.5)
                    }
                }
            }
        }
        // 口
        var mouth = Path()
        switch face {
        case .normal:
            mouth.move(to: CGPoint(x: 142, y: 226))
            mouth.addQuadCurve(to: CGPoint(x: 158, y: 226), control: CGPoint(x: 150, y: 231))
            context.stroke(mouth, with: .color(line), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
        case .smile:
            mouth.move(to: CGPoint(x: 138, y: 224))
            mouth.addQuadCurve(to: CGPoint(x: 162, y: 224), control: CGPoint(x: 150, y: 236))
            context.stroke(mouth, with: .color(line), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
        case .laugh:
            mouth.move(to: CGPoint(x: 136, y: 222))
            mouth.addQuadCurve(to: CGPoint(x: 164, y: 222), control: CGPoint(x: 150, y: 248))
            mouth.closeSubpath()
            context.fill(mouth, with: .color(rgb(0.75, 0.25, 0.3)))
            context.fill(Path(ellipseIn: CGRect(x: 143, y: 230, width: 14, height: 7)), with: .color(rgb(1, 0.55, 0.6)))
            context.stroke(mouth, with: .color(line), lineWidth: 2)
        case .surprised:
            let o = CGRect(x: 144, y: 222, width: 12, height: 14)
            context.fill(Path(ellipseIn: o), with: .color(rgb(0.7, 0.25, 0.3)))
            context.stroke(Path(ellipseIn: o), with: .color(line), lineWidth: 2)
        case .sad:
            mouth.move(to: CGPoint(x: 142, y: 230))
            mouth.addQuadCurve(to: CGPoint(x: 158, y: 230), control: CGPoint(x: 150, y: 223))
            context.stroke(mouth, with: .color(line), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
        case .angry:
            mouth.move(to: CGPoint(x: 140, y: 229))
            mouth.addLine(to: CGPoint(x: 146, y: 225))
            mouth.addLine(to: CGPoint(x: 154, y: 229))
            mouth.addLine(to: CGPoint(x: 160, y: 225))
            context.stroke(mouth, with: .color(line), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
        case .blush, .shy:
            mouth.move(to: CGPoint(x: 142, y: 228))
            mouth.addQuadCurve(to: CGPoint(x: 150, y: 226), control: CGPoint(x: 146, y: 224))
            mouth.addQuadCurve(to: CGPoint(x: 158, y: 228), control: CGPoint(x: 154, y: 231))
            context.stroke(mouth, with: .color(line), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
        }
    }

    // MARK: 髪（前）

    private func frontHair(_ look: Look, _ context: inout GraphicsContext) {
        var bangs = Path()
        bangs.move(to: CGPoint(x: 72, y: 150))
        if look.style == .long {
            // ぱっつん
            bangs.addLine(to: CGPoint(x: 84, y: 138))
            for i in 0...8 {
                let x = 92.0 + Double(i) * 14.5
                bangs.addLine(to: CGPoint(x: x, y: i % 2 == 0 ? 146 : 140))
            }
            bangs.addLine(to: CGPoint(x: 216, y: 138))
        } else {
            // ぎざぎざの前髪
            let tips: [(Double, Double)] = [(84, 168), (96, 122), (110, 156), (124, 116), (140, 152), (150, 112),
                                            (162, 150), (178, 118), (190, 156), (204, 124), (216, 168)]
            for (x, y) in tips { bangs.addLine(to: CGPoint(x: x, y: y)) }
        }
        bangs.addLine(to: CGPoint(x: 228, y: 150))
        bangs.addCurve(to: CGPoint(x: 150, y: 24), control1: CGPoint(x: 236, y: 70), control2: CGPoint(x: 205, y: 24))
        bangs.addCurve(to: CGPoint(x: 72, y: 150), control1: CGPoint(x: 95, y: 24), control2: CGPoint(x: 64, y: 70))
        context.fill(bangs, with: .color(look.hair))
        context.stroke(bangs, with: .color(look.hairDark), lineWidth: 2)
        // 横の髪（ほおにかかる）
        let sideLength: Double = look.style == .long ? 320 : (look.style == .twin ? 235 : 225)
        for side in [-1.0, 1.0] {
            var lock = Path()
            lock.move(to: CGPoint(x: 150 + side * 70, y: 110))
            lock.addCurve(to: CGPoint(x: 150 + side * 62, y: sideLength),
                          control1: CGPoint(x: 150 + side * 82, y: 170), control2: CGPoint(x: 150 + side * 72, y: sideLength - 40))
            lock.addCurve(to: CGPoint(x: 150 + side * 56, y: 120),
                          control1: CGPoint(x: 150 + side * 58, y: sideLength - 50), control2: CGPoint(x: 150 + side * 52, y: 170))
            lock.closeSubpath()
            context.fill(lock, with: .color(look.hair))
            context.stroke(lock, with: .color(look.hairDark), lineWidth: 1.5)
        }
        // 天使の輪
        var shine = Path()
        shine.addArc(center: CGPoint(x: 150, y: 120), radius: 62, startAngle: .degrees(205), endAngle: .degrees(335),
                     clockwise: false)
        context.stroke(shine, with: .color(.white.opacity(0.45)), style: StrokeStyle(lineWidth: 6, lineCap: .round,
                                                                                       dash: [14, 8]))
    }

    private func accessories(_ look: Look, _ context: inout GraphicsContext) {
        switch heroine {
        case .hinata:
            // 星のヘアピン
            context.fill(star(center: CGPoint(x: 198, y: 92), radius: 12), with: .color(rgb(1, 0.85, 0.3)))
            context.stroke(star(center: CGPoint(x: 198, y: 92), radius: 12), with: .color(rgb(0.8, 0.55, 0.1)), lineWidth: 1.5)
        case .shizuku:
            // めがね
            for x in [118.0, 182.0] {
                let frame = Path(roundedRect: CGRect(x: x - 24, y: 160, width: 48, height: 40), cornerRadius: 12)
                context.fill(frame, with: .color(.white.opacity(0.08)))
                context.stroke(frame, with: .color(rgb(0.35, 0.25, 0.45)), lineWidth: 2.5)
            }
            var bridge = Path()
            bridge.move(to: CGPoint(x: 142, y: 176))
            bridge.addQuadCurve(to: CGPoint(x: 158, y: 176), control: CGPoint(x: 150, y: 170))
            context.stroke(bridge, with: .color(rgb(0.35, 0.25, 0.45)), lineWidth: 2.5)
        case .rin:
            // ツインテールのリボン
            for side in [-1.0, 1.0] {
                let c = CGPoint(x: 150 + side * 86, y: 92)
                var bow = Path()
                bow.move(to: c)
                bow.addLine(to: CGPoint(x: c.x - 20, y: c.y - 14))
                bow.addLine(to: CGPoint(x: c.x - 20, y: c.y + 14))
                bow.closeSubpath()
                bow.move(to: c)
                bow.addLine(to: CGPoint(x: c.x + 20, y: c.y - 14))
                bow.addLine(to: CGPoint(x: c.x + 20, y: c.y + 14))
                bow.closeSubpath()
                context.fill(bow, with: .color(rgb(0.95, 0.3, 0.4)))
                context.fill(Path(ellipseIn: CGRect(x: c.x - 6, y: c.y - 6, width: 12, height: 12)),
                             with: .color(rgb(0.85, 0.2, 0.3)))
            }
        }
    }

    private func star(center: CGPoint, radius: Double) -> Path {
        var path = Path()
        for i in 0..<10 {
            let r = i % 2 == 0 ? radius : radius * 0.45
            let angle = Double(i) * .pi / 5 - .pi / 2
            let point = CGPoint(x: center.x + cos(angle) * r, y: center.y + sin(angle) * r)
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}

// MARK: - 背景

enum Backdrop: String, Codable {
    case black, roomMorning, street, classroom, classroomEvening, library, libraryEvening
    case rooftop, rooftopSunset, rooftopNight, clubroom, courtyard, shopping, sakuraHill
}

/// 決まった並びの「でたらめな」数（背景の本の色などを、毎回同じにする）
private struct Seeded {
    var state: UInt64
    mutating func next() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double((state >> 33) % 10_000) / 10_000
    }
}

struct BackdropView: View {
    let backdrop: Backdrop

    var body: some View {
        ZStack {
            if let image = RomanceImages.background(backdrop) {
                GeometryReader { geo in
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                }
            } else {
                Canvas { context, size in
                    draw(size: size, in: &context)
                }
            }
            if [Backdrop.street, .sakuraHill, .courtyard].contains(backdrop) {
                PetalsView()
            }
        }
        .ignoresSafeArea()
    }

    private func draw(size: CGSize, in context: inout GraphicsContext) {
        let w = size.width, h = size.height
        let full = CGRect(origin: .zero, size: size)
        switch backdrop {
        case .black:
            context.fill(Path(full), with: .color(.black))
        case .roomMorning:
            room(w, h, night: false, &context)
        case .street:
            sky(full, [rgb(0.55, 0.78, 1), rgb(0.85, 0.93, 1)], &context)
            clouds(w, h * 0.3, &context)
            var road = Path()
            road.move(to: CGPoint(x: w * 0.42, y: h * 0.45))
            road.addLine(to: CGPoint(x: w * 0.58, y: h * 0.45))
            road.addLine(to: CGPoint(x: w * 1.1, y: h))
            road.addLine(to: CGPoint(x: -w * 0.1, y: h))
            road.closeSubpath()
            context.fill(Path(CGRect(x: 0, y: h * 0.45, width: w, height: h * 0.55)), with: .color(rgb(0.6, 0.78, 0.55)))
            context.fill(road, with: .color(rgb(0.75, 0.73, 0.72)))
            for i in 0..<4 {
                let t = Double(i) / 3
                let scale = 0.4 + t * 0.9
                sakuraTree(x: w * (0.3 - t * 0.28), base: h * (0.5 + t * 0.4), scale: scale * w / 400, &context)
                sakuraTree(x: w * (0.7 + t * 0.28), base: h * (0.5 + t * 0.4), scale: scale * w / 400, &context)
            }
        case .classroom, .classroomEvening:
            classroom(w, h, evening: backdrop == .classroomEvening, &context)
        case .library, .libraryEvening:
            library(w, h, evening: backdrop == .libraryEvening, &context)
        case .rooftop:
            rooftop(w, h, sky: [rgb(0.4, 0.65, 1), rgb(0.8, 0.9, 1)], &context)
        case .rooftopSunset:
            rooftop(w, h, sky: [rgb(0.35, 0.3, 0.6), rgb(1, 0.5, 0.35), rgb(1, 0.82, 0.5)], &context)
        case .rooftopNight:
            rooftop(w, h, sky: [rgb(0.03, 0.05, 0.18), rgb(0.12, 0.15, 0.35)], &context)
        case .clubroom:
            clubroom(w, h, &context)
        case .courtyard:
            sky(full, [rgb(0.5, 0.75, 1), rgb(0.88, 0.95, 1)], &context)
            context.fill(Path(CGRect(x: 0, y: h * 0.12, width: w, height: h * 0.5)), with: .color(rgb(0.93, 0.9, 0.84)))
            for row in 0..<3 {
                for column in 0..<5 {
                    context.fill(Path(CGRect(x: w * (0.06 + Double(column) * 0.19), y: h * (0.17 + Double(row) * 0.14),
                                             width: w * 0.13, height: h * 0.08)),
                                 with: .color(rgb(0.6, 0.78, 0.92)))
                }
            }
            context.fill(Path(CGRect(x: 0, y: h * 0.62, width: w, height: h * 0.38)), with: .color(rgb(0.55, 0.8, 0.45)))
            sakuraTree(x: w * 0.2, base: h * 0.75, scale: w / 300, &context)
            context.fill(Path(CGRect(x: w * 0.55, y: h * 0.78, width: w * 0.35, height: h * 0.025)), with: .color(rgb(0.6, 0.4, 0.25)))
            context.fill(Path(CGRect(x: w * 0.58, y: h * 0.8, width: w * 0.02, height: h * 0.05)), with: .color(rgb(0.4, 0.3, 0.2)))
            context.fill(Path(CGRect(x: w * 0.85, y: h * 0.8, width: w * 0.02, height: h * 0.05)), with: .color(rgb(0.4, 0.3, 0.2)))
        case .shopping:
            sky(full, [rgb(0.3, 0.25, 0.55), rgb(1, 0.55, 0.45), rgb(1, 0.8, 0.55)], &context)
            var random = Seeded(state: 7)
            var x = -10.0
            while x < w {
                let bw = w * (0.18 + random.next() * 0.12)
                let bh = h * (0.35 + random.next() * 0.25)
                let rect = CGRect(x: x, y: h * 0.75 - bh, width: bw, height: bh)
                context.fill(Path(rect), with: .color(rgb(0.35 + random.next() * 0.2, 0.28, 0.35)))
                for wy in stride(from: rect.minY + 14, to: rect.maxY - 60, by: 26) {
                    for wx in stride(from: rect.minX + 10, to: rect.maxX - 14, by: 22) where random.next() > 0.35 {
                        context.fill(Path(CGRect(x: wx, y: wy, width: 12, height: 14)),
                                     with: .color(rgb(1, 0.85, 0.5).opacity(0.85)))
                    }
                }
                // ひさし
                let awning = CGRect(x: rect.minX, y: h * 0.62, width: bw, height: h * 0.04)
                let colors = [rgb(0.9, 0.3, 0.3), rgb(0.2, 0.55, 0.4), rgb(0.95, 0.65, 0.2)]
                let awningColor = colors[Int(random.next() * 3) % 3]
                for i in 0..<Int(bw / 14) {
                    context.fill(Path(CGRect(x: awning.minX + Double(i) * 14, y: awning.minY, width: 7, height: awning.height)),
                                 with: .color(i % 2 == 0 ? awningColor : .white))
                }
                x += bw + 4
            }
            context.fill(Path(CGRect(x: 0, y: h * 0.75, width: w, height: h * 0.25)), with: .color(rgb(0.55, 0.5, 0.5)))
            // ちょうちん
            for i in 0..<8 {
                let lx = w * (0.06 + Double(i) * 0.125)
                context.fill(Path(ellipseIn: CGRect(x: lx - 30, y: h * 0.18 - 30, width: 60, height: 60)),
                             with: .color(rgb(1, 0.6, 0.3).opacity(0.25)))
                context.fill(Path(ellipseIn: CGRect(x: lx - 9, y: h * 0.18 - 12, width: 18, height: 24)),
                             with: .color(rgb(1, 0.45, 0.35)))
            }
        case .sakuraHill:
            sky(full, [rgb(0.04, 0.05, 0.2), rgb(0.2, 0.15, 0.4), rgb(0.45, 0.25, 0.45)], &context)
            stars(w, h * 0.5, &context)
            var hill = Path()
            hill.move(to: CGPoint(x: 0, y: h * 0.78))
            hill.addQuadCurve(to: CGPoint(x: w, y: h * 0.78), control: CGPoint(x: w / 2, y: h * 0.62))
            hill.addLine(to: CGPoint(x: w, y: h))
            hill.addLine(to: CGPoint(x: 0, y: h))
            hill.closeSubpath()
            context.fill(hill, with: .color(rgb(0.12, 0.18, 0.2)))
            sakuraTree(x: w / 2, base: h * 0.72, scale: w / 170, night: true, &context)
            // ぼんぼり
            for i in 0..<6 {
                let bx = w * (0.08 + Double(i) * 0.168)
                let by = h * (0.84 + (i % 2 == 0 ? 0.0 : 0.03))
                context.fill(Path(ellipseIn: CGRect(x: bx - 40, y: by - 40, width: 80, height: 80)),
                             with: .color(rgb(1, 0.7, 0.4).opacity(0.25)))
                context.fill(Path(roundedRect: CGRect(x: bx - 8, y: by - 12, width: 16, height: 22), cornerRadius: 4),
                             with: .color(rgb(1, 0.85, 0.6)))
            }
        }
    }

    // MARK: 部品

    private func sky(_ rect: CGRect, _ colors: [Color], _ context: inout GraphicsContext) {
        context.fill(Path(rect), with: .linearGradient(Gradient(colors: colors), startPoint: .zero,
                                                       endPoint: CGPoint(x: 0, y: rect.height * 0.75)))
    }

    private func clouds(_ w: Double, _ y: Double, _ context: inout GraphicsContext) {
        var random = Seeded(state: 3)
        for _ in 0..<4 {
            let cx = random.next() * w, cy = y * (0.3 + random.next() * 0.7)
            for i in 0..<4 {
                context.fill(Path(ellipseIn: CGRect(x: cx + Double(i) * 22 - 40, y: cy - Double(i % 2) * 10, width: 50, height: 32)),
                             with: .color(.white.opacity(0.85)))
            }
        }
    }

    private func stars(_ w: Double, _ h: Double, _ context: inout GraphicsContext) {
        var random = Seeded(state: 11)
        for _ in 0..<70 {
            let r = 0.8 + random.next() * 1.8
            context.fill(Path(ellipseIn: CGRect(x: random.next() * w, y: random.next() * h, width: r, height: r)),
                         with: .color(.white.opacity(0.5 + random.next() * 0.5)))
        }
    }

    private func sakuraTree(x: Double, base: Double, scale: Double, night: Bool = false, _ context: inout GraphicsContext) {
        var trunk = Path()
        trunk.move(to: CGPoint(x: x - 8 * scale, y: base))
        trunk.addLine(to: CGPoint(x: x - 4 * scale, y: base - 60 * scale))
        trunk.addLine(to: CGPoint(x: x + 4 * scale, y: base - 60 * scale))
        trunk.addLine(to: CGPoint(x: x + 8 * scale, y: base))
        trunk.closeSubpath()
        context.fill(trunk, with: .color(night ? rgb(0.2, 0.12, 0.12) : rgb(0.45, 0.3, 0.25)))
        var random = Seeded(state: UInt64(abs(x * 13 + base)))
        for _ in 0..<16 {
            let bx = x + (random.next() - 0.5) * 90 * scale
            let by = base - 70 * scale + (random.next() - 0.6) * 55 * scale
            let r = (18 + random.next() * 16) * scale
            let pink = night ? rgb(0.95, 0.7, 0.8) : rgb(1, 0.78 + random.next() * 0.1, 0.85)
            context.fill(Path(ellipseIn: CGRect(x: bx - r, y: by - r, width: r * 2, height: r * 2)),
                         with: .color(pink.opacity(0.92)))
        }
    }

    private func room(_ w: Double, _ h: Double, night: Bool, _ context: inout GraphicsContext) {
        context.fill(Path(CGRect(x: 0, y: 0, width: w, height: h)), with: .color(night ? rgb(0.25, 0.25, 0.4) : rgb(0.96, 0.92, 0.85)))
        let window = CGRect(x: w * 0.2, y: h * 0.12, width: w * 0.6, height: h * 0.35)
        context.fill(Path(window), with: .linearGradient(
            Gradient(colors: night ? [rgb(0.05, 0.05, 0.2), rgb(0.15, 0.15, 0.4)] : [rgb(0.55, 0.8, 1), rgb(1, 0.95, 0.85)]),
            startPoint: CGPoint(x: 0, y: window.minY), endPoint: CGPoint(x: 0, y: window.maxY)))
        context.stroke(Path(window), with: .color(.white), lineWidth: 8)
        context.stroke(Path(CGRect(x: window.midX - 2, y: window.minY, width: 4, height: window.height)), with: .color(.white), lineWidth: 4)
        // カーテン
        context.fill(Path(CGRect(x: window.minX - 30, y: window.minY - 10, width: 40, height: window.height + 30)),
                     with: .color(rgb(0.95, 0.65, 0.6)))
        context.fill(Path(CGRect(x: window.maxX - 10, y: window.minY - 10, width: 40, height: window.height + 30)),
                     with: .color(rgb(0.95, 0.65, 0.6)))
        // ベッド
        context.fill(Path(roundedRect: CGRect(x: -20, y: h * 0.68, width: w * 0.75, height: h * 0.35), cornerRadius: 20),
                     with: .color(rgb(0.6, 0.75, 0.95)))
        context.fill(Path(roundedRect: CGRect(x: 10, y: h * 0.64, width: w * 0.3, height: h * 0.08), cornerRadius: 14),
                     with: .color(.white))
        context.fill(Path(CGRect(x: 0, y: h * 0.9, width: w, height: h * 0.1)), with: .color(rgb(0.7, 0.55, 0.4)))
    }

    private func classroom(_ w: Double, _ h: Double, evening: Bool, _ context: inout GraphicsContext) {
        context.fill(Path(CGRect(x: 0, y: 0, width: w, height: h)), with: .color(rgb(0.95, 0.92, 0.84)))
        // 窓
        for i in 0..<3 {
            let window = CGRect(x: w * (0.04 + Double(i) * 0.32), y: h * 0.08, width: w * 0.28, height: h * 0.3)
            context.fill(Path(window), with: .linearGradient(
                Gradient(colors: evening ? [rgb(0.9, 0.5, 0.35), rgb(1, 0.8, 0.5)] : [rgb(0.55, 0.78, 1), rgb(0.9, 0.95, 1)]),
                startPoint: CGPoint(x: 0, y: window.minY), endPoint: CGPoint(x: 0, y: window.maxY)))
            context.stroke(Path(window), with: .color(rgb(0.75, 0.75, 0.75)), lineWidth: 5)
        }
        // 黒板
        context.fill(Path(CGRect(x: w * 0.1, y: h * 0.42, width: w * 0.8, height: h * 0.16)), with: .color(rgb(0.15, 0.35, 0.25)))
        context.stroke(Path(CGRect(x: w * 0.1, y: h * 0.42, width: w * 0.8, height: h * 0.16)), with: .color(rgb(0.55, 0.4, 0.25)), lineWidth: 6)
        // 床と机
        context.fill(Path(CGRect(x: 0, y: h * 0.62, width: w, height: h * 0.38)), with: .color(rgb(0.72, 0.55, 0.38)))
        for row in 0..<3 {
            let y = h * (0.66 + Double(row) * 0.1)
            let size = 0.16 + Double(row) * 0.04
            for column in 0..<4 {
                let x = w * (0.08 + Double(column) * 0.24)
                context.fill(Path(CGRect(x: x, y: y, width: w * size, height: h * 0.035)), with: .color(rgb(0.85, 0.7, 0.5)))
                context.fill(Path(CGRect(x: x + 4, y: y + h * 0.035, width: 4, height: h * 0.05)), with: .color(rgb(0.5, 0.5, 0.55)))
            }
        }
        if evening {
            context.fill(Path(CGRect(x: 0, y: 0, width: w, height: h)), with: .color(rgb(1, 0.55, 0.3).opacity(0.18)))
        }
    }

    private func library(_ w: Double, _ h: Double, evening: Bool, _ context: inout GraphicsContext) {
        context.fill(Path(CGRect(x: 0, y: 0, width: w, height: h)), with: .color(rgb(0.85, 0.78, 0.65)))
        var random = Seeded(state: 21)
        let bookColors = [rgb(0.7, 0.25, 0.25), rgb(0.2, 0.35, 0.55), rgb(0.25, 0.5, 0.35), rgb(0.85, 0.7, 0.35),
                          rgb(0.5, 0.3, 0.5), rgb(0.9, 0.9, 0.85)]
        for shelf in 0..<5 {
            let y = h * (0.08 + Double(shelf) * 0.13)
            context.fill(Path(CGRect(x: 0, y: y + h * 0.11, width: w, height: h * 0.02)), with: .color(rgb(0.45, 0.3, 0.2)))
            var x = 0.0
            while x < w {
                let bw = 8 + random.next() * 10
                let bh = h * (0.07 + random.next() * 0.035)
                context.fill(Path(CGRect(x: x, y: y + h * 0.11 - bh, width: bw, height: bh)),
                             with: .color(bookColors[Int(random.next() * 6) % 6]))
                x += bw + 1
            }
        }
        context.fill(Path(CGRect(x: 0, y: h * 0.75, width: w, height: h * 0.25)), with: .color(rgb(0.55, 0.38, 0.25)))
        context.fill(Path(CGRect(x: w * 0.1, y: h * 0.78, width: w * 0.8, height: h * 0.04)), with: .color(rgb(0.7, 0.5, 0.32)))
        context.fill(Path(CGRect(x: 0, y: 0, width: w, height: h)), with: .linearGradient(
            Gradient(colors: [(evening ? rgb(1, 0.6, 0.3) : rgb(1, 0.95, 0.8)).opacity(0.3), .clear]),
            startPoint: .zero, endPoint: CGPoint(x: w, y: h)))
    }

    private func rooftop(_ w: Double, _ h: Double, sky colors: [Color], _ context: inout GraphicsContext) {
        sky(CGRect(x: 0, y: 0, width: w, height: h), colors, &context)
        if backdrop == .rooftopNight {
            stars(w, h * 0.6, &context)
            context.fill(Path(ellipseIn: CGRect(x: w * 0.7, y: h * 0.1, width: 46, height: 46)), with: .color(rgb(1, 0.97, 0.85)))
        } else if backdrop == .rooftop {
            clouds(w, h * 0.35, &context)
        }
        context.fill(Path(CGRect(x: 0, y: h * 0.72, width: w, height: h * 0.28)),
                     with: .color(backdrop == .rooftopNight ? rgb(0.3, 0.3, 0.38) : rgb(0.72, 0.72, 0.7)))
        // フェンス
        let fenceTop = h * 0.5, fenceBottom = h * 0.74
        let fenceColor = backdrop == .rooftopNight ? rgb(0.5, 0.55, 0.6) : rgb(0.35, 0.5, 0.45)
        for x in stride(from: 0.0, through: w, by: 16) {
            var d1 = Path()
            d1.move(to: CGPoint(x: x, y: fenceTop))
            d1.addLine(to: CGPoint(x: x + 40, y: fenceBottom))
            var d2 = Path()
            d2.move(to: CGPoint(x: x + 40, y: fenceTop))
            d2.addLine(to: CGPoint(x: x, y: fenceBottom))
            context.stroke(d1, with: .color(fenceColor.opacity(0.6)), lineWidth: 1)
            context.stroke(d2, with: .color(fenceColor.opacity(0.6)), lineWidth: 1)
        }
        context.fill(Path(CGRect(x: 0, y: fenceTop - 4, width: w, height: 6)), with: .color(fenceColor))
        for x in stride(from: 0.0, through: w, by: w / 5) {
            context.fill(Path(CGRect(x: x, y: fenceTop, width: 5, height: fenceBottom - fenceTop)), with: .color(fenceColor))
        }
    }

    private func clubroom(_ w: Double, _ h: Double, _ context: inout GraphicsContext) {
        context.fill(Path(CGRect(x: 0, y: 0, width: w, height: h)), with: .color(rgb(0.88, 0.85, 0.8)))
        // コルクボードと写真
        let board = CGRect(x: w * 0.12, y: h * 0.12, width: w * 0.76, height: h * 0.32)
        context.fill(Path(board), with: .color(rgb(0.78, 0.6, 0.4)))
        context.stroke(Path(board), with: .color(rgb(0.5, 0.35, 0.22)), lineWidth: 6)
        var random = Seeded(state: 5)
        for _ in 0..<9 {
            let pw = w * 0.13, ph = pw * 0.75
            let px = board.minX + 8 + random.next() * (board.width - pw - 16)
            let py = board.minY + 8 + random.next() * (board.height - ph - 16)
            context.fill(Path(CGRect(x: px, y: py, width: pw, height: ph)), with: .color(.white))
            context.fill(Path(CGRect(x: px + 4, y: py + 4, width: pw - 8, height: ph - 8)),
                         with: .color(rgb(0.4 + random.next() * 0.4, 0.5 + random.next() * 0.3, 0.6 + random.next() * 0.3)))
            context.fill(Path(ellipseIn: CGRect(x: px + pw / 2 - 3, y: py - 2, width: 6, height: 6)), with: .color(.red))
        }
        // 赤いランプ（暗室用）
        context.fill(Path(ellipseIn: CGRect(x: w * 0.8 - 40, y: h * 0.04 - 20, width: 80, height: 80)), with: .color(.red.opacity(0.15)))
        context.fill(Path(ellipseIn: CGRect(x: w * 0.8 - 10, y: h * 0.04 + 10, width: 20, height: 20)), with: .color(rgb(0.9, 0.2, 0.2)))
        // 机
        context.fill(Path(CGRect(x: 0, y: h * 0.7, width: w, height: h * 0.3)), with: .color(rgb(0.6, 0.48, 0.38)))
        context.fill(Path(CGRect(x: w * 0.05, y: h * 0.72, width: w * 0.9, height: h * 0.05)), with: .color(rgb(0.45, 0.35, 0.28)))
    }
}

/// 舞い落ちる桜の花びら
private struct PetalsView: View {
    private let petals: [(x: Double, speed: Double, sway: Double, size: Double, phase: Double)] = {
        var random = Seeded(state: 99)
        return (0..<26).map { _ in
            (x: random.next(), speed: 0.04 + random.next() * 0.06, sway: 10 + random.next() * 25,
             size: 5 + random.next() * 5, phase: random.next())
        }
    }()
    @State private var start = Date()

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSince(start)
                for petal in petals {
                    let progress = (petal.phase + t * petal.speed).truncatingRemainder(dividingBy: 1)
                    let y = progress * (size.height + 40) - 20
                    let x = petal.x * size.width + sin(t * 1.3 + petal.phase * 6) * petal.sway
                    var layer = context
                    layer.translateBy(x: x, y: y)
                    layer.rotate(by: .radians(t * 2 + petal.phase * 6))
                    layer.fill(Path(ellipseIn: CGRect(x: -petal.size / 2, y: -petal.size / 4,
                                                      width: petal.size, height: petal.size / 2)),
                               with: .color(Color(red: 1, green: 0.78, blue: 0.85)))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - 入れた画像

/// 恋愛アドベンチャーの画像（立ち絵・背景・イベント CG）。
/// `FilmCamera/Game/Romance/Images/` に決まった名前の PNG（または JPG）を置くと、図形の絵の代わりに使う。
/// 名前は docs/ROMANCE_IMAGES.md を参照。ない画像は図形の絵のまま
enum RomanceImages {
    private static let cache = NSCache<NSString, UIImage>()
    private static var missing: Set<String> = []

    static func image(_ name: String) -> UIImage? {
        if let cached = cache.object(forKey: name as NSString) { return cached }
        if missing.contains(name) { return nil }
        let found = UIImage(named: name)
            ?? ["png", "jpg", "jpeg"].lazy.compactMap { ext in
                Bundle.main.path(forResource: name, ofType: ext).flatMap(UIImage.init(contentsOfFile:))
            }.first
        if let found {
            cache.setObject(found, forKey: name as NSString)
        } else {
            missing.insert(name)
        }
        return found
    }

    /// 立ち絵。その表情がなければ、ふつうの顔の画像を使う
    static func sprite(_ heroine: Heroine, _ face: Face) -> UIImage? {
        image("\(heroine.rawValue)_\(face.rawValue)") ?? image("\(heroine.rawValue)_normal")
    }

    static func background(_ backdrop: Backdrop) -> UIImage? {
        guard backdrop != .black else { return nil }
        return image("bg_" + backdrop.fileName)
    }

    static func cg(_ name: String) -> UIImage? { image("cg_" + name) }
}

extension Backdrop {
    /// 画像のファイル名（bg_ の後ろ）
    var fileName: String {
        switch self {
        case .black: return "black"
        case .roomMorning: return "room_morning"
        case .street: return "street"
        case .classroom: return "classroom"
        case .classroomEvening: return "classroom_evening"
        case .library: return "library"
        case .libraryEvening: return "library_evening"
        case .rooftop: return "rooftop"
        case .rooftopSunset: return "rooftop_sunset"
        case .rooftopNight: return "rooftop_night"
        case .clubroom: return "clubroom"
        case .courtyard: return "courtyard"
        case .shopping: return "shopping"
        case .sakuraHill: return "sakura_hill"
        }
    }
}
