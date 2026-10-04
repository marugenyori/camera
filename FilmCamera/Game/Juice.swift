import SwiftUI

// ゲームを気持ちよくする演出の部品（はじける粒、紙吹雪、画面の揺れ、浮かぶ点数）

/// 1 か所ではじける粒（キャンディが消えたとき、宝石がはまったとき）
struct Burst: Identifiable {
    let id = UUID()
    /// 盤面のマス単位の位置（左上が 0,0。マスの真ん中は +0.5）
    let x: CGFloat
    let y: CGFloat
    let color: Color
    var count = 10
    var power: CGFloat = 1
}

struct BurstView: View {
    let burst: Burst
    let cell: CGFloat
    @State private var go = false
    private let particles: [(angle: Double, distance: CGFloat, size: CGFloat, star: Bool)]

    init(burst: Burst, cell: CGFloat) {
        self.burst = burst
        self.cell = cell
        particles = (0..<burst.count).map { i in
            (angle: Double(i) / Double(burst.count) * 2 * .pi + Double.random(in: -0.3...0.3),
             distance: CGFloat.random(in: 0.6...1.4) * burst.power,
             size: CGFloat.random(in: 0.1...0.22),
             star: i.isMultiple(of: 3))
        }
    }

    var body: some View {
        ZStack {
            // 中心の光
            Circle()
                .fill(RadialGradient(colors: [.white, burst.color.opacity(0.6), .clear],
                                     center: .center, startRadius: 0, endRadius: cell * 0.8))
                .frame(width: cell * (go ? 2.2 : 0.4), height: cell * (go ? 2.2 : 0.4))
                .opacity(go ? 0 : 1)
            ForEach(particles.indices, id: \.self) { i in
                let p = particles[i]
                Group {
                    if p.star {
                        Image(systemName: "sparkle").resizable().foregroundStyle(.white)
                    } else {
                        Circle().fill(burst.color)
                    }
                }
                .frame(width: cell * p.size * 1.6, height: cell * p.size * 1.6)
                .offset(x: go ? CGFloat(cos(p.angle)) * cell * p.distance : 0,
                        y: go ? CGFloat(sin(p.angle)) * cell * p.distance + cell * 0.3 : 0)
                .scaleEffect(go ? 0.3 : 1)
                .opacity(go ? 0 : 1)
            }
        }
        .position(x: burst.x * cell, y: burst.y * cell)
        .allowsHitTesting(false)
        .onAppear { withAnimation(.easeOut(duration: 0.55)) { go = true } }
    }
}

/// 浮かび上がって消える文字（+120、COMBO など）
struct FloatingText: Identifiable {
    let id = UUID()
    let text: String
    let x: CGFloat
    let y: CGFloat
    var color: Color = .white
    var big = false
}

struct FloatingTextView: View {
    let item: FloatingText
    let cell: CGFloat
    @State private var popped = false
    @State private var faded = false

    var body: some View {
        Text(item.text)
            .font(.system(item.big ? .title : .headline, design: .rounded).weight(.black))
            .foregroundStyle(item.color)
            .shadow(color: .black.opacity(0.45), radius: 0, x: 1.5, y: 2)
            .scaleEffect(popped ? 1 : 0.3)
            .opacity(faded ? 0 : 1)
            .offset(y: faded ? -cell * 1.5 : 0)
            .position(x: item.x * cell, y: item.y * cell)
            .allowsHitTesting(false)
            .onAppear {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.45)) { popped = true }
                withAnimation(.easeIn(duration: 0.5).delay(0.45)) { faded = true }
            }
    }
}

/// 画面全体に降る紙吹雪（クリアしたとき）
struct ConfettiView: View {
    private struct Piece {
        let x: CGFloat
        let delay: Double
        let speed: CGFloat
        let sway: CGFloat
        let spin: Double
        let color: Color
        let width: CGFloat
    }

    private let pieces: [Piece]
    @State private var start = Date()

    init(count: Int = 120) {
        let colors: [Color] = [.pink, .yellow, .orange, .cyan, .purple, .green, .red, .mint]
        pieces = (0..<count).map { _ in
            Piece(x: .random(in: 0...1), delay: .random(in: 0...0.8), speed: .random(in: 0.25...0.5),
                  sway: .random(in: 10...40), spin: .random(in: 2...8), color: colors.randomElement() ?? .pink,
                  width: .random(in: 6...12))
        }
    }

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation) { timeline in
                let t = timeline.date.timeIntervalSince(start)
                Canvas { context, size in
                    for piece in pieces {
                        let elapsed = t - piece.delay
                        guard elapsed > 0 else { continue }
                        let y = -20 + CGFloat(elapsed) * piece.speed * size.height
                        guard y < size.height + 20 else { continue }
                        let x = piece.x * size.width + sin(CGFloat(elapsed) * 3 + piece.x * 10) * piece.sway
                        var layer = context
                        layer.translateBy(x: x, y: y)
                        layer.rotate(by: .radians(elapsed * piece.spin))
                        layer.fill(Path(CGRect(x: -piece.width / 2, y: -piece.width / 4,
                                               width: piece.width, height: piece.width / 2)),
                                   with: .color(piece.color))
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .onAppear { start = Date() }
    }
}

/// 画面を揺らす（大きな爆発のとき）。trigger を増やすたびに 1 回揺れる
struct Shake: GeometryEffect {
    var amount: CGFloat = 8
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: amount * sin(animatableData * .pi * 6),
                                              y: amount * 0.5 * cos(animatableData * .pi * 5)))
    }
}
