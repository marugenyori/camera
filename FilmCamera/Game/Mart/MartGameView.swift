import SwiftUI

/// 「まちかどマート」の画面。画面のどこでも指でなぞると、そこがスティックになって店員が歩く
struct MartGameView: View {
    @StateObject private var game = MartGame()
    @Environment(\.dismiss) private var dismiss
    @State private var touchStart: CGPoint?
    @State private var touchNow: CGPoint?
    @State private var muted = GameAudio.shared.isMuted
    @State private var confirmingReset = false

    var body: some View {
        ZStack {
            TimelineView(.animation) { timeline in
                let time = timeline.date.timeIntervalSinceReferenceDate
                Canvas { context, size in
                    MartRenderer.draw(&context, size: size, game: game, camera: game.camera, time: time)
                }
            }
            .ignoresSafeArea()
            .gesture(stickGesture)
            joystick
            VStack {
                hud
                Spacer()
                if let banner = game.banner {
                    Text(banner)
                        .font(.title3.weight(.heavy))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(Color(red: 0.98, green: 0.55, blue: 0.15)))
                        .shadow(radius: 4)
                        .transition(.scale.combined(with: .opacity))
                        .task(id: banner) {
                            try? await Task.sleep(for: .seconds(1.8))
                            withAnimation { game.banner = nil }
                        }
                        .padding(.bottom, 120)
                }
                if game.level == 0 {
                    Text("左の台で商品を受け取って、棚に並べよう。レジに立つとお会計！")
                        .font(.footnote.weight(.bold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.bottom, 30)
                }
            }
            .allowsHitTesting(true)
        }
        .preferredColorScheme(.light)
        .animation(.spring(duration: 0.35), value: game.banner)
        .task { await run() }
        .onDisappear {
            game.save()
            GameAudio.shared.stop()
        }
        .confirmationDialog("最初からやり直しますか？", isPresented: $confirmingReset, titleVisibility: .visible) {
            Button("やり直す", role: .destructive) { game.reset() }
        }
    }

