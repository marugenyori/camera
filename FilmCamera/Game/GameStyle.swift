import SwiftUI

/// ゲーム全体の見た目：赤・黒・白の 3 色、斜めに傾けた帯とカード、ギザギザの吹き出し、網点の背景、
/// 1 文字ずつ白黒を入れかえた切り抜き文字。怪盗もののゲームのメニューのような勢いのあるスタイル（ロゴや書体はまねない）
enum GameStyle {
    static let red = Color(red: 0.9, green: 0.04, blue: 0.1)
    static let ink = Color(red: 0.06, green: 0.06, blue: 0.07)
    static let gold = Color(red: 1, green: 0.84, blue: 0.2)

    /// 太い斜体
    static func font(_ size: CGFloat, weight: Font.Weight = .black) -> Font {
        .system(size: size, weight: weight).italic()
    }
}

/// 平行四辺形（左右の辺を傾ける）
struct SlantShape: Shape {
    var skew: CGFloat = 12

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + skew, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - skew, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// ギザギザの吹き出し（ふちが星のようにとがる。とがり方を少しずつばらつかせる）
struct BurstShape: Shape {
    var spikes = 16
    var depth: CGFloat = 0.16

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let count = spikes * 2
        var path = Path()
        for index in 0..<count {
            let angle = CGFloat(index) / CGFloat(count) * 2 * .pi - .pi / 2
            let jitter: CGFloat = [1, 0.92, 1.04, 0.96][index % 4]
            let radius: CGFloat = index % 2 == 0 ? 1 : (1 - depth) * jitter
            let point = CGPoint(x: center.x + cos(angle) * rect.width / 2 * radius,
                                y: center.y + sin(angle) * rect.height / 2 * radius)
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}

/// 網点と放射する帯の背景
struct HalftoneBackground: View {
    var base: Color = GameStyle.red
    var dots: Color = .black

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(base))
            // 左上から放射する、うすい黒の帯
            let center = CGPoint(x: size.width * 0.15, y: size.height * 0.1)
            let radius = max(size.width, size.height) * 1.8
            for index in stride(from: 0, to: 16, by: 2) {
                let a0 = CGFloat(index) / 16 * 2 * .pi, a1 = CGFloat(index + 1) / 16 * 2 * .pi
                var ray = Path()
                ray.move(to: center)
                ray.addLine(to: CGPoint(x: center.x + cos(a0) * radius, y: center.y + sin(a0) * radius))
                ray.addLine(to: CGPoint(x: center.x + cos(a1) * radius, y: center.y + sin(a1) * radius))
                ray.closeSubpath()
                context.fill(ray, with: .color(.black.opacity(0.13)))
            }
            // 網点（下ほど大きく）
            let step: CGFloat = 14
            var y: CGFloat = 0
            var row = 0
            while y < size.height + step {
                let r = max(0.5, y / max(size.height, 1) * step * 0.42)
                var x: CGFloat = row % 2 == 0 ? 0 : step / 2
                while x < size.width + step {
                    context.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                                 with: .color(dots.opacity(0.26)))
                    x += step
                }
                y += step * 0.87
                row += 1
            }
        }
        .ignoresSafeArea()
    }
}

/// 切り抜き文字：1 文字ずつ白黒を入れかえ、少しずつ傾けて貼る
struct RansomText: View {
    let text: String
    var size: CGFloat = 34

    var body: some View {
        HStack(spacing: 1) {
            ForEach(Array(text.enumerated()), id: \.offset) { index, character in
                let dark = index % 3 != 1
                Text(String(character))
                    .font(GameStyle.font(size * (index % 4 == 2 ? 1.14 : 1)))
                    .foregroundStyle(dark ? Color.white : Color.black)
                    .padding(.horizontal, size * 0.1)
                    .background(dark ? GameStyle.ink : Color.white)
                    .rotationEffect(.degrees([-6, 4, -2, 7, -4][index % 5]))
                    .offset(y: [0, -3, 2, -1, 3][index % 5])
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}

/// 押すと少し沈んで右下にずれるボタン
struct SlantButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .offset(x: configuration.isPressed ? 3 : 0, y: configuration.isPressed ? 3 : 0)
            .animation(.spring(duration: 0.18), value: configuration.isPressed)
    }
}

extension View {
    /// 斜めのカード：塗り・白いふち・右下にずらした影
    func slantCard(skew: CGFloat = 10, fill: Color = GameStyle.ink, shadow: Color = GameStyle.red,
                   border: Color = .white) -> some View {
        background(
            ZStack {
                SlantShape(skew: skew).fill(shadow).offset(x: 5, y: 5)
                SlantShape(skew: skew).fill(fill)
                SlantShape(skew: skew).stroke(border, lineWidth: 2)
            }
        )
    }
}
