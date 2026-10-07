import SwiftUI
import UIKit

/// 起動したときの画面。黒い背景でレンズの絞りがゆっくり開き、ロゴが浮かび、シャッターの手応えで終わる。
/// iOS の起動画面（Info.plist の UILaunchScreen）も同じ色（LaunchBackground）なので、つなぎ目が見えない
struct SplashView: View {
    /// 終わったら呼ばれる
    var onFinish: () -> Void

    @State private var start = Date()
    @State private var clicked = false
    @State private var finished = false

    private static let background = Color(red: 0.071, green: 0.071, blue: 0.071)
    private static let duration = 1.7

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSince(start)
            // 絞りが開く（0 → 1、ゆっくり止まる）
            let open = ease(clamp((t - 0.15) / 0.75))
            // 文字が浮かぶ
            let text = ease(clamp((t - 0.5) / 0.55))
            // シャッターの光（一瞬だけ）
            let flash = max(0, 1 - abs(t - 1.15) / 0.12)
            ZStack {
                Self.background.ignoresSafeArea()
                VStack(spacing: 34) {
                    Lens(open: open, flash: flash)
                        .frame(width: 176, height: 176)
                        .scaleEffect(0.94 + 0.06 * open)
                    VStack(spacing: 10) {
                        Text("FILM CAMERA")
                            .font(.system(.callout, design: .monospaced).weight(.semibold))
                            .tracking(4 + 6 * (1 - text))
                            .foregroundStyle(.white.opacity(0.92))
                        HStack(spacing: 8) {
                            Circle()
                                .fill(Color.accentColor)
                                .frame(width: 5, height: 5)
                            Text("CC—1  ·  SHARED ALBUM")
                                .font(.system(.caption2, design: .monospaced))
                                .tracking(2)
                                .foregroundStyle(.white.opacity(0.4))
                        }
                    }
                    .opacity(text)
                    .offset(y: 8 * (1 - text))
                }
                // 下の細い線（読み込みの進み具合のように伸びる）
                VStack {
                    Spacer()
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: 44 * clamp(t / Self.duration), height: 2)
                        .opacity(0.8)
                        .padding(.bottom, 48)
                }
            }
            .onChange(of: t >= 1.1) { _, reached in
                if reached && !clicked {
                    clicked = true
                    UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.8)
                }
            }
            .onChange(of: t >= Self.duration) { _, reached in
                if reached && !finished {
                    finished = true
                    onFinish()
                }
            }
        }
        .onAppear { start = Date() }
    }

    private func clamp(_ x: Double) -> Double { min(1, max(0, x)) }
    private func ease(_ x: Double) -> Double { 1 - pow(1 - x, 3) }
}

/// レンズ：鏡筒の目盛り、6 枚羽根の絞り、奥のガラスの反射
private struct Lens: View {
    let open: Double
    let flash: Double

    var body: some View {
        Canvas { context, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let outer = min(size.width, size.height) / 2
            let inner = outer * 0.7

            // 鏡筒
            context.fill(circle(c, outer), with: .color(Color(white: 0.13)))
            context.stroke(circle(c, outer - 1), with: .color(Color(white: 0.22)), lineWidth: 1.5)
            // 目盛り
            for i in 0..<36 {
                let a = Double(i) / 36 * 2 * .pi - .pi / 2
                let long = i % 6 == 0
                let r1 = outer - 6, r2 = outer - (long ? 15 : 10)
                var tick = Path()
                tick.move(to: point(c, r1, a))
                tick.addLine(to: point(c, r2, a))
                context.stroke(tick, with: .color(.white.opacity(long ? 0.45 : 0.18)), lineWidth: long ? 1.4 : 1)
            }
            // オレンジの印
            context.fill(circle(point(c, outer - 10, -.pi / 2), 2.6), with: .color(.accentColor))

            // 絞りの羽根（奥）
            context.fill(circle(c, inner), with: .color(Color(white: 0.06)))
            let blades = 6
            let rotation = open * 0.7
            let hole = 3 + open * inner * 0.68
            var opening = Path()
            for i in 0..<blades {
                let a = Double(i) / Double(blades) * 2 * .pi + rotation
                if i == 0 { opening.move(to: point(c, hole, a)) } else { opening.addLine(to: point(c, hole, a)) }
            }
            opening.closeSubpath()
            // 開いた穴の向こう：ガラスの奥の深い青と、光の反射
            context.drawLayer { layer in
                layer.clip(to: opening)
                layer.fill(circle(c, hole + 2), with: .radialGradient(
                    Gradient(colors: [Color(red: 0.16, green: 0.22, blue: 0.32), Color(red: 0.03, green: 0.04, blue: 0.07)]),
                    center: CGPoint(x: c.x - hole * 0.3, y: c.y - hole * 0.3), startRadius: 0, endRadius: hole * 1.3))
                layer.fill(circle(CGPoint(x: c.x - hole * 0.35, y: c.y - hole * 0.35), hole * 0.18),
                           with: .color(.white.opacity(0.18)))
                layer.fill(circle(c, hole + 2), with: .color(.white.opacity(flash * 0.85)))
            }
            // 羽根の合わせ目（穴の角から外へ）
            for i in 0..<blades {
                let a = Double(i) / Double(blades) * 2 * .pi + rotation
                var edge = Path()
                edge.move(to: point(c, hole, a))
                edge.addLine(to: point(c, inner, a + 1.15))
                context.stroke(edge, with: .color(.white.opacity(0.13)), lineWidth: 1.2)
            }
            context.stroke(opening, with: .color(.white.opacity(0.2)), lineWidth: 1)
            context.stroke(circle(c, inner), with: .color(Color(white: 0.25)), lineWidth: 1.5)

            // ガラスの映り込み
            var glare = Path()
            glare.addArc(center: c, radius: inner - 8, startAngle: .degrees(200), endAngle: .degrees(250), clockwise: false)
            context.stroke(glare, with: .color(.white.opacity(0.14)), style: StrokeStyle(lineWidth: 3, lineCap: .round))
        }
    }

    private func circle(_ c: CGPoint, _ r: Double) -> Path {
        Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
    }

    private func point(_ c: CGPoint, _ r: Double, _ a: Double) -> CGPoint {
        CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r)
    }
}