    @MainActor
    private func run() async {
        var last = Date()
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(16))
            let now = Date()
            game.update(min(now.timeIntervalSince(last), 0.05))
            last = now
        }
    }

    private var stickGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if touchStart == nil { touchStart = value.startLocation }
                touchNow = value.location
                let dx = value.location.x - value.startLocation.x
                let dy = value.location.y - value.startLocation.y
                let length = max(hypot(dx, dy), 0.001)
                let scale = min(length / 50, 1) / length
                game.stick = CGVector(dx: dx * scale, dy: dy * scale)
            }
            .onEnded { _ in
                touchStart = nil
                touchNow = nil
                game.stick = .zero
            }
    }

    @ViewBuilder
    private var joystick: some View {
        if let start = touchStart, let now = touchNow {
            let dx = now.x - start.x, dy = now.y - start.y
            let length = hypot(dx, dy)
            let clamp = min(length, 50) / max(length, 0.001)
            ZStack {
                Circle()
                    .fill(.white.opacity(0.35))
                    .frame(width: 120, height: 120)
                    .overlay(Circle().stroke(.white.opacity(0.8), lineWidth: 3))
                Circle()
                    .fill(.white.opacity(0.9))
                    .frame(width: 54, height: 54)
                    .shadow(radius: 3)
                    .offset(x: dx * clamp, y: dy * clamp)
            }
            .position(start)
            .allowsHitTesting(false)
        }
    }

    private var hud: some View {
        HStack(spacing: 10) {
            Menu {
                Button {
                    muted.toggle()
                    GameAudio.shared.isMuted = muted
                } label: {
                    Label(muted ? "音を出す" : "音を消す", systemImage: muted ? "speaker.wave.2" : "speaker.slash")
                }
                Button(role: .destructive) {
                    confirmingReset = true
                } label: {
                    Label("最初からやり直す", systemImage: "arrow.counterclockwise")
                }
                Button {
                    dismiss()
                } label: {
                    Label("ゲームをやめる", systemImage: "xmark")
                }
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(Circle().fill(.black.opacity(0.25)))
            }
            // レベル（解放した数）
            HStack(spacing: 0) {
                ZStack {
                    Image(systemName: "star.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(Color(red: 1, green: 0.8, blue: 0.1))
                        .shadow(color: .orange, radius: 1)
                    Text("\(game.level + 1)")
                        .font(.headline.weight(.black))
                        .foregroundStyle(.white)
                        .shadow(radius: 1)
                }
                .zIndex(1)
                GeometryReader { geo in
                    let fraction = CGFloat(game.level) / CGFloat(MartGame.steps.count)
                    ZStack(alignment: .leading) {
                        Capsule().fill(.black.opacity(0.25))
                        Capsule().fill(Color(red: 0.35, green: 0.8, blue: 0.3))
                            .frame(width: max(geo.size.width * fraction, 10))
                        Text(fraction >= 1 ? "MAX" : "\(game.level)/\(MartGame.steps.count)")
                            .font(.caption.weight(.heavy))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 20)
                .padding(.leading, -10)
            }
            .frame(maxWidth: 170)
            Spacer()
            HStack(spacing: 6) {
                Text("💵")
                Text("\(game.money)")
                    .font(.headline.weight(.heavy).monospacedDigit())
                    .contentTransition(.numericText())
                    .animation(.snappy, value: game.money)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Capsule().fill(.white))
            .shadow(color: .black.opacity(0.15), radius: 3, y: 2)
        }
        .padding(.horizontal, 14)
        .padding(.top, 4)
    }
}

// MARK: - 描く

/// 斜め上から見たお店を描く（立体はすべて図形で）
@MainActor
enum MartRenderer {
    struct Projection {
        let w: CGFloat
        let u: CGFloat
        let origin: CGPoint

        func p(_ x: CGFloat, _ y: CGFloat, _ z: CGFloat = 0) -> CGPoint {
            CGPoint(x: origin.x + (x - y) * w / 2, y: origin.y + (x + y) * w / 4 - z * u)
        }
    }

    static func polygon(_ points: [CGPoint]) -> Path {
        Path { path in
            guard let first = points.first else { return }
            path.move(to: first)
            for point in points.dropFirst() { path.addLine(to: point) }
            path.closeSubpath()
        }
    }

    /// 床の上の箱（見える面：上・左手前・右手前）
    static func box(_ context: inout GraphicsContext, _ pr: Projection, _ r: CGRect, z0: CGFloat, z1: CGFloat,
                    top: Color, left: Color, right: Color) {
        let x0 = r.minX, x1 = r.maxX, y0 = r.minY, y1 = r.maxY
        context.fill(polygon([pr.p(x0, y1, z0), pr.p(x1, y1, z0), pr.p(x1, y1, z1), pr.p(x0, y1, z1)]), with: .color(left))
        context.fill(polygon([pr.p(x1, y0, z0), pr.p(x1, y1, z0), pr.p(x1, y1, z1), pr.p(x1, y0, z1)]), with: .color(right))
        context.fill(polygon([pr.p(x0, y0, z1), pr.p(x1, y0, z1), pr.p(x1, y1, z1), pr.p(x0, y1, z1)]), with: .color(top))
    }

    /// 画面の上で小さな立方体（運んでいる商品など）。b は底の真ん中
    static func cube(_ context: inout GraphicsContext, at b: CGPoint, size s: CGFloat, height h: CGFloat, color: Color,
                     stripe: Color? = nil) {
        let top = [CGPoint(x: b.x, y: b.y - h - s / 4), CGPoint(x: b.x + s / 2, y: b.y - h),
                   CGPoint(x: b.x, y: b.y - h + s / 4), CGPoint(x: b.x - s / 2, y: b.y - h)]
        let left = [CGPoint(x: b.x - s / 2, y: b.y - h), CGPoint(x: b.x, y: b.y - h + s / 4),
                    CGPoint(x: b.x, y: b.y + s / 4), CGPoint(x: b.x - s / 2, y: b.y)]
        let right = [CGPoint(x: b.x + s / 2, y: b.y - h), CGPoint(x: b.x, y: b.y - h + s / 4),
                     CGPoint(x: b.x, y: b.y + s / 4), CGPoint(x: b.x + s / 2, y: b.y)]
        context.fill(polygon(left), with: .color(color))
        context.fill(polygon(left), with: .color(.black.opacity(0.18)))
        context.fill(polygon(right), with: .color(color))
        context.fill(polygon(right), with: .color(.black.opacity(0.06)))
        if let stripe {
            let mid = h * 0.45
            context.fill(polygon([CGPoint(x: b.x - s / 2, y: b.y - mid - h * 0.12), CGPoint(x: b.x, y: b.y - mid + s / 4 - h * 0.12),
                                  CGPoint(x: b.x, y: b.y - mid + s / 4 + h * 0.12), CGPoint(x: b.x - s / 2, y: b.y - mid + h * 0.12)]),
                         with: .color(stripe))
            context.fill(polygon([CGPoint(x: b.x + s / 2, y: b.y - mid - h * 0.12), CGPoint(x: b.x, y: b.y - mid + s / 4 - h * 0.12),
                                  CGPoint(x: b.x, y: b.y - mid + s / 4 + h * 0.12), CGPoint(x: b.x + s / 2, y: b.y - mid + h * 0.12)]),
                         with: .color(stripe.opacity(0.85)))
        }
        context.fill(polygon(top), with: .color(color))
        context.fill(polygon(top), with: .color(.white.opacity(0.2)))
    }

    private static let wallColor = Color(red: 0.98, green: 0.82, blue: 0.68)
    private static let floorA = Color(red: 0.93, green: 0.89, blue: 0.8)
    private static let floorB = Color(red: 0.9, green: 0.85, blue: 0.76)
    private static let shirts: [Color] = [
        Color(red: 0.35, green: 0.6, blue: 0.9), Color(red: 0.95, green: 0.45, blue: 0.4), Color(red: 0.5, green: 0.75, blue: 0.4),
        Color(red: 0.95, green: 0.75, blue: 0.3), Color(red: 0.7, green: 0.5, blue: 0.85), Color(red: 0.3, green: 0.75, blue: 0.75),
        Color(red: 0.95, green: 0.6, blue: 0.75), Color(red: 0.55, green: 0.55, blue: 0.6),
    ]

    @MainActor
    static func draw(_ context: inout GraphicsContext, size: CGSize, game: MartGame, camera: CGPoint, time: Double) {
        let w = min(size.width / 6.2, 80)
        let target = CGPoint(x: size.width / 2, y: size.height * 0.55)
        let origin = CGPoint(x: target.x - (camera.x - camera.y) * w / 2, y: target.y - (camera.x + camera.y) * w / 4)
        let pr = Projection(w: w, u: w * 0.55, origin: origin)

        // 外の地面
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(red: 0.55, green: 0.8, blue: 0.4)))
        context.fill(polygon([pr.p(14.5, -2), pr.p(19, -2), pr.p(19, 13), pr.p(14.5, 13)]),
                     with: .color(Color(red: 0.8, green: 0.8, blue: 0.78)))
        // 床（市松模様）
        let floor = MartGame.floor
        context.fill(polygon([pr.p(0, 0), pr.p(floor.maxX, 0), pr.p(floor.maxX, floor.maxY), pr.p(0, floor.maxY)]),
                     with: .color(floorA))
        for gx in 0..<Int(floor.maxX) {
            for gy in 0..<Int(floor.maxY) where (gx + gy) % 2 == 0 {
                let x = CGFloat(gx), y = CGFloat(gy)
                context.fill(polygon([pr.p(x, y), pr.p(x + 1, y), pr.p(x + 1, y + 1), pr.p(x, y + 1)]), with: .color(floorB))
            }
        }
        // 奥の壁 2 枚
        let wallH: CGFloat = 2.4
        context.fill(polygon([pr.p(0, 0), pr.p(floor.maxX, 0), pr.p(floor.maxX, 0, wallH), pr.p(0, 0, wallH)]),
                     with: .color(wallColor))
        context.fill(polygon([pr.p(0, 0), pr.p(0, floor.maxY), pr.p(0, floor.maxY, wallH), pr.p(0, 0, wallH)]),
                     with: .color(wallColor.opacity(0.85)))
        context.fill(polygon([pr.p(0, 0), pr.p(0, floor.maxY), pr.p(0, floor.maxY, wallH), pr.p(0, 0, wallH)]),
                     with: .color(.black.opacity(0.06)))
        context.fill(polygon([pr.p(-0.3, -0.3, wallH), pr.p(floor.maxX, -0.3, wallH), pr.p(floor.maxX, 0, wallH), pr.p(0, 0, wallH),
                              pr.p(0, floor.maxY, wallH), pr.p(-0.3, floor.maxY, wallH)]),
                     with: .color(Color(red: 0.85, green: 0.65, blue: 0.5)))
        // 看板と倉庫の扉
        let sign = context.resolve(Text("MACHIKADO MART").font(.system(size: w * 0.32, weight: .black, design: .rounded))
            .foregroundColor(Color(red: 0.9, green: 0.35, blue: 0.2)))
        context.draw(sign, at: pr.p(7, 0, 1.7))
        context.fill(polygon([pr.p(0, 4.5, 0), pr.p(0, 6.5, 0), pr.p(0, 6.5, 1.8), pr.p(0, 4.5, 1.8)]),
                     with: .color(Color(red: 0.4, green: 0.45, blue: 0.5)))
        for k in 1..<6 {
            var line = Path()
            line.move(to: pr.p(0, 4.5, CGFloat(k) * 0.3))
            line.addLine(to: pr.p(0, 6.5, CGFloat(k) * 0.3))
            context.stroke(line, with: .color(.white.opacity(0.3)), lineWidth: 1)
        }

        // 床の上：解放マーク
        for (index, step) in game.visibleSteps {
            drawPad(&context, pr, step: step, paid: game.paidAmount(index), time: time)
        }
        // レジの立つ場所
        drawSpot(&context, pr, at: MartGame.cashierSpot, color: Color(red: 0.3, green: 0.75, blue: 0.4), symbol: "💰")

        // 立体：奥から順に
        enum Thing { case shelf(Int), supply(MartProduct), counter, cash, person(MartWalker, Int, Bool, MartCustomer?) }
        var things: [(CGFloat, Thing)] = []
        for product in game.unlockedProducts {
            let rect = MartGame.shelfRect(product.rawValue)
            things.append((rect.midX + rect.midY, .shelf(product.rawValue)))
            let spot = MartGame.supplySpot(product.rawValue)
            things.append((spot.x + spot.y, .supply(product)))
        }
        things.append((MartGame.counter.midX + MartGame.counter.midY, .counter))
        things.append((MartGame.cashSpot.x + MartGame.cashSpot.y, .cash))
        things.append((game.player.pos.x + game.player.pos.y, .person(game.player, -1, true, nil)))
        for customer in game.customers {
            things.append((customer.walker.pos.x + customer.walker.pos.y, .person(customer.walker, customer.shirt, false, customer)))
        }
        for helper in game.helpers {
            things.append((helper.walker.pos.x + helper.walker.pos.y, .person(helper.walker, -2, false, nil)))
        }
        if game.hasCashier {
            things.append((MartGame.cashierSpot.x + MartGame.cashierSpot.y,
                           .person(MartWalker(pos: MartGame.cashierSpot, facing: -1), -2, false, nil)))
        }
        things.sort { $0.0 < $1.0 }
        for (_, thing) in things {
            switch thing {
            case .shelf(let k):
                drawShelf(&context, pr, k: k, stock: game.stock[k])
            case .supply(let product):
                drawSupply(&context, pr, product: product)
            case .counter:
                drawCounter(&context, pr, serving: game.serving)
            case .cash:
                drawCash(&context, pr, amount: game.cash)
            case .person(let walker, let shirt, let isPlayer, let customer):
                drawPerson(&context, pr, walker: walker, shirt: shirt, isPlayer: isPlayer, time: time)
                if let customer { drawBubble(&context, pr, customer: customer, stock: game.stock[customer.product.rawValue]) }
            }
        }
        // 運べる数がいっぱいのとき
        if game.player.carry.count >= game.capacity {
            let head = pr.p(game.player.pos.x, game.player.pos.y, 1.2 + CGFloat(game.player.carry.count) * 0.27)
            let label = context.resolve(Text("MAX").font(.system(size: w * 0.28, weight: .black)).foregroundColor(.red))
            context.draw(label, at: CGPoint(x: head.x, y: head.y - w * 0.25))
        }
    }

    // MARK: 部品

    private static func drawPad(_ context: inout GraphicsContext, _ pr: Projection, step: MartStep, paid: Int, time: Double) {
        let rect: CGRect
        if case .shelf(let k) = step.kind {
            rect = MartGame.shelfRect(k).insetBy(dx: -0.15, dy: -0.15)
        } else {
            rect = CGRect(x: step.pos.x - 0.7, y: step.pos.y - 0.7, width: 1.4, height: 1.4)
        }
        let outline = polygon([pr.p(rect.minX, rect.minY), pr.p(rect.maxX, rect.minY), pr.p(rect.maxX, rect.maxY), pr.p(rect.minX, rect.maxY)])
        context.fill(outline, with: .color(.white.opacity(0.35)))
        // 払った分だけ、手前から塗る
        let fraction = CGFloat(paid) / CGFloat(step.cost)
        if fraction > 0 {
            let y = rect.maxY - rect.height * fraction
            context.fill(polygon([pr.p(rect.minX, y), pr.p(rect.maxX, y), pr.p(rect.maxX, rect.maxY), pr.p(rect.minX, rect.maxY)]),
                         with: .color(Color(red: 0.3, green: 0.8, blue: 0.35).opacity(0.7)))
        }
        let pulse = 0.7 + 0.3 * sin(time * 4)
        context.stroke(outline, with: .color(.white.opacity(pulse)), style: StrokeStyle(lineWidth: 3, dash: [8, 6]))
        let center = pr.p(rect.midX, rect.midY)
        let title = context.resolve(Text(step.title).font(.system(size: pr.w * 0.2, weight: .heavy, design: .rounded))
            .foregroundColor(Color(red: 0.25, green: 0.25, blue: 0.3)))
        context.draw(title, at: CGPoint(x: center.x, y: center.y - pr.w * 0.14))
        let price = context.resolve(Text("💵 \(step.cost - paid)").font(.system(size: pr.w * 0.24, weight: .black, design: .rounded))
            .foregroundColor(Color(red: 0.15, green: 0.5, blue: 0.2)))
        context.draw(price, at: CGPoint(x: center.x, y: center.y + pr.w * 0.12))
    }

    private static func drawSpot(_ context: inout GraphicsContext, _ pr: Projection, at point: CGPoint, color: Color, symbol: String) {
        let r: CGFloat = 0.5
        let outline = polygon([pr.p(point.x - r, point.y - r), pr.p(point.x + r, point.y - r),
                               pr.p(point.x + r, point.y + r), pr.p(point.x - r, point.y + r)])
        context.fill(outline, with: .color(color.opacity(0.35)))
        context.stroke(outline, with: .color(color), lineWidth: 2)
    }

    private static func drawShelf(_ context: inout GraphicsContext, _ pr: Projection, k: Int, stock: Int) {
        guard let product = MartProduct(rawValue: k) else { return }
        let rect = MartGame.shelfRect(k)
        // 影
        context.fill(polygon([pr.p(rect.minX + 0.1, rect.maxY), pr.p(rect.maxX + 0.1, rect.maxY), pr.p(rect.maxX + 0.1, rect.maxY + 0.15),
                              pr.p(rect.minX + 0.1, rect.maxY + 0.15)]), with: .color(.black.opacity(0.1)))
        box(&context, pr, rect, z0: 0, z1: 0.9, top: Color(white: 0.96), left: Color(white: 0.78), right: Color(white: 0.88))
        // 棚の段（手前の面に線）
        for z in [0.3, 0.6] as [CGFloat] {
            var line = Path()
            line.move(to: pr.p(rect.minX, rect.maxY, z))
            line.addLine(to: pr.p(rect.maxX, rect.maxY, z))
            context.stroke(line, with: .color(Color(white: 0.6)), lineWidth: 1.5)
        }
        // 商品：上に 4×2 で並べる
        let s = pr.w * 0.27
        for index in 0..<min(stock, MartGame.shelfCapacity) {
            let row = index / 4, col = index % 4
            let x = rect.minX + 0.25 + CGFloat(col) * 0.37
            let y = rect.minY + 0.2 + CGFloat(1 - row) * 0.4
            cube(&context, at: pr.p(x, y, 0.9), size: s, height: s * 0.9, color: product.color, stripe: product.accent)
        }
        // 名札
        let label = context.resolve(Text(product.label).font(.system(size: pr.w * 0.16, weight: .black)).foregroundColor(Color(white: 0.3)))
        context.draw(label, at: pr.p(rect.midX, rect.maxY, 0.15))
        if stock == 0 {
            let empty = context.resolve(Text("からっぽ").font(.system(size: pr.w * 0.17, weight: .heavy)).foregroundColor(.red))
            context.draw(empty, at: pr.p(rect.midX, rect.midY, 1.6))
        }
    }

    private static func drawSupply(_ context: inout GraphicsContext, _ pr: Projection, product: MartProduct) {
        let spot = MartGame.supplySpot(product.rawValue)
        let rect = CGRect(x: spot.x - 0.55, y: spot.y - 0.55, width: 1.1, height: 1.1)
        box(&context, pr, rect, z0: 0, z1: 0.12, top: Color(red: 0.75, green: 0.55, blue: 0.35),
            left: Color(red: 0.55, green: 0.38, blue: 0.22), right: Color(red: 0.65, green: 0.46, blue: 0.28))
        let s = pr.w * 0.3
        for (ox, oy) in [(-0.22, -0.22), (0.22, -0.22), (-0.22, 0.22), (0.22, 0.22)] as [(CGFloat, CGFloat)] {
            for level in 0..<2 {
                cube(&context, at: pr.p(spot.x + ox, spot.y + oy, 0.12 + CGFloat(level) * 0.5), size: s, height: s * 0.95,
                     color: product.color, stripe: product.accent)
            }
        }
        let label = context.resolve(Text(product.label).font(.system(size: pr.w * 0.15, weight: .black)).foregroundColor(.white))
        let at = pr.p(spot.x, spot.y, 1.7)
        let measured = label.measure(in: CGSize(width: 300, height: 50))
        context.fill(Path(roundedRect: CGRect(x: at.x - measured.width / 2 - 6, y: at.y - measured.height / 2 - 2,
                                              width: measured.width + 12, height: measured.height + 4), cornerRadius: 6),
                     with: .color(product.accent.opacity(0.9)))
        context.draw(label, at: at)
    }

    private static func drawCounter(_ context: inout GraphicsContext, _ pr: Projection, serving: Double) {
        let rect = MartGame.counter
        box(&context, pr, rect, z0: 0, z1: 0.85, top: Color(white: 0.95), left: Color(red: 0.85, green: 0.3, blue: 0.3),
            right: Color(red: 0.95, green: 0.4, blue: 0.38))
        // レジ
        let register = CGRect(x: rect.minX + 0.25, y: rect.midY - 0.3, width: 0.5, height: 0.6)
        box(&context, pr, register, z0: 0.85, z1: 1.15, top: Color(white: 0.3), left: Color(white: 0.15), right: Color(white: 0.22))
        context.fill(polygon([pr.p(register.minX + 0.1, register.minY + 0.1, 1.15), pr.p(register.maxX - 0.1, register.minY + 0.1, 1.15),
                              pr.p(register.maxX - 0.1, register.minY + 0.1, 1.45), pr.p(register.minX + 0.1, register.minY + 0.1, 1.45)]),
                     with: .color(Color(red: 0.3, green: 0.85, blue: 0.5)))
        if serving > 0 {
            let at = pr.p(rect.midX, rect.midY, 2.2)
            let r = pr.w * 0.18
            var ring = Path()
            ring.addArc(center: at, radius: r, startAngle: .degrees(-90), endAngle: .degrees(-90 + 360 * serving), clockwise: false)
            context.stroke(ring, with: .color(Color(red: 0.3, green: 0.8, blue: 0.35)), lineWidth: 5)
        }
    }

    private static func drawCash(_ context: inout GraphicsContext, _ pr: Projection, amount: Int) {
        guard amount > 0 else { return }
        let bills = min(amount / 3 + 1, 36)
        let s = pr.w * 0.36
        for index in 0..<bills {
            let column = index / 12, level = index % 12
            let spot = MartGame.cashSpot
            let at = pr.p(spot.x - 0.35 + CGFloat(column) * 0.35, spot.y, CGFloat(level) * 0.07)
            cube(&context, at: at, size: s, height: s * 0.12, color: Color(red: 0.35, green: 0.75, blue: 0.35))
        }
    }

    private static func drawPerson(_ context: inout GraphicsContext, _ pr: Projection, walker: MartWalker, shirt: Int,
                                   isPlayer: Bool, time: Double) {
        let w = pr.w
        let base = pr.p(walker.pos.x, walker.pos.y)
        // 影
        context.fill(Path(ellipseIn: CGRect(x: base.x - w * 0.2, y: base.y - w * 0.07, width: w * 0.4, height: w * 0.14)),
                     with: .color(.black.opacity(0.18)))
        let swing = walker.moving ? CGFloat(sin(walker.step * 9)) * w * 0.05 : 0
        let bob = walker.moving ? abs(CGFloat(sin(walker.step * 9))) * w * 0.03 : 0
        let skin = Color(red: 0.45, green: 0.6, blue: 0.85)
        let body: Color
        let legs: Color
        switch shirt {
        case -1:
            body = Color(red: 0.2, green: 0.45, blue: 0.85)
            legs = Color(red: 0.15, green: 0.18, blue: 0.3)
        case -2:
            body = Color(red: 0.2, green: 0.6, blue: 0.35)
            legs = Color(red: 0.15, green: 0.25, blue: 0.2)
        default:
            body = shirts[shirt % shirts.count]
            legs = Color(red: 0.3, green: 0.32, blue: 0.4)
        }
        let staff = shirt < 0
        let headColor = staff ? Color(red: 0.2, green: 0.2, blue: 0.25) : skin
        // 足
        for (side, offset) in [(-1.0, swing), (1.0, -swing)] as [(CGFloat, CGFloat)] {
            context.fill(Path(roundedRect: CGRect(x: base.x + side * w * 0.06 - w * 0.04 + offset * 0.5, y: base.y - w * 0.24,
                                                  width: w * 0.08, height: w * 0.24), cornerRadius: w * 0.04),
                         with: .color(legs))
        }
        let top = base.y - bob
        // 体
        context.fill(Path(roundedRect: CGRect(x: base.x - w * 0.13, y: top - w * 0.58, width: w * 0.26, height: w * 0.38),
                          cornerRadius: w * 0.11), with: .color(body))
        // エプロン（店員）
        if staff {
            context.fill(Path(roundedRect: CGRect(x: base.x - w * 0.1, y: top - w * 0.46, width: w * 0.2, height: w * 0.25),
                              cornerRadius: w * 0.05), with: .color(.white.opacity(0.85)))
        }
        // 頭
        let head = CGPoint(x: base.x, y: top - w * 0.72)
        context.fill(Path(ellipseIn: CGRect(x: head.x - w * 0.13, y: head.y - w * 0.13, width: w * 0.26, height: w * 0.26)),
                     with: .color(headColor))
        // 帽子（店員）
        if staff {
            let capColor = isPlayer ? Color(red: 0.2, green: 0.45, blue: 0.85) : Color(red: 0.2, green: 0.6, blue: 0.35)
            context.fill(Path(ellipseIn: CGRect(x: head.x - w * 0.14, y: head.y - w * 0.16, width: w * 0.28, height: w * 0.16)),
                         with: .color(capColor))
            context.fill(Path(ellipseIn: CGRect(x: head.x + walker.facing * w * 0.04 - w * 0.12, y: head.y - w * 0.07,
                                                width: w * 0.24, height: w * 0.07)), with: .color(capColor))
        }
        // 運んでいる商品（手の前に高く積む）
        if !walker.carry.isEmpty {
            let s = w * 0.3
            let hand = CGPoint(x: base.x + walker.facing * w * 0.16, y: top - w * 0.42)
            for (index, product) in walker.carry.enumerated() {
                cube(&context, at: CGPoint(x: hand.x, y: hand.y - CGFloat(index) * s * 0.55), size: s, height: s * 0.55,
                     color: product.color, stripe: product.accent)
            }
            // 手
            context.fill(Path(ellipseIn: CGRect(x: hand.x - w * 0.05, y: hand.y - w * 0.03, width: w * 0.1, height: w * 0.08)),
                         with: .color(headColor))
        }
    }

    private static func drawBubble(_ context: inout GraphicsContext, _ pr: Projection, customer: MartCustomer, stock: Int) {
        let w = pr.w
        let base = pr.p(customer.walker.pos.x, customer.walker.pos.y)
        let at = CGPoint(x: base.x, y: base.y - w * 1.15)
        let text: String
        let color: Color
        switch customer.phase {
        case .toShelf, .shopping:
            guard customer.phase == .toShelf || stock == 0 || customer.got < customer.want else { return }
            text = "\(customer.want - customer.got)"
            color = customer.product.color
        case .toQueue, .queued:
            text = "💵"
            color = .white
        case .leaving:
            return
        }
        let box = CGRect(x: at.x - w * 0.24, y: at.y - w * 0.2, width: w * 0.48, height: w * 0.36)
        context.fill(Path(roundedRect: box, cornerRadius: w * 0.1), with: .color(.white))
        context.fill(polygon([CGPoint(x: at.x - w * 0.06, y: box.maxY), CGPoint(x: at.x + w * 0.06, y: box.maxY),
                              CGPoint(x: at.x, y: box.maxY + w * 0.08)]), with: .color(.white))
        if customer.phase == .toShelf || customer.phase == .shopping {
            cube(&context, at: CGPoint(x: at.x - w * 0.08, y: at.y + w * 0.08), size: w * 0.18, height: w * 0.16,
                 color: color, stripe: customer.product.accent)
            let count = context.resolve(Text(text).font(.system(size: w * 0.16, weight: .black)).foregroundColor(.black))
            context.draw(count, at: CGPoint(x: at.x + w * 0.11, y: at.y))
        } else {
            let label = context.resolve(Text(text).font(.system(size: w * 0.2)))
            context.draw(label, at: at)
        }
    }
}
